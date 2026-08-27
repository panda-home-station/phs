# OpenNAS 系统级 AI 助手 —— Pipa 方案

## 1. 背景与目标

### 1.1 项目背景
- **OpenNAS / Panda Home Station (PHS)**：web desktop 桌面访问系统
- **pandacode/**：完整移植自 OpenAI Codex CLI (`rust-v0.144.1`) 的 `codex-rs/tui` 这部分代码（也就是 CLI 的 TUI 前端），并自行加了多 provider 抽象层
- **tmp/opencode、tmp/openclaw**：两个独立的开源 agent 系统，作为方案参考（pandacode 与它们没有代码继承关系）
- **当前 webdesktop/apps/agent/**：AI 助手占位（仅 "开发中…" 字样）
- **当前 webdesktop/src/desktop/components/QuickAgentDialog.tsx**：已实现 Copilot 浮动窗口雏形，但只跑 mock state

### 1.2 需求
给 OpenNAS 做一个**系统级别的 AI 助手**，像 Windows Copilot 一样作为系统级 agent。
系统目标：**AI Based WebOS**。

命名采用 **Pipa**（中文可写作「琵琶」，也可只用 Pipa），命名映射与原则详见后续 §4。

---

## 2. 架构总览

### 2.1 系统拓扑

```
┌────────────────── webdesktop (浏览器, React) ──────────────────┐
│                                                                │
│   ┌────────────────────────┐  ┌─────────────────────────────┐ │
│   │ QuickPipaDialog        │  │ apps/pipa (全屏 AI 工作台) │ │
│   │  - Cmd+K 唤起          │  │  - 多 thread / 多 session   │ │
│   │  - 浮动 Copilot        │  │  - 文件 diff / 终端 / 工具  │ │
│   └─────────────┬──────────┘  └──────────────┬──────────────┘ │
│                 │                            │                 │
│                 │  shared/sdk/pipa.ts        │                 │
│                 │   CRUD: client.call('pipa.*', ...)         │
│                 │   流式: core.subscribe('pipa.stream')       │
│                 └─────────────┬──────────────┘                 │
└───────────────────────────────┼────────────────────────────────┘
                                │  wss://nas/api/v25.10.2
                                │  (复用 middleware 主 RPC,无新端口)
                                ▼
┌────────────────────────────────────────────────────────────────┐
│ TrueNAS middleware  (Python) — 127.0.0.1:6000                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ PipaStreamService                                       │  │
│  │   - pipa.stream.connect / send / disconnect             │  │
│  │     走主 RPC,中间用 should_send_event()                 │  │
│  │     按 session_id 单播                                    │  │
│  │   - 接 event channel 'pipa.stream' 单向广播 daemon 帧    │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ PipaSupervisorService                                   │  │
│  │   - 确保每用户 daemon 进程跑起来:                          │  │
│  │     loginctl enable-linger <uid>                        │  │
│  │     渲染 ~/.config/systemd/user/pipa.service             │  │
│  │     mkdir -p ~/.panda                                   │  │
│  │     machinectl shell <user>@.host systemctl --user start │  │
│  │     探 /run/user/<uid>/pipa.sock                        │  │
│  │   - 全程不动 main.py / pre_freeze_setup                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ PipaUserPrefsService (CRUDService,EncryptedText)         │  │
│  │ PipaStatusService (per-caller 查询)                       │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────┬────────────────────────────────┘
                                │  私有 DBus + machinectl shell
                                │  machinectl shell <user>@.host
                                │  → systemd --user instance
                                ▼
┌────────────────────────────────────────────────────────────────┐
│ 每用户独立进程:                                               │
│   panda-app-server (Rust)                                     │
│   - 用户 <user> 在 systemd --user instance 下跑               │
│   - 监听 unix:///run/user/<uid>/pipa.sock                     │
│   - 读 ~/.panda/  (AuthManager / ConfigManager / threads)     │
│   - 内部 thread/turn/item + MCP + provider 抽象全部复用        │
│                                                                 │
│ 注意:pandacode 仓库本身一行未改。                             │
│ 全部 supervisor / event channel 逻辑都在 middleware 侧。      │
└────────────────────────────────────────────────────────────────┘
```

### 2.2 三大核心原则

#### 原则 ① Per-user daemon process = per-user singletons
照 POSIX 标准模型（`sudo`、`sshd`、`podman rootless`、`gnome-software` 都是这样），
每 TrueNAS 用户一个独立 `panda-app-server` 进程跑在 `systemd --user` instance 下，UID = caller。
pandacode daemon 内部所有 singleton（`AuthManager` / `ConfigManager` / skill caches / thread store）
在进程启动时 read 一次 — **进程隔离 = 数据隔离**。

middleware 是 supervisor（[`PipaSupervisorService`](middleware/src/middlewared/middlewared/plugins/pipa_supervisor.py)）：
```python
class PipaSupervisorService(Service):
    """Per-user panda-app-server supervisor。"""

    @private
    async def ensure_running_for_caller(self, app):
        """StreamService.connect 必调:确保 caller 的 daemon 进程在跑。"""
        # 1. username = app.authenticated_credentials.dump()['username']
        # 2. user = await self.middleware.call('user.get_user_obj', {'username': username})
        # 3. uid, pw_dir = user['pw_uid'], user['pw_dir']
        # 4. await self._ensure_linger(uid)
        # 5. await self._write_unit_file(uid, pw_dir)
        # 6. await self._ensure_panda_home(uid, pw_dir, username)
        # 7. await self._start_unit(uid, username)
        # 8. await self._wait_socket(uid, timeout=5.0)
```

daemon 挂了 / 被 `systemctl --user stop` 了，supervisor 重启。middleware 不感知启动细节。

#### 原则 ② 走 middleware 单一端口，不开新端口
`panda-app-server` **不暴露任何外部端口**。所有外部访问（webdesktop 本地、FastConnect 远端）都通过 middleware 的 **127.0.0.1:6000**：

- `/api/current` —— 普通 CRUD（`pipa.user_prefs.*`、`pipa.status`、`pipa.supervisor.status`）
- `/api/current` —— 流式 turn 也走主 RPC（`pipa.stream.connect` / `send` / `disconnect` + `core.subscribe('pipa.stream')` event channel）

**TLS / Origin / 鉴权 / 审计 / 限流 / 反代全部复用现有 middleware 设施。**

> 早期计划走 `/_plugins/pipa/ws` 独立 WS 端点 —— 已废。原因：[main.py:657](middleware/src/middlewared/middlewared/main.py#L657) 的 `/_plugins/{plugin}/{route}` 挂载要 `pre_freeze_setup` 钩子在 aiohttp freeze router 前挂路由，违反"main.py 不动"原则。改走 event channel 后 middleware 主 RPC 一条隧道就够，与 SMB / Docker / VM / FC 等同级，FastConnect 不需要为 Pipa 改任何代码。

#### 原则 ③ 身份 / 权限 / 设置深度走 middleware
- **身份识别**：middleware 在 `pipa.stream.connect` 必读 caller（用户 + roles），`ensure_running_for_caller` 按 caller UID 拉起对应 daemon
- **权限**：pipa 想执行任何 NAS 操作都通过 HTTP 调回 middleware 的 `pool.*` / `sharing.*` 等接口，**带着 caller 的 session token** —— middleware 的 RBAC 天然落地
- **审计**：pipa 触发的每个 NAS 操作由 middleware 的 `audit.py` 自动记录
- **设置**：用户选 provider / 存 API key 走 middleware 的 `pipa_user_prefs` 数据表（`EncryptedText` 加密）
- **daemon 侧 secrets**：用户的 provider API key 进 daemon 的 `~/.panda/auth.json`（per-user daemon 自己管理，`PANDA_HOME` per-process）
- **进度**：长任务走 middleware 的 jobs 系统

---

## 3. 详细设计

### 3.1 pandacode 后端：零代码改动

**核心决策**：pandacode 仓库零改动（仅 wire-protocol 字段补齐由客户端承担）。

- 进程隔离 = 数据隔离：每用户一个 `panda-app-server` 进程，启动时 read 一次 `~/.panda/` → per-user `AuthManager` / `ConfigManager` / skill caches
- 协议不变：`InitializeParams` 的 `user_home` 字段 daemon 早已支持，supervisor 在进程启动时把 `PANDA_HOME=/home/<user>/.panda` 塞进环境变量即可
- WebSocket transport 不变：`AppServerTransport::from_str` 已经支持 `unix:///run/user/<uid>/pipa.sock`，无需任何代码改动

后续若要更深集成（NAS skills / NAS tools / WebDesktop session source 等）才 fork，但保持"只加可选项、不改主流程"。

**pandacode 配置启动方式**（由 systemd per-user unit 指定）：
```bash
/usr/sbin/panda-app-server \
    --listen unix:///run/user/%U/pipa.sock \
    --session-source vscode   # 暂用 vscode 复用 enum;后续可加 WebDesktop
```

[panda-rs/app-server/src/main.rs](pandacode/panda-rs/app-server/src/main.rs) 通过 `--listen AppServerTransport` 接收参数，参数解析在 [panda-rs/app-server/src/transport.rs](pandacode/panda-rs/app-server/src/transport.rs)（re-export 自 `panda_app_server_transport` crate，定义 `AppServerTransport::DEFAULT_LISTEN_URL` 等常量）。两种实现都已支持 `unix://` 路径（`--listen unix:///run/user/<uid>/pipa.sock`），无需任何代码改动。

**当前范围**：pandacode 仅作为流式对话后端（无 NAS 上下文、无 NAS tools）
**后续范围**：如需更深集成，再考虑在 pandacode 加 `panda-home/nas_context/`、`skills/nas/`、`tools/nas_*` 等模块——但当前不阻塞。

> 早期曾试图在 `InitializeParams.user_home` 做"per-connection HOME"（见 ADR-008 旧版本），实测后放弃 — 因为 pandacode daemon 启动时已经把 `~/.panda/` 全部 load 到内存（`AuthManager` 单例），per-connection HOME 救不了 thread store 冲突。改 per-user daemon 进程后，整块问题消失。

### 3.2 systemd 单元：per-user template（由 middleware 渲染）

#### 3.2.1 单元模板（middleware 源码内 textwrap.dedent 字符串）

middleware 在 [`pipa_supervisor.py`](middleware/src/middlewared/middlewared/plugins/pipa_supervisor.py) 持有模板常量，渲染到每用户自己的 `~/.config/systemd/user/pipa.service`：

```ini
[Unit]
Description=Pipa - per-user pandacode app-server (OpenNAS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PANDA_HOME=%h/.panda
Environment=PANDA_NO_UPDATE_CHECK=1
ExecStart=/usr/sbin/panda-app-server \
    --listen unix:///run/user/%U/pipa.sock \
    --session-source vscode
Restart=on-failure
RestartSec=5s
TimeoutStopSec=30s

RuntimeDirectory=pipa
RuntimeDirectoryMode=0700

NoNewPrivileges=true
ProtectSystem=strict
# ProtectHome DROPPED — per-user daemon needs %h read-write
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

IPAddressDeny=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

StandardOutput=journal
StandardError=journal
SyslogIdentifier=pipa-user

[Install]
WantedBy=default.target
```

> **关键差异**（vs Slice 0 的 system unit）：
> - 不再有 `User=root` —— 由 systemd --user 上下文提供
> - 不再有 `ProtectHome=true` —— daemon 要读 `~/.panda/`
> - `%h` 展开为用户 home，`%U` 展开为 UID
> - 文件 owner 必须 = 用户，否则 systemd user instance 拒加载；supervisor 用 `sudo -u <user> tee` 写入

#### 3.2.2 tmpfiles（无需）

每用户 daemon 用 `RuntimeDirectory=pipa` 自动建 `/run/user/<uid>/pipa/`。
无系统级 tmpfiles（旧的 `/usr/lib/tmpfiles.d/pipa.conf` 已删）。

#### 3.2.3 启动顺序
- pandacode daemon 不依赖 middleware（middleware 只是按需 `ensure_running_for_caller`）
- middleware 不阻塞 daemon 启动；但 `pipa.stream.connect` 必等 `/run/user/<uid>/pipa.sock` 出现才回 OK（最多 5s，超时报 "AI 助手暂未就绪"）

### 3.3 middleware 的 pipa 插件

#### 3.3.1 文件结构

```
middleware/src/middlewared/middlewared/plugins/
├── pipa.py                  # 业务逻辑:UserPrefs / Status / Stream(事件 channel 单播)
├── pipa_supervisor.py       # 进程编排:per-user systemd --user 生命周期

middleware/src/middlewared/middlewared/api/v26_0_0/
└── pipa.py                  # Pydantic schemas
```

#### 3.3.2 PipaSupervisorService（核心：per-user 生命周期）

完整实现见 [`pipa_supervisor.py`](middleware/src/middlewared/middlewared/plugins/pipa_supervisor.py)。要点：

```python
import os
import pwd
import subprocess
import textwrap

from middlewared.service import Service, private, job
from middlewared.service_exception import CallError


def pipa_socket_for_user(uid: int) -> str:
    """每用户 unix socket 路径。"""
    return f'/run/user/{uid}/pipa.sock'


class PipaSupervisorService(Service):
    """Per-user panda-app-server supervisor。"""

    class Config:
        namespace = 'pipa.supervisor'
        cli_namespace = 'pipa.supervisor'

    PIPA_USER_SERVICE_TEMPLATE = textwrap.dedent('''\
        [Unit]
        Description=Pipa - per-user pandacode app-server (OpenNAS)
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        Environment=PANDA_HOME=%h/.panda
        Environment=PANDA_NO_UPDATE_CHECK=1
        ExecStart=/usr/sbin/panda-app-server \\
            --listen unix:///run/user/%U/pipa.sock \\
            --session-source vscode
        Restart=on-failure
        RestartSec=5s
        TimeoutStopSec=30s

        RuntimeDirectory=pipa
        RuntimeDirectoryMode=0700

        NoNewPrivileges=true
        ProtectSystem=strict
        PrivateTmp=true
        PrivateDevices=true
        ProtectKernelTunables=true
        ProtectKernelModules=true
        ProtectControlGroups=true

        IPAddressDeny=
        RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

        StandardOutput=journal
        StandardError=journal
        SyslogIdentifier=pipa-user

        [Install]
        WantedBy=default.target
    ''')

    _start_locks: dict[int, asyncio.Lock] = {}

    @private
    async def ensure_running_for_caller(self, app):
        """pipa.stream.connect 必调。返回 (uid, socket_path)。"""
        creds = app.authenticated_credentials
        if creds is None:
            raise CallError('Pipa requires authenticated caller')

        username = creds.dump().get('username')
        user_obj = await self.middleware.call(
            'user.get_user_obj', {'username': username},
        )
        uid = user_obj['pw_uid']
        pw_dir = user_obj['pw_dir']
        socket_path = pipa_socket_for_user(uid)

        # 并发去重:同一 uid 只跑一次 ensure_running 流程
        lock = self._start_locks.setdefault(uid, asyncio.Lock())
        async with lock:
            if not os.path.exists(socket_path):
                await self._ensure_linger(uid, username)
                await self._write_unit_file(uid, pw_dir, username)
                await self._ensure_panda_home(uid, pw_dir, username)
                await self._start_unit(uid, username)
                await self._wait_socket(uid, socket_path, timeout=5.0)

        return uid, socket_path

    async def _ensure_linger(self, uid: int, username: str):
        """loginctl enable-linger <uid> (idempotent)。"""
        proc = await self.middleware.run_in_thread(
            subprocess.run,
            ['loginctl', 'enable-linger', str(uid)],
            check=False, capture_output=True, text=True,
        )
        if proc.returncode != 0:
            self.logger.warning(
                'loginctl enable-linger %d failed: %s',
                uid, proc.stderr.strip(),
            )

    async def _write_unit_file(self, uid: int, pw_dir: str, username: str):
        """写入 ~/.config/systemd/user/pipa.service,owner = user。"""
        unit_dir = os.path.join(pw_dir, '.config', 'systemd', 'user')
        unit_path = os.path.join(unit_dir, 'pipa.service')

        def _do_write():
            subprocess.run(
                ['sudo', '-u', username, 'mkdir', '-p', unit_dir],
                check=True,
            )
            proc = subprocess.run(
                ['sudo', '-u', username, 'tee', unit_path],
                input=self.PIPA_USER_SERVICE_TEMPLATE.encode(),
                capture_output=True,
            )
            if proc.returncode != 0:
                self.logger.warning('Failed to write %s', unit_path)
        await self.middleware.run_in_thread(_do_write)

    async def _ensure_panda_home(self, uid: int, pw_dir: str, username: str):
        """daemon 拒启无 ~/.panda/,预创建 mode 0700。"""
        panda_home = os.path.join(pw_dir, '.panda')

        def _do_mkdir():
            proc = subprocess.run(
                ['sudo', '-u', username, 'mkdir', '-p', '-m', '0700', panda_home],
                check=False, capture_output=True, text=True,
            )
            if proc.returncode != 0:
                self.logger.warning(
                    'mkdir %s for %s failed: %s',
                    panda_home, username, proc.stderr.strip(),
                )
        await self.middleware.run_in_thread(_do_mkdir)

    async def _start_unit(self, uid: int, username: str):
        """machinectl shell <user>@.host systemctl --user start pipa.service。"""
        def _do_start():
            proc = subprocess.run(
                ['machinectl', 'shell',
                 f'{username}@.host',
                 'systemctl', '--user', 'start', 'pipa.service'],
                check=False, capture_output=True, text=True,
            )
            if proc.returncode != 0:
                self.logger.warning(
                    'start pipa.service for %d failed: %s',
                    uid, proc.stderr.strip(),
                )
        await self.middleware.run_in_thread(_do_start)

    async def _wait_socket(self, uid: int, socket_path: str, *, timeout: float):
        """轮询 socket 出现 + websockets.unix_connect 探活。
        compression 必须 None —— pandacode tokio_tungstenite 拒 permessage-deflate。"""
        import websockets
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if os.path.exists(socket_path):
                try:
                    async with websockets.unix_connect(
                        socket_path, compression=None,
                    ):
                        return
                except OSError:
                    pass
            await asyncio.sleep(0.05)
        raise CallError(f'Pipa daemon for uid {uid} not reachable at {socket_path}')

    @api_method(PipaSupervisorStatusArgs, PipaSupervisorStatusResult,
                roles=['PIPA_READ'])
    async def status(self, uid: int) -> dict:
        """Admin 诊断:查任意 uid 的 daemon 状态。"""
        socket_path = pipa_socket_for_user(uid)
        socket_exists = os.path.exists(socket_path)
        daemon_reachable = False
        if socket_exists:
            import websockets
            try:
                async with websockets.unix_connect(socket_path, compression=None):
                    daemon_reachable = True
            except OSError:
                pass

        unit_installed = self._unit_installed(uid)
        unit_state = await self._unit_state(uid)
        linger_enabled = self._linger_enabled(uid)

        return {
            'socket_path': socket_path,
            'socket_exists': socket_exists,
            'daemon_reachable': daemon_reachable,
            'unit_installed': unit_installed,
            'unit_state': unit_state,
            'linger_enabled': linger_enabled,
        }

    @staticmethod
    def _linger_enabled(uid: int) -> bool:
        proc = subprocess.run(
            ['loginctl', 'show-user', str(uid)],
            check=False, capture_output=True, text=True,
        )
        return 'Linger=yes' in proc.stdout

    @staticmethod
    def _unit_installed(uid: int) -> bool:
        try:
            entry = pwd.getpwuid(uid)
        except KeyError:
            return False
        return os.path.exists(
            os.path.join(entry.pw_dir, '.config', 'systemd', 'user', 'pipa.service'),
        )

    async def _unit_state(self, uid: int) -> Literal['active', 'inactive', 'failed', 'unknown']:
        try:
            entry = pwd.getpwuid(uid)
        except KeyError:
            return 'unknown'
        username = entry.pw_name

        def _do_query():
            proc = subprocess.run(
                ['machinectl', 'shell',
                 f'{username}@.host',
                 'systemctl', '--user', 'is-active', 'pipa.service'],
                check=False, capture_output=True, text=True,
            )
            if proc.returncode == 0:
                return proc.stdout.strip()
            return 'unknown'
        return await self.middleware.run_in_thread(_do_query)
```

#### 3.3.3 PipaStreamService（业务侧：事件 channel 单播）

`pipa.py` 走 middleware 标准 event channel（`pipa.stream`），不用 `/_plugins/*` raw WS。
完整实现见 [`pipa.py`](middleware/src/middlewared/middlewared/plugins/pipa.py)。要点：

```python
from dataclasses import dataclass


@dataclass
class _StreamSession:
    """每浏览器 WS 连接 = 一个 stream session,挂在 caller uid 上。"""
    session_id: str
    uid: int
    socket_path: str
    ws: websockets.WebSocketClientProtocol
    task: asyncio.Task


class PipaStreamService(Service):
    """把浏览器 WS ↔ caller uid 的 daemon unix socket 双向转发 NDJSON/JSON-RPC 帧。"""
    class Config:
        namespace = 'pipa.stream'
        private = True  # 不暴露给普通 client,RPC 入口走单独的 schema

    async def connect(self, app):
        """浏览器 ws_handler 必调。返回 session_id。"""
        creds = app.authenticated_credentials
        username = creds.dump()['username']

        uid, socket_path = await self.middleware.call(
            'pipa.supervisor.ensure_running_for_caller', app,
        )

        session_id = uuid.uuid4().hex
        ws = await websockets.unix_connect(
            socket_path, compression=None,
        )
        task = asyncio.create_task(
            self._daemon_reader_loop(session_id, uid, ws),
        )
        self._sessions[session_id] = _StreamSession(
            session_id=session_id, uid=uid, socket_path=socket_path,
            ws=ws, task=task,
        )
        return session_id

    async def send(self, session_id: str, frame: str):
        """浏览器 → daemon:browser 把单帧 JSON-RPC 帧发过来,转发到 unix socket。"""
        session = self._sessions.get(session_id)
        if session is None:
            raise CallError(f'Unknown session {session_id}')
        await session.ws.send(frame.rstrip('\n') + '\n')

    async def disconnect(self, session_id: str):
        session = self._sessions.pop(session_id, None)
        if session is None:
            return
        session.task.cancel()
        with contextlib.suppress(Exception):
            await session.ws.close()

    async def _daemon_reader_loop(self, session_id: str, uid: int, ws):
        """daemon → 浏览器:读 NDJSON 帧,用 event channel 单播给对应 session_id 的 WS。"""
        try:
            async for line in ws:
                self.middleware.send_event(
                    'pipa.stream',
                    f'{{"session_id": "{session_id}", "frame": {line.decode()}}}',
                )
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            # 通知浏览器端流断了
            self.middleware.send_event(
                'pipa.stream',
                f'{{"session_id": "{session_id}", "frame": {{"method": "session/closed"}}}}',
            )
            self._sessions.pop(session_id, None)


def setup(middleware):
    """事件 channel 注册:每次 daemon 有帧就广播,SDK 端按 session_id 过滤。"""
    middleware.event_register(
        'pipa.stream',
        text='Pipa stream events (per-session NDJSON frames from daemon)',
        role_prefix='SHARING_ADMIN',
    )
```

> 浏览器侧 SDK（见 §3.4.2）通过 `core.subscribe('pipa.stream')` 订阅事件，再用 `session_id` 过滤出属于自己的帧。多浏览器 tab 同时开不同 session 不会串流。

#### 3.3.4 PipaUserPrefsService / PipaStatusService

**重要 schema 演进**:`pipa_user_prefs` 已经从最初的"单行 user_id 唯一"演化成
multi-preset 模式(每个用户可拥有多行,`is_active=true` 至多一行,由 partial unique index 兜底)。
实现见 alembic `versions/26.0/2026-08-25_12-09_pipa_user_prefs_multi_and_notes.py`(Squash 干净)。

```python
class PipaUserPrefsModel(sa.Model):
    """用户偏好(multi-preset:每用户多行,is_active 至多一行)。"""
    __tablename__ = 'pipa_user_prefs'
    id = sa.Column(sa.Integer(), primary_key=True)
    user_id = sa.Column(sa.Integer(), sa.ForeignKey('account_bsdusers.id'),
                        nullable=False)
    provider = sa.Column(sa.String(64), nullable=True)
    model = sa.Column(sa.String(128), nullable=True)
    display_name = sa.Column(sa.String(128), nullable=True)  # 用户自命名,fallback 到 catalog
    base_url = sa.Column(sa.String(512), nullable=True)       # 可覆盖 catalog base_url
    wire_api = sa.Column(sa.String(16), nullable=True)        # 'responses'|'anthropic'|'chat'
    # api_key_encrypted 仍存在(为 webdesktop Settings 面板 + 测试连接);
    # 真正 daemon 用的 key 在 daemon 自己的 ~/.panda/auth.json
    api_key_encrypted = sa.Column(sa.EncryptedText(), nullable=True)
    enabled_skills = sa.Column(sa.JSON(), nullable=True)
    daily_token_quota = sa.Column(sa.Integer(), nullable=True)
    auto_approve_safe_ops = sa.Column(sa.Boolean(), default=False)
    is_active = sa.Column(sa.Boolean(), nullable=False, server_default='1')
    display_order = sa.Column(sa.Integer(), nullable=False, server_default='0')
    notes = sa.Column(sa.Text(), nullable=True)


class PipaUserPrefsService(CRUDService):
    class Config:
        namespace = 'pipa.user_prefs'
        datastore = 'pipa_user_prefs'
        role_prefix = 'SHARING_ADMIN'


class PipaStatusService(Service):
    """per-caller 查询:返回当前 caller 的 daemon 状态。"""
    class Config:
        namespace = 'pipa.status'

    @api_method(PipaStatusArgs, PipaStatusResult)
    async def status(self, app):
        creds = app.authenticated_credentials
        username = creds.dump()['username']
        user_obj = await self.middleware.call(
            'user.get_user_obj', {'username': username},
        )
        uid = user_obj['pw_uid']
        return await self.middleware.call('pipa.supervisor.status', uid)


# === 辅助 namespace ===

class PipaProviderCatalogService(Service):
    """返回 UI 可以选的所有 provider 模板(catalog 是 single source of truth)。"""
    class Config:
        namespace = 'pipa.provider_catalog'


class PipaTestProviderService(Service):
    """用当前/指定 provider + key 跑一个 model/list probe,验证可达性。
    用 open_transient_session(不走 _sessions,不会污染 stream 表)。"""
    class Config:
        namespace = 'pipa.test_provider'


class PipaListModelsService(Service):
    """直接打上游 GET {base_url}/models 拉模型列表(不走 daemon,UI 表单还没存的场景)。
    空列表 + note 说明协议无 catalogue 或请求失败。"""
    class Config:
        namespace = 'pipa.list_models'
```

> `PipaStatusService.status` 不带 `roles=` —— 普通登录用户都能查自己的状态。
> `PipaSupervisorService.status` 带 `roles=['PIPA_READ']` —— admin 才能诊断任意 uid。
> **`@api_method(roles=[...], authorization_required=False)` 是互斥的**：选其中一个要么都得带，要么都不带。

**关于 `api_key_encrypted` 列的去留**:后续计划删这列,改为 daemon `~/.panda/auth.json`
sole source of truth。当前 alembic 链**尚未删**(过渡期两边都写)。Webdesktop
Settings 面板走 `pipa.user_prefs.update({ api_key })`,daemon 内部另外通过 `~/.panda/auth.json`
走 pandacode 自家加载路径 — 两侧独立,删除前没有功能冲突。

#### 3.3.5 审计 / RBAC / Jobs 全自动
- **审计**：`pipa.user_prefs.*` / `pipa.stream.*` / `pipa.supervisor.*` 全部走 `@api_method`，middleware 自动应用 `log_audit_message_for_method`
- **RBAC**：role `PIPA_READ` 给 admin 查任意 daemon；普通用户自己的 status 不需要角色（已认证即可）
- **Jobs**：pipa tool 调 middleware 的 `pool.extend` 等长任务是 `@job` 装饰的，pipa 拿到 `JobId`，webdesktop 通过 `core.get_jobs` 订阅进度
- **告警协同**（后续）：在 [plugins/alert.py](middleware/src/middlewared/middlewared/plugins/alert.py) 的 dispatch hook 里加 `_ai_explain_alert`，调 `pipa.stream.connect` 异步生成解释

#### 3.3.6 跨插件协同示例

| 触发方 | 调 pipa 干什么 | 实现 |
|---|---|---|
| [plugins/alert.py](middleware/src/middlewared/middlewared/plugins/alert.py) | 新告警 → pipa 解释 | 在 alert dispatch hook 里 `await middleware.call('pipa.stream.connect', app)` + send frame |
| [plugins/audit/audit.py](middleware/src/middlewared/middlewared/plugins/audit/audit.py) | 异常操作模式 → pipa 风险评估 | 后台 `periodic` 任务 |
| [plugins/reporting/](middleware/src/middlewared/middlewared/plugins/reporting/) | 「上月 IO 峰值」→ pipa 自然语言报告 |  |
| 定时快照策略 | 「每周末自动给 tank/media 做快照」→ pipa 调 `pool.snapshot.create` + `crontab_create` |  |

---

### 3.4 webdesktop 集成

#### 3.4.1 目录改名
```
webdesktop/apps/agent/  →  webdesktop/apps/pipa/
```

`apps/pipa/manifest.json`:
```json
{
  "name": "pipa",
  "title": "Pipa · 系统全能助手",
  "version": "0.1.0",
  "entry": "./src/index.tsx",
  "icons": { "default": "./icon.svg" },
  "minWidth": 900,
  "minHeight": 600
}
```

#### 3.4.2 SDK `webdesktop/src/shared/sdk/pipa.ts`

**协议选择**：走 **middleware 主 RPC event channel**，不开 raw WS。

- CRUD：`client.call('pipa.user_prefs.*')` / `client.call('pipa.status')` / `client.call('pipa.provider_catalog.list')` / `client.call('pipa.test_provider')` / `client.call('pipa.list_models')`
- 流式 turn：
  - `await client.call('pipa.stream.connect', app)` → middleware 内部完成整套握手(详见下)→ 返回 `Literal[True]`
  - `client.subscribe('pipa.stream', evt => { ... evt.fields.frame ... })` 收 daemon 帧
  - `await client.call('pipa.stream.send', session_id_or_just_frame, frame)` 发帧
  - `await client.call('pipa.stream.disconnect')` 关闭

**关键决策 — initialize 握手由 middleware 代理,SDK 不发**：
pandacode daemon 的 `initialize` / `initialized` 是连接生命周期里**只能发一次**的握手帧,
daemon 内部用 `InitializeRequestProcessor` 跟踪状态,收到第二个 `initialize` 会报
`"Already initialized"` 直接关连接(见 [panda-rs/app-server](pandacode/panda-rs/app-server/) 的
`initialize_processor.rs`)。如果让 SDK 自己发,跟 `pipa.stream.connect` 在并发场景下
会出现竞争(浏览器打开两个 tab 同时调 connect 时,daemon 会被第二次 initialize 拒掉)。

实现选择:**`PipaStreamService.connect` 在 middleware 侧替 SDK 走完整套握手**
—— 发 `initialize`(id=0,带 `clientInfo` + `userInfo` + `userHome` + `middlewareEndpoint`),
`await` daemon ack(处理可能的 error 帧),再发 `initialized` notification,只有 ack 拿到后才
注册 reader 任务 + 把控制权还给 SDK。SDK 的 `connect()` 只 `await call('stream.connect')`,
等 `onConnected` 回调就算会话可用,不发自己的 initialize 帧。

> `userHome` 字段在当前架构下**等于** daemon-global `PANDA_HOME=%h/.panda` —— 因为
> 每个用户的 daemon 进程启动时就读自己的 `~/.panda/` —— 但 middleware 仍然把 `pw_dir/.panda`
> 写进 `initialize.userHome`。这样未来切到 per-request HOME(罕见)时 wire 协议不用动,
> daemon 端无需任何代码改动。

```ts
/**
 * Pipa SDK —— 系统级 AI 助手客户端
 *
 * 普通 CRUD 走现有 WS client (/api/current 同步 RPC):
 *   pipa.getUserPrefs()           →  client.call('pipa.user_prefs.query', ...)
 *   pipa.updateUserPrefs(patch)   →  client.call('pipa.user_prefs.update', ...)
 *   pipa.status()                 →  client.call('pipa.status')
 *
 * 流式 turn 走 event channel 'pipa.stream' (主 RPC 同一条隧道):
 *   const conn = pipa.open(callbacks)
 *   await conn.connect()          // 内部: subscribe event channel + pipa.stream.connect
 *                                // (initialize 握手由 middleware 代发,SDK 不再发)
 *   await conn.threadStart({})
 *   await conn.turnStart(threadId, input)
 *   conn.on('agentMessageDelta', d => ...)
 *   await conn.close()
 */
import { truenasApi, ConnectionState } from '@truenas/api'

export interface PipaUserPrefs {
  id: number
  user_id: number                // 一个用户可拥有多行(multi-preset)
  provider: string | null        // catalog id,自由字符串(不再是 4 个固定 enum)
  model: string | null
  api_key_set: boolean           // true 表示已存,从不返回明文
  is_active: boolean             // 每个用户最多一行 is_active=true(部分唯一索引兜底)
  display_order: number          // 卡片排序,lower = earlier
  enabled_skills: string[] | null
  daily_token_quota: number | null
  auto_approve_safe_ops: boolean
  notes: string | null
}

type PipaConnectionCallbacks = {
  onConnected?: () => void
  onAgentMessageDelta?: (d: { type: 'text' | 'reasoning' | 'image'; delta: string }) => void
  onToolCall?: (name: string, args: any) => void
  onApprovalRequest?: (req: { approvalId: string; toolName: string; args: any; reason: string }) => void
  onTurnCompleted?: (turn: any) => void
  onError?: (err: Error) => void
  onDisconnected?: () => void
}

export const pipa = {
  // ===== 同步 CRUD =====
  getUserPrefs(): Promise<PipaUserPrefs[]> {
    return truenasApi.call<PipaUserPrefs[]>('user_prefs.query', [], {})
  },
  updateUserPrefs(id: number, patch: Partial<PipaUserPrefs>): Promise<PipaUserPrefs> {
    return truenasApi.call<PipaUserPrefs>('user_prefs.update', id, patch)
  },
  status(): Promise<PipaStatus> {
    return truenasApi.call<PipaStatus>('status')
  },

  /** 打开流式连接。fire-and-forget,真正 ready 通过 `onConnected` 回调通知。 */
  open(callbacks: PipaConnectionCallbacks = {}): PipaConnection {
    const conn = new PipaConnection(callbacks)
    void conn.connect().catch(e =>
      callbacks.onError?.(e instanceof Error ? e : new Error(String(e))))
    return conn
  },
}

class PipaConnection {
  private cbs: PipaConnectionCallbacks
  private nextId = 1
  private pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void }>()
  private unsubscribe: (() => void) | null = null
  private disposeConnListener: (() => void) | null = null
  private connected = false

  constructor(cbs: PipaConnectionCallbacks = {}) {
    this.cbs = cbs
  }

  async connect(): Promise<void> {
    if (this.connected) return

    // 监听 middleware WS 状态:断了就主动 close(),释放 server-side _sessions。
    // middleware 没有 core.on_close hook,这是唯一可靠清理点。
    if (!this.disposeConnListener) {
      this.disposeConnListener = truenasApi.onConnectionStateChange(state => {
        if (this.connected
          && (state === ConnectionState.Disconnected || state === ConnectionState.Error)) {
          void this.close()
        }
      })
    }

    // 先订阅 event channel,再 await stream.connect —— 否则 connect 完成到 subscribe
    // 之间可能漏掉 daemon 的早期帧。
    await this.subscribe()

    // middleware 代发完整 initialize/initialized 握手,await 返回时 session 已活。
    await truenasApi.call<true>('stream.connect')

    this.connected = true
    this.cbs.onConnected?.()
  }

  /** pandacode JSON-RPC 2.0 请求。response 通过 pipa.stream event 按 id 回填到 pending。 */
  call<T = unknown>(method: string, params?: unknown): Promise<T> {
    const id = this.nextId++
    return new Promise<T>((resolve, reject) => {
      this.pending.set(id, { resolve: resolve as (v: unknown) => void, reject })
      void truenasApi.call('stream.send', JSON.stringify({ jsonrpc: '2.0', id, method, params }))
    })
  }

  // ===== pandacode high-level methods =====

  threadStart(opts: { model?: string; cwd?: string } = {}) {
    return this.call<{ thread: { id: string } }>('thread/start', opts)
  }
  threadResume(threadId: string) {
    return this.call('thread/resume', { threadId })
  }
  threadList(opts: { cursor?: string; limit?: number } = {}) {
    return this.call('thread/list', opts)
  }
  threadArchive(threadId: string) {
    return this.call('thread/archive', { threadId })
  }
  turnStart(threadId: string, input: { text: string; images?: string[] }) {
    // pandacode TurnStartParams.input 是 Vec<UserInput>,serde tagged enum 需要
    // discriminator,直接传 { text } 会被反序列化拒掉("invalid type: map, expected a sequence")。
    // 包成 { type: 'text', text } 单元素数组。
    const userInputs = [{ type: 'text' as const, text: input.text }]
    return this.call<{ turn: { id: string } }>('turn/start', { threadId, input: userInputs })
  }
  turnInterrupt(turnId: string) {
    return this.call('turn/interrupt', { turnId })
  }
  sendApproval(approvalId: string, decision: 'approve' | 'decline') {
    return this.call('item/approval/decision', { approvalId, decision })
  }

  async close() {
    if (!this.connected) {
      this.disposeConnListener?.()
      this.disposeConnListener = null
      return
    }
    this.connected = false
    this.disposeConnListener?.()
    this.disposeConnListener = null
    // 拒掉所有 in-flight RPC,UI 看到错误就当 connection lost
    for (const p of this.pending.values()) {
      p.reject(new Error('pipa connection closed'))
    }
    this.pending.clear()
    this.unsubscribe?.()
    this.unsubscribe = null
    await truenasApi.call('stream.disconnect').catch(() => {})
    this.cbs.onDisconnected?.()
  }
}
```

#### 3.4.3 `apps/pipa/src/index.tsx` 重写

照 `apps/terminal/src/App.tsx` 的多 panel 布局：左侧 thread 列表，中间对话流（**流式渲染 + 代码块高亮 + diff 视图**），右侧工具调用 / 文件预览 / 终端输出。

**复用** [apps/terminal/src/pterm/](webdesktop/apps/terminal/src/pterm/) 的流式渲染器。

```tsx
export default function PipaApp() {
  const connRef = useRef<PipaConnection | null>(null)
  const [messages, setMessages] = useState<Message[]>([])

  useEffect(() => {
    const conn = pipa.open({
      onAgentMessageDelta: d => setMessages(p => appendDelta(p, d)),
      onToolCall: (name, args) => setMessages(p => appendTool(p, name, args)),
      onApprovalRequest: req => showApprovalModal(req),
      onTurnCompleted: () => { /* keep conn for next turn */ },
      onError: e => toast.error(e.message),
    })
    conn.initialize().then(() => connRef.current = conn)
    return () => conn.close()
  }, [])

  const startTurn = async (input: string) => {
    const conn = connRef.current
    if (!conn) return
    const { thread } = await conn.threadStart({ cwd: `/home/${user}` })
    await conn.turnStart(thread.id, { text: input })
  }

  return (
    <PipaLayout
      messages={messages}
      onSend={startTurn}
    />
  )
}
```

#### 3.4.4 浮动 Copilot `QuickPipaDialog.tsx`

新建 `webdesktop/src/desktop/components/QuickPipaDialog.tsx`（参考原 `QuickAgentDialog.tsx` 的 UI 风格），把 mock state 换成 `pipa.open()` + `PipaConnection`（§3.4.2）。
- `useEffect` 里 `pipa.open(callbacks)`，初始化后保持单连接
- `handleSend` 调 `conn.turnStart(threadId, { text })`
- `onOpenFullApp` 把当前 threadId 传给 `apps/pipa` 的窗口（通过 `openApp('pipa', { initialDraft })`）
- 审批 modal 用 `conn.sendApproval(approvalId, 'approve'|'decline')`

**入口策略：Cmd+K + Taskbar 机器人图标双入口**。
- `DesktopShell.tsx` 在 window keydown 层注册 `Cmd/Ctrl+K` 全局快捷键(行 45-65),先于任何 focused element 处理
- Taskbar 上的 `AI 助手` 按钮(`mdiRobot` 图标)行为:`isRunning('pipa')` 时 focusOrOpen,否则 toggle QuickPipaDialog
- Sidebar 组件本身**不显示** Pipa/Agent 入口 — Sidebar 留给持久化 nav(thread/files/dashboard 等),Pipa 走瞬时入口

> 早期设计说"Cmd+K 是唯一入口"已经不准确:Taskbar 机器人按钮是自然的视觉入口,与 Cmd+K 并存。两者最终都打开同一个 QuickPipaDialog,只是触发路径不同。

#### 3.4.5 Pipa 设置面板 `apps/pipa/src/Settings.tsx`

**不**放 `apps/system-settings/`，直接做在 Pipa 全屏 app 内部（用户进 Pipa app → 点齿轮图标 → 切到 Settings tab）。

需要暴露的设置项：
- **Provider**：openai / anthropic / ollama / lmstudio（下拉）
- **Model**：根据 provider 动态显示可选模型列表
- **API Key**：输入框，保存时通过 `pipa.updateUserPrefs(id, { api_key })` 进 middleware `EncryptedText`（**绝不明文回返**，只显示 `api_key_set: bool`）
- **测试连接**：调 `pipa.status()` 验证 daemon 可达
- **配额**（后续）：每日 token 用量 / 上限

数据流：
```ts
const cfg = await pipa.getUserPrefs()
await pipa.updateUserPrefs(cfg.id, { provider, model, api_key })
```

#### 3.4.6 `DesktopShell.tsx` 全局快捷键 + `Taskbar.tsx` 入口

```tsx
// DesktopShell.tsx 行 45-65 — Cmd/Ctrl+K 全局快捷键
useEffect(() => {
  const onKey = (e: KeyboardEvent) => {
    const isK = e.key === 'k' || e.key === 'K'
    if (!isK) return
    if (!(e.metaKey || e.ctrlKey)) return
    if (e.altKey || e.shiftKey) return  // 不带 alt/shift 才触发
    e.preventDefault()
    toggleQuickDialog()                  // → usePipaUiStore.toggleQuickDialog
  }
  window.addEventListener('keydown', onKey)
  return () => window.removeEventListener('keydown', onKey)
}, [toggleQuickDialog])
```

```tsx
// Taskbar.tsx 行 207-217 + 326-337 — AI 助手按钮(mdiRobot 图标)
onClick={() => {
  if (isRunning('pipa')) {
    focusOrOpen('pipa')                  // 已开 → 聚焦窗口
  } else {
    usePipaUiStore.getState().toggleQuickDialog()  // 未开 → 弹 QuickPipaDialog
  }
}}
```

> Cmd+K 和 Taskbar 机器人按钮最终都打开同一个 QuickPipaDialog —— 触发路径不同,落点相同。
> Sidebar 组件本身**不显示** Pipa 入口（Sidebar 留给持久化 nav 视图）。

### 3.5 FastConnect 通道

> **D4 修正**：FastConnect 实际是「NAS → portal **主动 outbound** WebSocket 隧道」架构（见 [fastconnect/app/api/tunnel.py](fastconnect/app/api/tunnel.py#L28)），隧道对路径透明。

Pipa 当前走 middleware 主 RPC + event channel (`pipa.stream`)，与 SMB / Docker / VM / FC 等同级 — FastConnect 完全不需要为 Pipa 改任何代码，远端浏览器走现有隧道即可。

#### 为什么 unix socket 完全不影响 FastConnect
unix socket `/run/user/<uid>/pipa.sock` 是 middleware **本机内**与 pipa daemon 通信；FastConnect 只管浏览器 ↔ NAS 边界，对 unix socket 这一层完全不可见。两层独立、互不干扰。

> Slice 0 早期曾补 fastconnect `/_plugins/{path:path}` route 作为 forward-compat。当前不再需要 — 若日后 middleware 任何插件需要 raw WS 端点，再单独补即可，与 Pipa 解耦。

---

## 4. 命名空间 / 路径映射表

| 旧名 / 概念 | 新名 / 现状 | 位置 |
|---|---|---|
| `pandacode` 仓库目录 | 保留原名（git 历史 + 同步上游用） | `/pandacode/` |
| `pandacode/panda-cli/` | **不改**，原样 | pandacode/panda-cli/ |
| `pandacode/panda-rs/app-server/` | **不改**，原样 | pandacode/panda-rs/app-server/ |
| `panda-app-server` 二进制 | **不改**（pandacode deb 装 `/usr/sbin/panda-app-server`） | pandacode/debian/ |
| `panda` CLI 命令 | **不改**，原样 | pandacode/panda-cli/bin/panda.js |
| `apps/agent/` | `apps/pipa/` | webdesktop/apps/ |
| `agent` (manifest name) | `pipa` | webdesktop/apps/pipa/manifest.json |
| `QuickAgentDialog` 旧入口 | **删除**（Cmd+K + Taskbar 机器人图标是入口，Sidebar 不显示） | webdesktop/src/desktop/components/ |
| `useWebSocketInit` (现有) | 保留 | webdesktop/src/shared/hooks/ |
| `/api/v25.10.2` (现有主 RPC) | 不变 | middleware |
| `/_shell/...` (现有) | 不变 | middleware |
| ~~`/_plugins/{plugin}/{route}` for Pipa~~ | **不用** — Pipa 走 event channel | middleware |
| `/api/current` (webdesktop 用) | 不变 — Pipa 流式也用 | middleware |
| ~~系统 `pipa.service`~~ | **删** — 无系统级 daemon | /etc/systemd/system/ |
| ~~`/run/pipa/pipa.sock`~~ | **删** — 改 per-user | systemd RuntimeDirectory |
| ~~`/usr/lib/tmpfiles.d/pipa.conf`~~ | **删** — RuntimeDirectory=pipa 自动建 | /usr/lib/tmpfiles.d/ |
| **新增** per-user socket | `/run/user/<uid>/pipa.sock`（mode `srw------- <user> <user>`） | systemd RuntimeDirectory=pipa |
| **新增** per-user unit | `~/.config/systemd/user/pipa.service`（owner = user） | middleware 渲染并写 |
| **新增** per-user panda home | `<pw_dir>/.panda`（mode 0700） | systemd `%h` 展开 |
| **新增** middleware namespace | `pipa.supervisor.*` / `pipa.stream.*` / `pipa.user_prefs.*` / `pipa.status` / `pipa.test_provider` / `pipa.provider_catalog` / `pipa.list_models` | middleware plugins/pipa*.py |
| **新增** middleware 事件 channel | `pipa.stream`（per-session NDJSON 帧广播，按 `ws.session_id` 单播） | middleware event_register |
| **新增** middleware API 版本 | `api/v26_0_0/pipa.py` | middleware/api/ |
| **新增** alembic migration | `versions/26.0/2026-08-17_12-00_pipa_user_prefs.py` + `2026-08-25_12-09_pipa_user_prefs_multi_and_notes.py` | middleware/alembic/ |
| **新增** webdesktop SDK | `shared/sdk/pipa.ts`（走 event channel，middleware 代发 initialize 握手） | webdesktop/src/shared/sdk/ |
| **新增** webdesktop 全屏 app | `apps/pipa/`（App.tsx + 6 个组件 + Settings.tsx） | webdesktop/apps/pipa/ |
| **新增** Pipa 设置面板 | `apps/pipa/src/Settings.tsx`（在 AI 应用 UI 内） | webdesktop/apps/pipa/src/ |
| **新增** Pipa 浮动 Copilot | `desktop/components/QuickPipaDialog.tsx` | webdesktop/src/desktop/components/ |
| **新增** Pipa 全局 Zustand store | `shared/stores/pipa.ts`（toggleQuickDialog / setActiveDraft 等） | webdesktop/src/shared/stores/ |
| **新增** Cmd+K 全局快捷键 | `desktop/components/DesktopShell.tsx` 行 45-65 | webdesktop/src/desktop/components/ |
| **新增** Taskbar Pipa 入口 | `desktop/components/Taskbar.tsx`（mdiRobot 图标，`isRunning('pipa')` 时 focus 否则 toggle dialog） | webdesktop/src/desktop/components/ |
| ~~`usePipaInit.ts` 独立 hook~~ | **未单独抽** — DesktopShell 内联 14 行 useEffect（toggle 弹窗 + keydown listener） | webdesktop/src/shared/hooks/ |
| ~~FastConnect `/_plugins/*` route for Pipa~~ | **不需要** | fastconnect |
| **保留** `api_key_encrypted` 列 | Slice 1 暂存；Slice 2 Sprint F 计划删除（daemon `~/.panda/auth.json` 接管） | middleware alembic |

---

## 5. 安全模型

| 维度 | 措施 |
|---|---|
| **网络暴露** | `panda-app-server` 只监听 unix socket；middleware 仅 127.0.0.1:6000；不直连外网 |
| **FastConnect** | 复用 portal 已有的 token/session 认证 — Pipa 走主 RPC，不需要为 Pipa 改 FastConnect |
| **pipa 进程权限** | per-user systemd unit: `NoNewPrivileges=true` + `ProtectSystem=strict` + `PrivateTmp=true` + `PrivateDevices=true` + `ProtectKernel*` + `ProtectControlGroups` |
| **`ProtectHome`** | **DROPPED** — per-user daemon 需要 read-write `~/.panda/`，由 `ProtectSystem=strict` 限制 `/usr` `/boot` `/efi` |
| **socket 文件权限** | 每用户 socket 由 systemd RuntimeDirectory=pipa 自动建，mode `srw------- <user> <user>` |
| **API key 存储** | daemon 侧：`~/.panda/auth.json`（per-user daemon 自己管，mode 0600）；middleware 侧：`pipa_user_prefs.api_key_encrypted` 列用 `EncryptedText`（仅 webdesktop Settings 面板用） |
| **caller 身份传递** | middleware 在 `pipa.stream.connect` 读 caller uid，supervisor 按 UID 拉对应 daemon；pipa 回调 middleware 时带 caller session token |
| **进程隔离** | 每用户一个独立 daemon 进程，UID = caller；不同用户之间无法互相读 `~/.panda/`（kernel 文件权限兜底） |
| **高危操作审批**（后续） | 默认全审：删 pool / dataset / share / 改 ACL / quota / 启动 replication 一律走 `item/approval/request` 流，webdesktop 弹 modal 等用户确认 |
| **审计** | middleware 自动记录所有 `pipa.*` 触发的 NAS 操作到 `/audit` dataset |
| **速率限制**（后续） | middleware 利用 `pipa_user_prefs.daily_token_quota` 字段限制 |
| **Provider 隔离** | 仅 per-user：每个 TrueNAS 用户各自的 daemon 进程 + 各自的 `~/.panda/auth.json` |
| **故障隔离** | daemon 挂了 supervisor 重启；middleware 重启时 per-user daemon 由 systemd --user instance 维持 |

---

## 6. 实施 Sprint 计划

### Slice 1 — 已完成 ✅

| Sprint | 目标 | 状态 | 关键产出 |
|---|---|---|---|
| **A** | per-user daemon + supervisor | ✅ | `pipa_supervisor.py` 实现 `ensure_running_for_caller`：loginctl enable-linger、渲染 per-user unit、`~/.panda/` 预创建、machinectl shell start、socket 探活 |
| **B** | middleware event channel + StreamService | ✅ | `pipa.py` 实现 `PipaStreamService.connect/send/disconnect` + `_daemon_reader_loop` + `event_register('pipa.stream')` |
| **C** | api_key_encrypted + PipaStatus per-caller | ✅ | `v26_0_0/pipa.py` schemas：`PipaStatusEntry` / `PipaPerUserRuntimeStatusEntry` / `PipaSupervisorStatusArgs/Result` |
| **D** | pandacode deb 去系统 unit | ✅ | `pandacode/Makefile` 删 `sync_systemd_unit` + `stop_service` + `start_service` 目标；`debian/rules` 删 `dh_installsystemd --name=pipa`；`debian/postinst` 删 daemon-reload 块 |
| **E** | deploy via deploy-nas.sh | ✅ | middleware 重装 + pandacode 重装 + webdesktop 重启，3 个用户并发验证 PASS（见 §9.1） |

### Slice 2 — 待开始

| Sprint | 目标 | 关键产出 | 触及层 |
|---|---|---|---|
| **F** | `~/.panda/auth.json` 是 sole source of truth | alembic 删 `pipa_user_prefs.api_key_encrypted`；webdesktop Settings 改写直接通过 daemon `~/.panda/auth.json` 写入；保留 `EncryptedText` 列只用于审计/导入导出 | middleware + webdesktop |
| **G** | 数据迁移脚本 | `/var/lib/panda/<sanitized>/` → `~/.panda/`，幂等可重入 | middleware |
| **H** | admin 全用户 daemon 诊断面板 | webdesktop `apps/system-settings/` 加 Pipa tab，调 `pipa.supervisor.status(uid)` 列每个 uid 状态 | webdesktop |
| **I** | auto-linger 策略 | 默认 `enable-linger`；admin policy 控制是否自动开 | middleware |
| **J** | idle daemon eviction | N 分钟无活动 supervisor 自动 `systemctl --user stop`；下次 `pipa.stream.connect` 重新拉起 | middleware |
| **K** | per-user `MemoryMax` / `CPUQuota` | unit 模板加 slice 指令（用户基数 >10 时再做） | middleware |

### 后续方向

| Sprint | 目标 | 关键产出 | 触及层 |
|---|---|---|---|
| **L** | 跨插件协同 | alert.py / audit / reporting / jobs 自动调 AI：新告警 → AI 解释；异常操作 → AI 风险评估 | middleware |
| **M** | 语音 Pipa / V8 sandboxed 脚本 / Web browsing | 真正的 AI-Based WebOS | pandacode + middleware |

---

## 7. 文件级变更清单

### 7.1 pandacode/ 端（Slice 1 一行未改）
```
pandacode/
├── panda-rs/app-server/src/main.rs                  # 不动(cli --listen AppServerTransport 早已支持)
├── panda-rs/app-server/src/transport.rs             # 不动(panda_app_server_transport crate re-export 入口)
├── etc/pipa.service                                  # **已删除**(untracked 死代码,system unit 不再 ship)
└── Makefile / debian/                                # Slice 1 删了系统 unit 相关 target
                                                     # debian/panda-app-server.pipa.service **已删除**
                                                     # Makefile status target 改为 per-user aware
```

### 7.2 systemd / 系统端（无系统 unit）
```
/etc/systemd/system/pipa.service                      # 不存在(Slice 1 已删)
/usr/lib/tmpfiles.d/pipa.conf                        # 不存在(Slice 1 已删)
/run/user/<uid>/pipa.sock                            # 每用户,systemd RuntimeDirectory=pipa 自动建
<user-home>/.config/systemd/user/pipa.service        # middleware 渲染并写入
<user-home>/.panda/                                  # middleware supervisor 创建
/usr/sbin/panda-app-server                            # pandacode deb 装
```

### 7.3 middleware/ 端
```
middleware/src/middlewared/middlewared/
├── plugins/
│   ├── pipa.py                                       # 改:CRUD + StatusService + StreamService + event channel
│   ├── pipa_supervisor.py                            # 新增:~280 行 per-user supervisor
│   ├── alert.py                                      # Slice 2+ 加 _ai_explain_alert hook
│   └── audit/audit.py                                # 不动(自动生效)
├── api/
│   └── v26_0_0/
│       └── pipa.py                                   # 改:PipaStatusEntry + PipaPerUserRuntimeStatusEntry
│                                                       + PipaSupervisorStatusArgs/Result + event channel schemas
├── main.py                                           # 不动(Slice 1 一行未改)
└── alembic/
    └── versions/
        └── xxxx_add_pipa_user_prefs.py               # Slice 1 已加:pipa_user_prefs 表
                                                        Slice 2 删 api_key_encrypted 列

middleware/
└── debian/
    └── middlewared.postinst                          # 不动
```

### 7.4 webdesktop/ 端
```
webdesktop/
├── apps/
│   ├── agent/                                        # 删
│   └── pipa/                                         # 新增
│       ├── manifest.json                             # name: "pipa", title: "Pipa · 系统全能助手"
│       ├── icon.svg                                  # panda + 琵琶 logo
│       └── src/
│           ├── index.tsx                             # 多 panel UI
│           ├── App.tsx
│           ├── Settings.tsx                          # 在 AI 应用内
│           ├── components/
│           ├── hooks/
│           └── services/
├── src/
│   ├── shared/
│   │   ├── sdk/
│   │   │   └── pipa.ts                               # SDK,走 event channel;initialize 握手由 middleware 代发
│   │   ├── hooks/
│   │   │   └── usePipaInit.ts                        # **未单独抽** — Cmd+K 逻辑内联在 DesktopShell 行 45-65
│   │   └── stores/
│   │       └── pipa.ts                               # Zustand store(toggleQuickDialog / setActiveDraft)
│   └── desktop/
│       └── components/
│           ├── QuickPipaDialog.tsx                   # 新增,QuickAgentDialog 整个删除
│           ├── DesktopShell.tsx                      # 改:加 Cmd+K 全局快捷键(行 45-65)
│           ├── Taskbar.tsx                           # 改:加 AI 助手机器人按钮(mdiRobot)
│           └── Sidebar.tsx                           # **不变** — Sidebar 本身就不显示 Pipa 入口
└── apps/system-settings/                             # 不动
```

### 7.5 fastconnect/ 端（Slice 1 不需要任何改动）
Pipa 走主 RPC event channel，FastConnect 隧道对路径透明。

---

## 8. 关键决策记录 (ADR)

### ADR-001: per-user daemon via systemd --user
**决定**：每 TrueNAS 用户一个 `panda-app-server` 进程，由 middleware supervisor 拉起，跑在 `systemd --user` instance 下。
**理由**：照 POSIX 标准模型（`sudo` / `sshd` / `podman rootless`）；进程隔离 = 数据隔离；真实 UID 隔离无需内部权限 drop；pandacode 零代码改动。
**拒绝的方案**：
- 系统单 daemon + per-connection `$PANDA_HOME`（详见 ADR-008）— pandacode `AuthManager` 等单例启动时 read，per-connection 救不了 thread store 冲突
- middleware 在 `setup()` 里 `subprocess.Popen(['panda-app-server'], ...)` 拉起（生命周期缠进 middleware 进程；丢失 systemd cgroup / hardening / journal / restart）

### ADR-002: 用 unix socket,不是 TCP localhost
**决定**：每用户 daemon 监听 `unix:///run/user/<uid>/pipa.sock`。
**理由**：与 dhcpcd 一致；无端口管理；socket 文件 mode 0700 天然隔离。
**拒绝的方案**：`ws://127.0.0.1:<port>`（多端口管理 + 反向代理配置复杂）。

### ADR-003: 走 middleware 单一端口 6000,不开新端口
**决定**：所有外部访问都过 `127.0.0.1:6000`（中间已用 nginx 反代）。
**理由**：TLS/Origin/鉴权/RBAC/审计/FastConnect 全复用现有设施。
**拒绝的方案**：pipa 直开 TCP 端口对外暴露。

### ADR-004: 命名 Pipa
**决定**：Pipa
**理由**：2 音节 + 元音收尾像 Siri；panda 主题（琵琶形似熊猫）；商标干净；中文亲和。

### ADR-005: 流式 turn 走主 RPC event channel
**决定**：流式 turn（`initialize` / `thread/start` / `turn/start` / `item/agentMessage/delta` 等 JSON-RPC 帧）走主 RPC：
- 控制方向：`pipa.stream.connect` / `send` / `disconnect`（普通 RPC 调用）
- 数据方向：daemon → 浏览器走 `core.subscribe('pipa.stream')` event channel，按 `session_id` 单播
**理由**：
- middleware 主 RPC 会把 `AsyncGenerator` 物化为 list 再返回，不能原生流式；要逐 token 推到浏览器必须 event channel 单播
- event channel 与 SMB / Docker / VM / FC 等同级，复用现有隧道与订阅机制
- 不需要 `/_plugins/*` raw WS 挂载点（避免改 main.py / pre_freeze_setup）
**复用度**：webdesktop 端 100% 复用现有 `useTruenasApi` / websocket-client / event subscribe。
**早期误区**：曾计划 raw WebSocket `/_plugins/pipa/ws` —— 实测发现要走 `pre_freeze_setup` 钩子违反"main.py 不动"原则，改回主 RPC event channel 是更干净的路径。

### ADR-006: AI 触发的 NAS 操作走 middleware RPC,不是 SSH/直调
**决定**：pipa 的 NAS tools 全部用 HTTP 调回 middleware，带 caller session token。
**理由**：RBAC/audit/jobs 白送；AI 永远不会直接碰 ZFS/SMB/samba-tool 配置。
**拒绝的方案**：pipa 走 ssh 到 NAS 调 `zfs` 命令。

### ADR-007: middleware 插件统一走主 RPC + event channel
**决定**：所有 Pipa middleware 端点（`pipa.supervisor.*` / `pipa.stream.*` / `pipa.user_prefs.*` / `pipa.status`）+ 一个事件 channel `pipa.stream`。
**理由**：这是 middleware 标准 RPC + event 机制；与 SMB / Docker / VM / FC 完全同级；FastConnect 完全不需要为 Pipa 改代码；不动 `main.py`。
**对比早期方案**：曾考虑走 [main.py:657](middleware/src/middlewared/middlewared/main.py#L657) 的 `/_plugins/{plugin}/{route}` 路由挂载点 —— 但需 `pre_freeze_setup` 钩子在 aiohttp freeze router 前挂路由，违反"main.py 不动"原则。Slice 1 走 event channel 后整块问题消失。

### ADR-008: per-user daemon 取代 per-connection HOME
**决定**：Slice 1 用 per-user daemon 进程，每个进程启动时 read `~/.panda/`（由 systemd unit `Environment=PANDA_HOME=%h/.panda` 注入），不再做 per-connection HOME。
**理由**：
- pandacode daemon 启动时 read `~/.panda/auth.json` 进 `AuthManager` 单例 — 进程内 per-connection 切 HOME 救不了 thread store 冲突（thread store 是 process-local 状态）
- per-user daemon = per-user `AuthManager` / `ConfigManager` / thread store，单例自然隔离
- POSIX 标准模型，工具链熟、systemd 文档全、polkit 规则现成
**拒绝的方案**：
- 系统单 daemon + per-connection `InitializeParams.user_home` — 上面已说单例救不了
- 不隔离直接共享 `~/.panda` — 多个用户共用一个 daemon 时 thread store 冲突、A 用户能看 B 用户对话
**迁移路径**：Slice 0 阶段曾做 `InitializeParams.user_home`（middleware 在 connect 时塞 `/var/lib/panda/<sanitized>/`），Slice 1 测出 thread store 冲突后退回 per-user daemon。

---

## 9. 验证清单

### 9.1 详细验证场景

按步骤的完整验收(per-user 拉起链路 / 流式通道 / SDK / EncryptedText / 多用户隔离回归 / 失败排查表)见 [pipa-test-runbook.md](./pipa-test-runbook.md)。

### 9.2 Slice 1 PASS 速查

```bash
# 1. 基础设施
loginctl enable-linger apple banana
# loginctl show-user <uid> 才是正确检查命令(不是 list-lingers)

# 2. 部署
cd /home/truenas_admin/work/OpenNAS
./tools/deploy-nas.sh --target middleware
./tools/deploy-nas.sh --target pandacode
./tools/deploy-nas.sh --target webdesktop

# 3. 确认系统 daemon 已删
systemctl status pipa.service
# expect: Unit pipa.service could not be found.

# 4. 触发两个用户并发 + 验证 daemon + socket + unit + ~/.panda/ 隔离
# 详见 test-runbook §1(per-user daemon 拉起链路) + §5(多用户隔离回归)

# 5. status probe
midclt call pipa.status            # 返回自己的 daemon 状态(per-caller)
midclt call pipa.supervisor.status 1001   # admin 查 apple(需 PIPA_READ 角色)
```

### 9.3 Slice 2 Sprint 必过

- [ ] `~/.panda/auth.json` 是 sole source of truth（API key 不再双写）
- [ ] `pipa_user_prefs.api_key_encrypted` 列删除后所有调用正常
- [ ] admin panel 能列出所有 uid daemon 状态
- [ ] idle N 分钟后 daemon 自动 stop，下次 connect 自动拉起
- [ ] `/var/lib/panda/<sanitized>/` 历史数据已迁移到 `~/.panda/`

### 9.4 后续方向(关键回归)

- [ ] alert 自动触发 AI 解释
- [ ] 高危操作自动弹审批 modal
- [ ] apple 的 thread 列表对 banana 不可见（process 隔离已天然满足，但加回归测试）

### 9.5 通用跨 Slice 必过

- [ ] `pipa.status` 返回 `daemon_reachable: true`
- [ ] API key 永不明文（grep middleware DB 不出现 `sk-` 前缀明文）
- [ ] Cmd+K 在任何已打开窗口都能唤起 QuickPipaDialog
- [ ] middleware 重启不杀掉 per-user daemon（systemd --user instance 维持）
- [ ] per-user daemon 挂了 supervisor 自动重启

---

## 10. 下一步可执行项

Slice 1 已全部 PASS，下一步按 Slice 2 顺序：

1. **`~/.panda/auth.json` sole source of truth**
   - alembic 删 `pipa_user_prefs.api_key_encrypted` 列（保留 `EncryptedText` 类型备份用于 import/export）
   - webdesktop Settings 面板改写：通过 daemon 自己的 API 写入 `~/.panda/auth.json`
   - 移除 middleware 侧 API key 加密读写路径

2. **数据迁移脚本**
   - `/var/lib/panda/<sanitized>/` → `~/.panda/`，幂等可重入
   - 不存在则跳过；存在则逐文件 mv + chown

3. **admin 全用户 daemon 诊断面板**
   - webdesktop `apps/system-settings/` 加 Pipa tab
   - 调 `pipa.supervisor.status(uid)` 列每个 uid 状态

4. **auto-linger 策略 + idle eviction**
   - middleware 策略决定是否自动 enable-linger
   - N 分钟 idle supervisor 自动 `systemctl --user stop`

5. **跨插件协同**（Slice 后续）
   - alert.py dispatch hook 调 pipa 异步解释
   - audit 异常模式后台任务调 pipa 风险评估