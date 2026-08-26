# Pipa 测试 Runbook (验收)

按步骤顺序跑。每段都有「快速命令」+ 「成功标志」+ 「失败排查」三段。
**任何一步失败都先停下,别继续后面的步骤**——后面的依赖前面的产物。

> **重要前提**:Pipa 是 per-user daemon,**不存在** `/run/pipa/pipa.sock`
> 或 `systemctl status pipa` 这种系统级概念。daemon 跑在每个 TrueNAS 用户自己的
> `systemd --user` instance 下,socket 在 `/run/user/<uid>/pipa.sock`。
>
> 本 runbook 假设:
> - 至少两个 TrueNAS 用户已存在(例如 `apple` / `banana`),各自能登录 webdesktop
> - middleware + pandacode + webdesktop 三个 deb 都已通过 `tools/deploy-nas.sh --target <name>` 装好
> - 至少一个 provider 的 API key 已配(否则流式测试到"Sprint 3"阶段会卡)

---

## 0. 预检 (任何步骤开始前)

```bash
cd /home/truenas_admin/work/OpenNAS

# 仓库布局确认
ls middleware/ webdesktop/ pandacode/ fastconnect/  # 4 个目录都在

# 工具链探测
which cargo rustc node npm python3 dpkg-buildpackage midclt systemctl curl

# TrueNAS 是否就绪
midclt call system.ready
# 期望: True

# 关键:系统级 pipa unit 不应存在(per-user daemon 时代)
systemctl status pipa.service 2>&1 | head -1
# 期望: Unit pipa.service could not be found.

# 关键:deb 已装
dpkg -l panda-app-server | tail -1
# 期望: ii  panda-app-server  0.1.0-...
```

**已知缺口**:`cargo` / `rustc` 默认没装。两种处理:
- A. 在 dev 机器上 `cd pandacode && make build_deb`,把 `.deb` scp 到 NAS 后 `dpkg -i`
- B. 在 NAS 上装 Rust:`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

---

## 1. 基础设施:per-user daemon 拉起链路

**目标**:首次 Cmd+K 触发 middleware supervisor 拉起 apple 用户的 daemon,socket 出现在
`/run/user/<apple-uid>/pipa.sock`,daemon accept-ready。

```bash
# 1.1 linger 已开(否则用户登出后 daemon 跟着死)
sudo loginctl enable-linger apple banana
loginctl show-user apple Linger=
loginctl show-user banana Linger=
# 期望: 都输出 Linger=yes

# 1.2 用 apple 登录 webdesktop(浏览器),按一次 Cmd+K(或 Taskbar 机器人按钮)
#     → middleware 内部跑 PipaSupervisorService.ensure_running_for_caller:
#        loginctl enable-linger / sudo -u apple tee unit / mkdir -p ~/.panda /
#        machinectl shell start / 探 socket

# 1.3 验证 apple 的 daemon 跑起来了
ps -eo pid,rss,user,args --no-headers | grep '[p]anda-app-server.*--listen unix:///run/user/'
# 期望: 一行,user=apple,args 里含 --listen unix:///run/user/<apple-uid>/pipa.sock

ls -la /run/user/<apple-uid>/pipa.sock
# 期望: srw------- 1 apple apple

ls -la /home/apple/.config/systemd/user/pipa.service
# 期望: -rw-r--r-- 1 apple apple (middleware 渲染时已 sudo -u 写)

ls -la /home/apple/.panda
# 期望: drwx------ 6 apple apple (middleware _ensure_panda_home 建)

# 1.4 验证 apple 的 daemon accept-ready(不是 stale socket)
midclt call pipa.status
# 期望: daemon_reachable: true

# 1.5 用 banana 重复 1.2-1.4
#     然后再跑一次 ps,期望 2 行
ps -eo pid,rss,user,args --no-headers | grep '[p]anda-app-server.*--listen unix:///run/user/'
# 期望: 2 行,user=apple + user=banana
# 实测: 2 daemon 总 RSS ~80-120 MB
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| `machinectl shell` 报 `Permission denied` | `apple` 用户不在 `users` 组,`usermod -aG users apple` |
| `_write_unit_file` 卡住 | `sudo -u apple tee` 失败,看 `journalctl -u middlewared` 的 supervisor 警告 |
| socket 文件出现但 `daemon_reachable: false` | `journalctl --user -u pipa.service -M apple@.host -n 30` 看 daemon 启动日志 |
| `_wait_socket` 超时(5-10s) | pandacode 启动慢,首次启动 + workspace load 可能 5-8s,确认 `_wait_socket(timeout=10.0)` 生效 |
| daemon 跑了几秒就退出 | 看 `~/.panda/logs/` 的 sqlite;最常见是 API key 无效触发的 panic |
| apple 能起,banana 起不来 | 第二个用户的 home 目录权限错位,`sudo -u banana ls /home/banana` 检查 |

---

## 2. 流式通道:main RPC event channel 单播

**目标**:webdesktop SDK 通过 `pipa.stream.connect` + 订阅 `pipa.stream` event channel,
拿到 daemon 的 NDJSON 帧;浏览器 DevTools 看到 WS 主连接 `/api/current`,
**而不是**任何 `/_plugins/pipa/ws` 独立 WS 端点。

```bash
# 2.1 验证 main RPC 端点存在
midclt call pipa.stream.connect 2>&1 | head -3
# 期望: 返回 true (Literal[True])

# 2.2 验证 event channel 已注册
midclt call core.get_events | python3 -c "import sys,json; d=json.load(sys.stdin); print([e['name'] for e in d if 'pipa' in e['name']])"
# 期望: ['pipa.stream']

# 2.3 (用 apple 登录浏览器) Cmd+K → QuickPipaDialog 弹窗
#     右上角 badge 应是绿色 ● 就绪;若灰 → daemon unreachable,回到 §1 排查
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| `CallError: pipa.stream.connect method not found` | middleware 没重启 / plugin 没加载,`journalctl -u middlewared \| grep pipa` |
| `CallError: Pipa daemon for uid N not reachable` | 回到 §1 — supervisor `_wait_socket` 超时 |
| 弹窗 "AI 助手暂未就绪" | daemon unreachable;`midclt call pipa.status` 看字段 |
| DevTools 看到 `_plugins/pipa/ws` 连接 | **错的** — 当前架构走主 RPC;说明前端在用老版本,SPA 需 Ctrl+Shift+R 硬刷 |

---

## 3. webdesktop SDK + apps/pipa + Cmd+K

**目标**:浏览器开 webdesktop → Cmd+K → 输入"hello" → 收到 AI 流式回复。

```bash
# 3.1 webdesktop 编译 + 装
cd /home/truenas_admin/work/OpenNAS/webdesktop
npm ci
npm run build
# 把 dist/ 拷到 nginx serving dir,或 symlink:
sudo ln -sf /home/truenas_admin/work/OpenNAS/webdesktop/dist /usr/share/truenas-webdesktop/

# 3.2 重启 webserver (假设 nginx 反代)
systemctl restart nginx  # 或 caddy

# 3.3 浏览器:打开 https://<nas>/,登录 root 或 apple
# 3.4 按 Cmd+K (macOS) 或 Ctrl+K (Linux/Windows)
#     期望:右下角弹一个浮动输入框 "和 Pipa 聊聊..."
#     或 Taskbar 上的机器人图标

# 3.5 探测 daemon 是否就绪(弹窗右上角 badge)
#     期望: ● 就绪 (绿色);若灰色 → daemon unreachable

# 3.6 输入 "hello" + Enter
#     期望:apps/pipa 窗口打开,首条用户消息自动发出

# 3.7 等 AI 回复
#     期望:消息流式出现(逐字/逐词),完成后停止

# 3.8 DevTools → Network → WS → 看**主**连接
#     URL: wss://<nas>/api/current
#     Status: 101 Switching Protocols
#     Messages 标签**只看到主 RPC 帧**(core.subscribe / core.call 等)
#
# 3.9 同时打开 DevTools → Console,过滤 'pipa'
#     期望: 看到 ['pipa.stream'] event delivery (fields.frame 里有 daemon 的 NDJSON)
#            initialize 握手由 middleware 代发,SDK 不发自己的 initialize
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| Cmd+K 没反应 | 看 `~/.xsession-errors` 或 DevTools console,有 JS 报错 |
| 弹窗 "AI 助手暂未就绪" | `midclt call pipa.status` 看 daemon_reachable |
| 弹窗 OK,apps/pipa 打开但一直转圈 | DevTools WS 主连接没握上,看 Network panel 的 404/403 |
| 流式回复卡顿/丢失 | `journalctl -u middlewared -f` + `journalctl --user -u pipa.service -M apple@.host -f` |
| 全程无回复但 daemon 活着 | AI provider 的 key 没配,见 §4 |

---

## 4. Settings + EncryptedText API key

**目标**:填 openai API key → DB 里是密文 → 重启 webdesktop 仍 `api_key_set=true`。

```bash
# 4.1 (前置)打开 apps/pipa → 点右上齿轮 → Settings 面板

# 4.2 选 provider=openai,model=gpt-4o-mini(便宜的测试模型),
#     在 API Key 输入框填入你的 openai key (sk-...)

# 4.3 点 "测试连接" 按钮
#     期望:右侧出现绿色 ✓ (走 pipa.test_provider → transient session → model/list)

# 4.4 点 "保存"
#     期望:绿色 "已保存" toast,API key 输入框被清空(本地不残留)

# 4.5 直查 DB 看密文(不要查磁盘 log)
sudo sqlite3 /data/freenas-v1.db \
  "SELECT id, user_id, provider, model, substr(api_key_encrypted, 1, 30) FROM pipa_user_prefs"
# 期望: api_key_encrypted 是 "0ENC..." / "!..." / 长 base64 之类,**不含 "sk-"**

# 4.6 重启 browser session,重开 apps/pipa → Settings
#     期望: 输入框 placeholder = "••••••••••(已设置)",Save 按钮亮
#     等价检测:在 DevTools console 跑
#       await window.truenasApi.call('pipa.user_prefs.query')
#     期望: [{ ..., "api_key_set": true }]

# 4.7 (回归)审计 log 验证
journalctl -u middlewared --since "5 min ago" --no-pager | grep -i "pipa"
# 期望: 看到 "audit: pipa.user_prefs.create user_id=N provider=openai api_key_set=True"
#       **不应**有 sk- 开头的明文

# 4.8 (可选)清空测试
# 在 Settings 里 API Key 框输入空字符串 + 保存
sudo sqlite3 /data/freenas-v1.db \
  "SELECT api_key_encrypted FROM pipa_user_prefs"
# 期望: NULL
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| `api_key_encrypted` 是明文 | 致命安全 bug — EncryptedText column 没生效,看 §"EncryptedText 调试" |
| 测试连接失败但 daemon 活着 | key 无效;`curl https://api.openai.com/v1/models -H "Authorization: Bearer $KEY"` 先验证 |
| 没看到审计 log | middleware 没重启用新版,确认 `make reinstall` 而不是 `make install` |

### EncryptedText 调试 (§4 深度排查)

如果 `api_key_encrypted` 是明文,说明 SQLAlchemy column type 没生效:

```bash
# 1. 看 model 实际注册的 column type
python3 -c "
import sys
sys.path.insert(0, '/home/truenas_admin/work/OpenNAS/middleware/src/middlewared')
from middlewared.sqlalchemy import Model
from middlewared.plugins.pipa import PipaUserPrefsModel
print(type(PipaUserPrefsModel.__table__.c.api_key_encrypted.type).__name__)
"
# 期望: EncryptedText
# 若 = Text → model 没被加载,plugin 未 import

# 2. 看 encrypt/decrypt 是不是 False 桩函数
python3 -c "
import sys; sys.path.insert(0, '/home/truenas_admin/work/OpenNAS/middleware/src/middlewared')
import middlewared.sqlalchemy as sa
print(sa.encrypt, sa.decrypt)
"
# 期望: <function encrypt at 0x...> (真函数);若 <function False at ...> → 测试 mock 残留

# 3. 手动 encrypt 测试
python3 -c "
import sys; sys.path.insert(0, '/home/truenas_admin/work/OpenNAS/middleware/src/middlewared')
from middlewared.sqlalchemy import encrypt
print(encrypt('sk-test-123'))
"
# 期望: 长字符串 (Fernet / base64);若是空字符串 → encrypt 被 monkey-patch 了
```

---

## 5. 多用户隔离回归

**目标**:alice 的 `~/.panda/` 对 bob 不可见,thread store / auth.json / config.toml 隔离。

```bash
# 5.1 (前置)alice 和 banana 都触发过 Cmd+K(各自 daemon 都在跑)

# 5.2 alice 的 panda home 对 banana 不可读
sudo -u banana ls /home/alice/.panda
# 期望: Permission denied (kernel UID 隔离兜底)

# 5.3 alice 的 daemon 进程只看 alice 的 home
ls -l /proc/<alice-pid>/cwd
# 期望: /home/alice(daemon 进程的 cwd 由 systemd --user 上下文决定)

# 5.4 alice 用 QuickPipaDialog 开新 thread,然后 banana 也开新 thread
#     两个 thread id 不重叠,alice 看不到 banana 的 thread,反之亦然

# 5.5 重启 alice 的 daemon,验证 thread store 重置(per-user 进程隔离)
sudo machinectl shell alice@.host /usr/bin/systemctl --user restart pipa.service
# 等 3s,alice 再开 Cmd+K,期望 thread 列表空了(或只剩 restart 之前已存档的)

# 5.6 重启 middlewared 期间 per-user daemon **不挂**
sudo systemctl restart middlewared
# 等 5s,alice 仍能 Cmd+K 直接对话(systemd --user instance 维持)
midclt call pipa.status
# 期望: daemon_reachable: true
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| banana 能 ls 进 alice 的 `~/.panda` | 权限错位,`stat /home/alice/.panda` 看 mode 应是 0700 owner=alice |
| alice 看到 banana 的 thread | per-user daemon 进程隔离失效,确认 `ps -eo user,pid,args` 里两个 daemon 真的 user=alice/user=banana |
| 重启 middlewared 后 daemon unreachable | linger 没开(用户登出导致 systemd --user instance 跟着停),`loginctl show-user <uid> Linger=` |

---

## 6. 自动化一键脚本

如果想一次跑完所有 sanity check:

```bash
# (在 NAS 上,root 用户)
bash /home/truenas_admin/work/OpenNAS/tools/check-pipa-status.sh
```

这个脚本应该覆盖:
- `systemctl is-active middlewared`(系统 unit,应该 active)
- `systemctl status pipa.service`(系统 unit,**应该 NOT found**)
- `ps -eo user,pid,args | grep '[p]anda-app-server.*--listen unix:///run/user/'`(per-user daemon 列表)
- `ls -la /run/user/*/pipa.sock`(per-user socket 列表)
- `midclt call pipa.status`(per-caller 状态)
- `midclt call pipa.user_prefs.query | head`
- DB 加密验证 (`SELECT substr api_key_encrypted`)

期望输出:全 ✓ + 1 行总结。

---

## 7. 出问题报 bug 时附什么

最小可复现信息:

```
TrueNAS SCALE 版本: cat /etc/os-release | head -3
Slice: (1 / 2 / 3 / 4 / 5)
触发用户: (具体哪个 TrueNAS 用户触发了)
失败点: (具体哪个命令/操作)
期望: (应该看到什么)
实际: (看到了什么)

Per-user daemon 日志(关键):
  sudo journalctl --user -u pipa.service -M <user>@.host --since "5 min ago" --no-pager | tail -50

Middleware 日志:
  sudo journalctl -u middlewared --since "5 min ago" --no-pager | tail -50

前端 console 报错: (浏览器 DevTools → Console)
WS 帧序列: (DevTools → Network → WS → Messages 标签,**只看主连接 /api/current**)
DB 状态: SELECT * FROM pipa_user_prefs (脱敏,不含 api_key 明文)
```

---

## 参考

- `docs/pipa-deploy-on-this-nas.md` — 部署流程
- `docs/fastconnect-pipa-tunnel.md` — FastConnect 远端接入
- `middleware/.../plugins/pipa.py` — middleware 业务侧(stream + status + provider)
- `middleware/.../plugins/pipa_supervisor.py` — per-user daemon supervisor
- `webdesktop/src/shared/sdk/pipa.ts` — 浏览器 SDK
- `pandacode/Makefile` + `debian/` — deb 打包(无 systemd 单元)
