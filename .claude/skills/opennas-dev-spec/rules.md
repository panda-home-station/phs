# OpenNAS 开发规范 — Rules

> 18 大规则,聚合到 14-reviews Pipa feature + 跨仓库多次 review 的教训 + memory 收敛。
> 一旦改这里,请同步 SKILL.md 顶部的触发关键词。
>
> 1-10 是 dev 直接写的代码规范,11-18 是从 memory 重构出来的架构 / 部署 / 流程规范。每节都附"为什么" + "模板"。

---

## §1 alembic revision id

**Rule**: revision id 必须由 `alembic revision -m "..."` 生成。**绝不**手写 hex 也不写非 hex。

### 为什么

- 真随机 hex 12 字符差不多都会有 2-3 个重复字符(`f3b4b0f4b0cf` 里 `f` 和 `0` 重复)。
- 手写"看起来整齐"的 hex(`a1b2c3d4e5f6` 严格顺序)12 char 全部 unique,**alembic 接受但没有真随机隐含的"不可预测"性质**。
- 一旦你**以后想 rename** 这些手写 id 到真随机,所有已 stamped 的 DB 都会 `Can't locate revision identified by 'X'`—— ghost 节点故障。
- 非 hex placeholder (`p7p8p9q0q1q2`)更糟: `p`/`q` 都不是 hex,alembic 接受但 migration 图损坏。

### 检测 heuristics

```bash
# 真随机 hex 12 字符 unique-char-count 通常 6-10
# 手写 hex 12 字符 unique-char-count == 12(无碰撞)
grep -rh "^revision = '" alembic/versions/26.0/ | while read l; do
  hex=$(echo "$l" | sed -E "s/.*'([0-9a-f]+)'.*/\1/")
  u=$(echo -n "$hex" | grep -oE '[0-9a-f]' | sort -u | wc -l)
  [[ $u -eq 12 ]] && echo "HAND-WRITTEN: $hex"
done
```

### 当你需要 rename 已 shipped 的 revision

**Dev box**:
```bash
# 1. 在文件里改 revision = 'old' → 'new'
# 2. 改下游文件的 down_revision = 'old' → 'new'
# 3. DB 同步:
DB=/data/freenas-v1.db
sudo sqlite3 $DB "UPDATE alembic_version SET version_num='<new_id>';"
# 4. 走一遍
sudo -E DATABASE=$DB PWENC_SECRET=/data/pwenc_secret \
  FREENAS_DATABASE=$DB FAKE_ENV=1 FREENAS_PWENC_SECRET=/data/pwenc_secret \
  alembic -c middleware/src/middlewared/middlewared/alembic.ini upgrade head
# 5. 验证
sudo -E DATABASE=$DB ... alembic heads
```

**Production box**: 永远不要 rename shipped migration。新改动写一个新 migration 文件,down_revision 指向**最新**的 shipped revision(不是它自己的新 id)。

### 当前链上历史包袱(2026-08-20)

4 个手写 id 永久保留作为 `down_revision` reference,不能重命名:

- `c3f8d9e2a4b1` (TrueNAS upstream 2025-10-13 shipped hand-written,作为下游 revision)
- `c7d8e9f0a1b2` (down_revision of `2026-04-04_12-00_remove_tnc_ip_fields.py`)
- `a4b1e7f9c2d5` (down_revision of `2026-03-03_20-40_migrate_virt_global_networks.py`)
- `a8f5d9e2c1b7` (down_revision of `2026-02-12_15-37_split_dataset_paths.py`)

**检测到新手写 id 出现的正确处理**: 当 lint 报错 ❌,先确认它是不是 shipped(看文件日期 + 是否在 active chain 上),如果已 shipped 就加进 `ALLOW_KNOWN`,否则按 "rename 流程" 处理。

---

## §2 middleware plugin: 命名 + cli_namespace

**Rule**: 每个 Service 必须:
- `namespace` 跟 `cli_namespace` **同时** 设置为相同的 string
- 方法用 `app.namespace.method` 形态(不是 `app.method`)
- `CRUDService` 派生类必须同时 `namespace` + `cli_namespace`

### 为什么

- `validate_api_method_schema_class_names` (utils/plugins.py) 检查 `cli_namespace` 必填,没设就 startup 失败 `Service does not have CLI namespace set`
- 用户调 `midclt call pipa.status.status` —— 不是 `pipa.status`!
- `cli_namespace` 跟 `namespace` 不一致 ⇒ CLI 跟 API 调用入口错位

### 模板

```python
class PipaFooService(Service):
    class Config:
        namespace = 'pipa.foo'           # API 路由前缀
        cli_namespace = 'pipa.foo'      # CLI 子命令前缀,必须相同
        event_register = ['pipa.foo']   # 事件名(可选)

    @api_method(PipaFooArgs, PipaFooResult)
    async def bar(self, foo_data):
        ...
```

### `core.get_methods` 检查

```bash
midclt call core.get_methods | python3 -c "
import json, sys
methods = json.load(sys.stdin)
pipa = [m for m in methods if m.startswith('pipa.')]
for m in sorted(pipa):
    print(m)
"
```

期望: 实际方法名 `pipa.foo.bar`,**不是** `pipa.bar`。

---

## §3 @private + @staticmethod 冲突

**Rule**: `@private` 装饰器**不能**跟 `@staticmethod` 同时使用。

### 为什么

- `@staticmethod` 是个 descriptor,会**丢弃** 通过 `@private` 设的 `_private=True` 属性
- `validate_api_method_schema_class_names` 检查 `hasattr(method, '_private')` 做判定
- 结果: `@private @staticmethod` 装饰的方法**仍然被公开注册**,setup 失败 `API method <fn> is public, but has no @api_method`

### 模板

```python
# ❌ 错
class FooService(Service):
    @private
    @staticmethod
    def _helper(x):
        return x

# ✅ 对: 用 underscore prefix 开头,validator 自动 skip
class FooService(Service):
    @private
    def _helper(self, x):
        return x
```

或者:

```python
class FooService(Service):
    @staticmethod
    def _helper(x):  # underscore 开头 → API 校验器 skip
        return x
```

---

## §4 Sensitive 数据: EncryptedText + 不进日志

**Rule**:
- API key / token / JWT / bcrypt hash 列用 `EncryptedText` (SQLAlchemy 自定义 type,SQLite 下透明加密)
- **永远不要** logger.info/debug/error 里 println 任何 sensitive 数据
- **永远不要** commit message 里写 sensitive 数据
- column 名必须明确表明它加密了:`api_key_encrypted`,不是 `api_key`

### 模板

```python
class PipaUserPrefsModel(sa.Model):
    __tablename__ = 'pipa_user_prefs'
    id = sa.Column(sa.Integer, primary_key=True)
    user_id = sa.Column(sa.Integer, sa.ForeignKey('account_bsdusers.id'))
    api_key_encrypted = sa.Column(EncryptedText(), nullable=True)  # ✓
```

### 检查

```bash
# 验证存储的是 ciphertext,不是 plaintext
sqlite3 /data/freenas-v1.db \
  "SELECT substr(api_key_encrypted, 1, 20) FROM pipa_user_prefs LIMIT 1"
# 期望: 看到 `gAAAAAB...` (Fernet 格式) 或 hex,绝不是 `sk-...`
```

### Pydantic 模式

```python
class PipaUserPrefsEntry(BaseModel):
    api_key: str | None = Field(default=None, description="Plaintext API key, "
                                "encrypted at rest by the server. Never logged.")
    # 入参可接受明文,server encrypt 之后存
```

---

## §5 Multi-user 隔离: per-user daemon + per-connection userHome

**Rule**:
- 全局 `CODEX_HOME` / `PANDA_HOME` ❌ —— 多用户共享会互相污染
- 每用户独立 daemon(进程级隔离),`PANDA_HOME=%h/.panda` 写到 per-user unit 里 ✓
- middleware 在 `pipa.stream.connect` 里把 caller 的 `pw_dir/.panda` 塞进 initialize 帧的 `userHome` 字段,**为未来 per-request HOME 切换留口子**,不是当下隔离机制

### 模板

```python
@api_method(PipaStreamConnectArgs, PipaStreamConnectResult, pass_app=True)
async def connect(self, app):
    creds = app.authenticated_credentials
    user = creds['username']
    user_home = self._user_home_for(user)  # /home/<user>/.panda
    await self._open_panda_session(user_home=user_home)
    # 现在 userHome == per-user daemon 的 PANDA_HOME(同一用户所有 connection 共享)
    # daemon 端无需代码改动即可在未来切换到真正 per-request HOME
```

### pandacode daemon 配置

```ini
# per-user systemd unit(middleware 渲染到 ~/.config/systemd/user/pipa.service)
[Service]
Environment=PANDA_HOME=%h/.panda
ExecStart=/usr/sbin/panda-app-server --listen unix:///run/user/%U/pipa.sock
```

---

## §6 注释不写代号 / 阶段号 / 日期

**Rule**: 注释里**不**写:
- 项目代号 ("P3-104", "A++")
- 阶段号 ("Sprint 1", "Phase 2")
- **日期** ("2026-08-15 migrated", "after 14-reviews")
- 临时变量 ("TODO-A", "FIXME-X")

### 为什么

- 这些都是**可索引**的字符串,后人看 git blame `grep "P3-104"` 找不到对应 wiki / 文档
- 长期 commit history 里它们**永久存在**,但没有任何上下文锚点
- "哪天的 review 改的"这种信息从 git log 直接看,不要写进 docstring

### 模板

```python
# ❌ 错
"""Add tunnel_user_disabled column to truenas_connect.

P3-104 root-cause fix. After 14-reviews 2026-08-15 we realised ...

# ✅ 对
"""Add tunnel_user_disabled column to truenas_connect.

Replace the in-memory `self.connection is None` heuristic with a
durable user-intent flag. The reconciler reads this column across
reboots, HA failover, and watchdog cycles, so it can correctly
distinguish "user explicitly stopped the tunnel" from "tunnel task
died and needs a restart".
```

### 例外

- **revision id 文件头** `Create Date: 2026-08-15 12:00:00.000000+00:00` ✓ (alembic 自动生成)
- **commit message** 多行 / `Refs:` 部分 ✓
- **CHANGELOG.md** 顶层 changelog entry ✓

---

## §7 跨仓库修改: 4 个独立 commit / PR

**Rule**: 一次 task 涉及多个仓库时,**每个仓库独立 commit + 独立 PR**。

### 模板

```
$ git status
M middleware/src/middlewared/middlewared/plugins/pipa.py
M webdesktop/src/desktop/components/QuickPipaDialog.tsx
M pandacode/panda-rs/src/main.rs
```

→ 三个 commit,可能三个 PR:

```bash
# middleware
cd middleware && git add -A && git commit -m "feat(pipa): provider catalog"

# webdesktop
cd webdesktop && git add -A && git commit -m "feat(pipa): quick dialog UX"

# pandacode
cd pandacode && git add -A && git commit -m "feat(pipa): daemon handles reconnect"
```

### 顶层 OpenNAS 仓库

只在 `repos/manifests/*.xml` / `tools/` / `docs/` 直接改(这些是顶层的)。**代码不进顶层 repo**。

### 双轨 commit

```bash
# 顶层 only 改 manifest / docs
cd /home/.../OpenNAS
git add -A && git commit -m "chore: bump middleware to new commit"

# 子仓库
cd middleware && git commit ...
```

---

## §8 本地部署: tools/deploy-nas.sh

**Rule**: 任何本地 NAS 部署**只**用 `tools/deploy-nas.sh --target <id>`,**禁**散打 sudo cp / systemctl。

### Targets

```
tools/deploy-nas.sh --target middleware   # 中间件 deb + alembic
tools/deploy-nas.sh --target pandacode    # Pipa 后端 + 启 daemon
tools/deploy-nas.sh --target webdesktop   # SPA
```

### 顺序

```
1. middleware (停 → 打包 → 装 → 迁移 → 启)
2. pandacode  (停 → build → 装 → 启)
3. webdesktop (build → 装到 webserver root)
4. 检查: bash tools/check-pipa-status.sh
```

### 失败时

```bash
sudo journalctl -u middlewared -n 30 --no-pager
sudo journalctl --user -u pipa.service -M <user>@.host -n 30 --no-pager
sudo journalctl -u nginx -n 30 --no-pager
sqlite3 /data/freenas-v1.db "SELECT version_num FROM alembic_version;"
```

完整 fail-recovery 详见 `docs/pipa-deploy-on-this-nas.md` 与 `docs/pipa-test-runbook.md`。

---

## §9 (隐含) Cwd 子仓库对齐

**Rule**: 写代码 / commit / 测试前,**先** `cd` 到对应子仓库根。

```bash
# ❌ 错: 在顶层 OpenNAS 改 middleware 代码
cd /home/.../OpenNAS
vim middleware/src/middlewared/middlewared/plugins/pipa.py

# ✅ 对
cd /home/.../OpenNAS/middleware
vim src/middlewared/middlewared/plugins/pipa.py
```

`.claude/current` 文件保存当下"target sub-repo",被双轨 commit 命令读取。

---

## §10 (隐含) 凭证管理

**Rule**:
- **永远不要** commit `~/.config/sudo_askpass.sh` / `~/.ssh/id_rsa` / `id_rsa.pub` / `pwenc_secret`
- **永远不要** commit 真实密码 / token / API key
- 部署脚本用 `sudo -A` + `SUDO_ASKPASS` 环境变量

### `.gitignore` 必加

```
~/.config/sudo_askpass.sh
/data/pwenc_secret
*.deb.bak
*.db.bak
```

---

## §11 @api_method 薄壳: internal call 必须 `*args` 兼容

**Rule**: `@api_method` 装饰的方法,内部 `self.middleware.call(...)` 调它时,被调方法**只接受 `*args`**,不能依赖 kwargs。

### 为什么

`@api_method` 在 setup 时把方法签名包成 JSON-RPC 友好的 thin wrapper —— 它**只透传位置参数**。如果你内部这么写:

```python
# ❌ 错
@api_method(FooArgs, FooResult)
async def stop(self, user_initiated: bool = False):
    ...

# middleware 内部调用:
await self.middleware.call('foo.stop', user_initiated=True)  # ❌ TypeError
```

middleware 内部传 kwargs,但 `@api_method` wrapper 不解 kwargs,直接 `TypeError: stop() takes ...`。
2026-08-16 fastconnect-stale-status 那次就是这个坑。

### 模板

```python
# ✅ 对: public thin wrapper + private _impl
@api_method(FooArgs, FooResult)
async def stop(self):
    """public entry — JSON-RPC calls this with positional args from schema"""
    return await self._stop_impl()

async def _stop_impl(self, user_initiated: bool = False):
    """internal call — kwargs OK"""
    ...
```

或者干脆**两个方法**,内部走 `_impl`:

```python
await self.middleware.call('foo._stop_impl', user_initiated=True)  # OK
```

---

## §12 App architecture: 三个"不要"

**Rule**: 写新 app / plugin 时:

1. ❌ **不要** 在 `main.py` 加全局 hook(`on_connect` / `on_close` / `pre_freeze_setup` 等)
2. ❌ **不要** 写"raw WebSocket" / `/api/ws` / `/_plugins/<x>/ws` 自定义路径
3. ❌ **不要** 让 app 自己 bind port

### 为什么

- `main.py` 是 TrueNAS 上游,改它 = 每次 upstream merge 都冲突
- FastConnect 路径映射只认 `/api/current` + JSON-RPC,自定义路径在隧道里断流
- 系统只有 nginx + systemd 单元做服务暴露,app bind port 跟 OS 资源争抢

### 正确做法

- **streaming**:复用 `service.event_register` + `send_event` + `should_send_event` 过滤(SMB/Docker 模式)
- **sub-protocol**:都走 `/api/current` JSON-RPC
- **暴露**:让 pandacode / 你的 daemon 听 unix socket,systemd 单元管理生命周期

### 长期 AppRegistry 准备

日后做 AppRegistry 时,你会希望每个 app 都:
- 复用 `pipa.stream` event channel 模式作为 "app streaming"
- 复用 `pipa.stream.connect/send/disconnect` 三方法作为 "app plumbing"
- 复用 `should_send_event` 过滤机制作为 "app 多用户隔离"

**Pipa 是天然范本**。

---

## §13 Pipa architecture: 当前 = JSON-RPC + middleware event channel

**Rule**: Pipa 链路是:

```
browser (webdesktop)
  └─ /api/{version}  ← 复用现有 middleware JSON-RPC WebSocket
       │
       ├─ pipa.stream.connect()/send()/disconnect()       (单次/每次发)
       └─ core.subscribe('pipa.stream')                    (持续接收)
              ↓
              middleware daemon_reader_loop 里
              send_event('pipa.stream', 'CHANGED', fields={'frame': line})
              ↓
              should_send_event 过滤 (按 session_id)
              ↓
              browser 收到 {msg:'changed', collection:'pipa.stream', fields:{frame:<jsonrpc>}}
```

**不要再切回 raw WebSocket**。所有 streaming 走这个模式。

### 关键设计点

- **wire protocol**:pandacode 还是 NDJSON over unix socket,每行 JSON-RPC 2.0
- **session 隔离**:middleware 通过 `should_send_event` 过滤,按 `ws.session_id` 匹配 `connect` 时的 session_id
- **per-user session**:每个 WS session 单独一个 pandacode unix socket 连接
- **method 内联**:helper 协程 inline 进 `connect()` 方法更易读

---

## §14 PANDA_HOME vs CODEX_HOME

**Rule**: pandacode 是上游 Codex 的 fork。**读 `PANDA_HOME`,不是 `CODEX_HOME`**。`CODEX_HOME` 是上游约定,我们 fork 出 `$PANDA_HOME` 是为了避免未来跟 upstream merge 冲突。

### 为什么

pandacode 0.1.0 之前用 `CODEX_HOME`,跟我们 monorepo 命名不一致。改成 `PANDA_HOME`。

### per-user daemon 的 unit 模板(middleware 渲染,不是 deb 装)

pandacode deb **不再 ship 任何 systemd 单元**。`PANDA_HOME` 由
per-user unit 在 `~/.config/systemd/user/pipa.service` 里 `Environment=PANDA_HOME=%h/.panda`
指定,`%h` 展开为该用户的 home 目录。**不存在** `/var/lib/panda` 这种系统级路径。

```ini
[Service]
Environment=PANDA_HOME=%h/.panda
ExecStart=/usr/sbin/panda-app-server --listen unix:///run/user/%U/pipa.sock
# ProtectHome INTENTIONALLY OMITTED — per-user daemon needs R/W ~/.panda
```

### per-connection 覆盖

通过 `initialize.userHome` 临时覆盖(每个 WS session 的 user_home),而不是改全局 `PANDA_HOME`。
当前架构下 per-connection `userHome == daemon-global PANDA_HOME`(每个用户一个 daemon,
启动时 read 自己的 `~/.panda/`),middleware 在 `pipa.stream.connect` 里把 `pw_dir/.panda`
塞进 initialize 帧,daemon 端无需任何代码改动即可在未来切到真正的 per-request HOME。

---

## §15 systemd unit packaging: Pipa 不绑 service 到任何 deb

**Rule**: pipa **不绑任何 systemd 单元到 deb**。per-user daemon 的 unit
由 middleware 在每次 `pipa.stream.connect` 时按 caller UID 渲染并 `sudo -u <user> tee` 写入
`~/.config/systemd/user/pipa.service`,然后用 `machinectl shell <user>@.host systemctl --user start`
拉起。pandacode deb 只装二进制,deb 的 postinst 是 no-op(无 daemon-reload,无 systemctl 调用)。

### 决定

| 单元 | 谁负责 |
|------|--------|
| `~/.config/systemd/user/pipa.service`(per-user) | middleware `PipaSupervisorService._write_unit_file` 渲染并写 |
| `~/.panda/`(per-user data dir) | middleware `PipaSupervisorService._ensure_panda_home` `sudo -u <user> mkdir -p -m 0700` |
| `/run/user/<uid>/pipa.sock`(per-user socket) | systemd `RuntimeDirectory=pipa` 自动建,daemon 自己 bind |
| 系统级 `pipa.service` / `/run/pipa/` / `/var/lib/panda/` | **不存在** — pandacode deb 完全不 ship |

### 为什么

- 每用户 daemon = per-user singletons(`AuthManager` / `ConfigManager` / thread store),
  进程隔离天然兜底,无需 systemd 单元层面再做隔离
- 真 UID 隔离:daemon 进程跑在该用户自己的 `systemd --user` instance 下,UID = caller,
  `~/.panda/` mode 0700 由 kernel 文件权限兜底
- pandacode 仓库**零代码改动**:pandacode daemon 早已支持 `--listen unix:///path`
  + `user_home` initialize 参数,supervisor 不用改 daemon
- middleware 不动 `main.py` 的 `pre_freeze_setup`(避免 Slice 0 raw WS 路径的踩坑)

### deb 侧的 no-op 标记

```makefile
# pandacode/Makefile 重装链 — 无 systemctl 调用
reinstall: clean build_deb install

# pandacode/debian/rules — dh_installsystemd 显式 override 为 no-op
override_dh_installsystemd:
	# No system unit shipped — per-user daemon is supervised by middleware.
	true
```

```sh
# pandacode/debian/postinst — configure 分支是空 :
case "$1" in
    configure)
        # Intentionally empty — see header comment.
        :
```

如果看到这些 no-op 被填充回去,review 必须 reject。

### 装 deb 后的 3-check 验证

```bash
# 1. 文件在没
ls /lib/systemd/system/pipa.service
# 2. 装了 systemctl 能看到
sudo systemctl list-unit-files pipa.service
# 3. enable + start 实际能跑
sudo systemctl enable --now pipa.service
sudo systemctl is-active pipa.service
```

### middleware 的 postinst 必须有

```bash
# middleware deb postinst:只触发,不要复制 unit
if dpkg -l panda-app-server >/dev/null 2>&1; then
    deb-systemd-invoke enable pipa.service || true
    systemctl restart pipa.service || true
fi
```

---

## §16 Repo ownership matrix

**Rule**: 跨 4 个仓库,每个仓库只能改自己范围内的文件,不能跨边界。

| 仓库 | 职责 | 不该碰 |
|------|------|--------|
| `webui/` | Angular 维护(legacy) | 不写新代码 |
| `webdesktop/` | React UI / SDK / apps | 不写 daemon / 不写 middleware |
| `middleware/` | 中间件 + schema + 路由 | 不写 SPA / 不写 rust |
| `pandacode/` | Daemon + Node.js bridge + systemd unit | 不写 UI / 不写 middleware |

### 为什么

- 每个仓库独立 git,跨边界 = 4 个独立 commit,容易冲突
- 中间件装到 NAS 上跟 pandacode deb 装到 NAS 上生命周期独立
- webdesktop 跟 middleware 之间走 JSON-RPC,不强耦合

### 验证

```bash
# 改 middleware 之前确认 cwd 是 middleware 仓库
cd /home/<you>/work/OpenNAS/middleware
git status  # 不要在 OpenNAS 顶层看到 middleware 改动
```

### 顶层 OpenNAS 仓库

- 改 `repos/manifests/*.xml` ✓
- 改 `tools/` ✓
- 改 `docs/` ✓
- 改 `*.md` ✓
- 改 `webdesktop/...` ❌
- 改 `middleware/...` ❌

---

## §17 Bash deploy script: subshell exit 陷阱

**Rule**: `tools/deploy-nas.sh` 来源 bash 有一些隐含陷阱:

1. **subshell `exit` 只退出 subshell**,不退出 main 脚本
2. **process substitution `<(...)` / `>(...)` 跟 subshell 一样**,里面的 `exit` 只退出 subshell
3. **early return 是关键** —— 失败立即 return,不要走完整个 flow

### 模板

```bash
# ✅ 对: 早期 return + 显式退出码
deploy_middleware() {
    if [[ ! -d "$MIDDLEWARE_DIR" ]]; then
        echo "❌ middleware not found at $MIDDLEWARE_DIR"
        return 1  # 退出函数,不是 main
    fi
    ...
}

main() {
    deploy_middleware || return 1  # 显式串联
    deploy_pandacode || return 1
    deploy_webdesktop || return 1
}

main "$@"
```

### ❌ 错

```bash
run_step() {
    if [[ ! -f "$1" ]]; then
        echo "missing"
        exit 1  # ← 只退出 subshell,main 继续
    fi
}

run_step "makefile"  # 即使失败,后面也继续跑
```

### 顺序 + 早返 + target registry

`deploy-nas.sh` 用 `declare -A TARGETS` 做 registry:

```bash
declare -A TARGETS=(
    [middleware]=deploy_middleware
    [pandacode]=deploy_pandacode
    [webdesktop]=deploy_webdesktop
)

for t in "${REQUESTED[@]}"; do
    fn="${TARGETS[$t]:-}"
    if [[ -z "$fn" ]]; then
        echo "unknown target: $t"
        return 1
    fi
    "$fn" || return 1
done
```

---

## §18 Commit checklist: 无 indexed annotations

**Rule**: 提交前 code review 必须包含"无 indexed annotations"项。
**commit message 本身也算**,不只是代码 / 注释。

### 详查

- 项目代号 (P3-104, A++, SPK)
- 阶段号 (Sprint 1, Phase 2, M0/M1)
- **日期** (2026-08-15 migrated, "after 14-reviews")
- 临时变量 (TODO-A, FIXME-X)
- 内部短语 (§3.4.5, "L347 cache fix")
- **规则标号 (R1~R9 / §1~§18)** — 读 commit 的人没法快速跳到那节。doc
  内部用编号没事(那节 anchor 就在 doc 顶上),commit message 引用就是
  索引断链。

### 为什么

读者几月后看 git blame `grep "P3-104"` 找不到对应 wiki / 文档 —— 这些字符串**永久存在**但**没有上下文锚点**。commit message 同理:`git log --grep "R1"` 找不到对应 doc,几个月后回看也只剩裸字符串。

### 模板

```python
# ❌ 错
"""Add tunnel_user_disabled column to truenas_connect.

P3-104 root-cause fix. After 14-reviews 2026-08-15 we realised ...

# ✅ 对
"""Add tunnel_user_disabled column to truenas_connect.

Replace the in-memory `self.connection is None` heuristic with a
durable user-intent flag. The reconciler reads this column across
reboots, HA failover, and watchdog cycles, so it can correctly
distinguish "user explicitly stopped the tunnel" from "tunnel task
died and needs a restart".
```

```bash
# ❌ 错: commit message 引用 R1-R9 规则标号
git commit -m "docs(system-app): R1-R9 约定 + 何时抽共享原件决策表"

# ✅ 对: 用规则的描述名,读者看得懂
git commit -m "docs(system-app): 共享组件约定(rule-of-two + tokens + memo)"
```

### 例外

- alembic 文件头 `Revision ID: ... Revises: ... Create Date: ...`(自动生成)✓
- `CHANGELOG.md` 顶层 changelog entry ✓
- commit message `Refs: #123` (issue 引用) ✓

---

## 修改记录

- 1.0 (2026-08-20) — 初始 10 规则,合并 14-reviews Pipa 教训
- 1.1 (2026-08-20) — 追加 8 节,从 memory 收敛:@api_method 薄壳 / App architecture / Pipa architecture / PANDA_HOME / systemd unit / repo ownership / bash subshell / commit checklist
