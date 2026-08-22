# Pipa 测试 Runbook (Sprint 1-5 验收)

按 sprint 顺序跑。每个 sprint 都有「快速命令」+ 「成功标志」+ 「失败排查」三段。
**任何一步失败都先停下,别继续后面的步骤**——后面的依赖前面的产物。

---

## 0. 预检 (任何 sprint 开始前)

```bash
cd /home/truenas_admin/work/OpenNAS

# 仓库布局确认
ls middleware/ webdesktop/ pandacode/ fastconnect/  # 4 个目录都在

# 工具链探测
which cargo rustc node npm python3 dpkg-buildpackage midclt systemctl curl

# TrueNAS 是否就绪
midclt call system.ready
# 期望: True
```

**已知缺口**:`cargo` / `rustc` 默认没装。两种处理:
- A. 在 dev 机器上 `cd pandacode && make build_deb`,把 `.deb` scp 到 NAS 后 `dpkg -i`
- B. 在 NAS 上装 Rust:`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`

---

## 1. Sprint 1:pandacode deb + systemd

**目标**:`panda-app-server` 跑起来,socket 在 `/run/pipa/pipa.sock`。

```bash
# 1.1 装 rustup(若用方案 B)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
source $HOME/.cargo/env

# 1.2 编译 + 装 deb
cd /home/truenas_admin/work/OpenNAS/pandacode
make reinstall

# 1.3 验证 deb 内容(可选)
dpkg -L panda-app-server | head -10
# 期望: /usr/sbin/panda-app-server 是 binary,不是空文件

# 1.4 middleware 的 pipa.service 应已通过 middleware/debian 的 postinst 拉起
systemctl status pipa
# 期望: active (running)

ls -l /run/pipa/pipa.sock
# 期望: srw-r----- 1 root root ...  (socket 文件存在)

# 1.5 重启 systemd 不应影响 middleware 主功能
systemctl restart pipa
systemctl status middlewared | head -3
# 期望: middlewared 仍 active (running)
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| `cargo: command not found` | §0 选 A (dev 机器 build) |
| `dpkg-buildpackage: unmet build dependencies: cargo` | 同上 |
| `systemctl status pipa` 显示 `inactive (dead)` | `journalctl -u pipa -n 30 --no-pager` 看 startup error |
| `/run/pipa/pipa.sock` 不存在 | 检查 `tmpfiles.d/pipa.conf` 是否安装 + `RuntimeDirectory=pipa` 是否生效 |
| `/usr/sbin/panda-app-server: not found` | deb 没装,看 `dpkg -l | grep panda-app-server` |

---

## 2. Sprint 2:middleware pipa plugin 骨架

**目标**:`/_plugins/pipa/ws` 路由可用,sync RPC (`pipa.status` / `pipa.user_prefs.query`) 返回正常。

```bash
# 2.1 重装 middleware
cd /home/truenas_admin/work/OpenNAS/middleware/src/middlewared
make reinstall_container    # 容器模式,或 `make reinstall` 包模式

# 2.2 等 5s 启动,验证
sleep 5
midclt call pipa.status
# 期望: {"socket_exists": true, "daemon_reachable": true, "socket_path": "/run/pipa/pipa.sock"}

# 2.3 验证插件路由确实挂上
curl -s http://127.0.0.1:6000/_plugins/pipa/ws -i | head -1
# 期望: HTTP/1.1 426 Upgrade Required  (curl 不带 Upgrade 头)

# 2.4 验证 CRUD 接口
midclt call pipa.user_prefs.query
# 期望: []  (没人配过)
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| `CallError: method pipa.status not found` | middleware 没重启 / plugin 没加载,看 `journalctl -u middlewared | grep pipa` |
| `daemon_reachable: false` 但 socket 存在 | `journalctl -u pipa -n 10` 看 daemon 是不是 panic 了 |
| `426 Upgrade Required` 但 WS 实际握手不上 | middleware 没到 mount,确认 `setup()` 被调用了 |
| alembic migration 没跑 | `midclt call datastore.query pipa_user_prefs` 报表不存在 → `cd middleware && make migrate` |

---

## 3. Sprint 3:webdesktop SDK + apps/pipa + Cmd+K

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

# 3.3 浏览器:打开 https://<nas>/,登录 root 或某用户
# 3.4 按 Cmd+K (macOS) 或 Ctrl+K (Linux/Windows)
#     期望:右下角弹一个浮动输入框 "和 Pipa 聊聊..."

# 3.5 探测 daemon 是否就绪(弹窗右上角 badge)
#     期望: ● 就绪 (绿色);若灰色 → daemon unreachable

# 3.6 输入 "hello" + Enter
#     期望:apps/pipa 窗口打开,首条用户消息自动发出

# 3.7 等 AI 回复
#     期望:消息流式出现(逐字/逐词),完成后停止

# 3.8 DevTools → Network → WS → 看连接
#     URL: wss://<nas>/_plugins/pipa/ws
#     Status: 101 Switching Protocols
#     Messages 标签:
#       {"jsonrpc":"2.0","id":0,"method":"initialize",...}
#       → 服务端 ack
#       客户端 → {"jsonrpc":"2.0","method":"initialized"}
#       → {"jsonrpc":"2.0","id":1,"method":"thread/start",...}
#       → {"jsonrpc":"2.0","id":2,"method":"turn/start",...}
#       ← {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"delta":"Hi"}}
#       ← ... 更多 delta
#       ← {"jsonrpc":"2.0","method":"turn/completed",...}
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| Cmd+K 没反应 | 看 `~/.xsession-errors` 或 DevTools console,有 JS 报错 |
| 弹窗 "AI 助手暂未就绪" | `midclt call pipa.status` 看 daemon_reachable |
| 弹窗 OK,apps/pipa 打开但一直转圈 | DevTools WS 没握上手,看 Network panel 的 404/403 |
| 流式回复卡顿/丢失 | `journalctl -u middlewared -f` 看 panda-app-server 日志 |
| 全程无回复但 daemon 活着 | AI provider 的 key 没配,见 Sprint 4 |

---

## 4. Sprint 4:Settings + EncryptedText API key

**目标**:填 openai API key → DB 里是密文 → 重启 webdesktop 仍 `api_key_set=true`。

```bash
# 4.1 (前置)打开 apps/pipa → 点右上齿轮 → Settings 面板

# 4.2 选 provider=openai,model=gpt-4o-mini(便宜的测试模型),
#     在 API Key 输入框填入你的 openai key (sk-...)

# 4.3 点 "测试连接" 按钮
#     期望:右侧出现绿色 ✓ (testProvider 走 panda-app-server model/list round-trip)

# 4.4 点 "保存"
#     期望:绿色 "已保存" toast,API key 输入框被清空(本地不残留)

# 4.5 直查 DB 看密文(不要查磁盘 log)
sudo sqlite3 /var/db/system/sysdb/sysdb.db \
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
sudo sqlite3 /var/db/system/sysdb/sysdb.db \
  "SELECT api_key_encrypted FROM pipa_user_prefs"
# 期望: NULL
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| 找不到 sysdb.db | `find / -name "sysdb.db" 2>/dev/null`;TrueNAS SCALE 可能在 `/data/` |
| `api_key_encrypted` 是明文 | 致命安全 bug — EncryptedText column 没生效,看 §"EncryptedText 调试" |
| 测试连接失败但 daemon 活着 | key 无效;curl https://api.openai.com/v1/models -H "Authorization: Bearer $KEY" 先验证 |
| 没看到审计 log | middleware 没重启用新版,确认 `make reinstall` 而不是 `make install` |

### EncryptedText 调试 (Sprint 4 深度排查)

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

## 5. Sprint 5:FastConnect 隧道

**目标**:远端浏览器走 portal 域名,Cmd+K 弹窗 + 对话正常。

```bash
# 5.1 (前置)portal.fastconnect.host + 此 NAS 都已注册
#     portal 端:
curl -s https://portal.fastconnect.host/api/v1/lookup/qc-xxx \
  -H "Authorization: Bearer $USER_JWT"
# 期望: status: ONLINE

# 5.2 NAS 端 tunnel 在线
midclt call tn_connect.status | head -20
# 期望: state: CONNECTED, last_error: null

# 5.3 在远端浏览器(手机/家外网络):
#     打开 https://qc-xxx.fastconnect.host/
#     登录 webdesktop (走 NAS user login,不要 portal login)

# 5.4 DevTools → Network → 测 WS 握手:
#     手动连 wss://qc-xxx.fastconnect.host/_plugins/pipa/ws
#     期望:101 Switching Protocols
#     若 404: portal 路由没起来,看 fastconnect 端 `docker compose logs portal`

# 5.5 DevTools → Application → 看 fastconnect 是否注入了 Sec-WebSocket-Protocol: bearer

# 5.6 Cmd+K 弹窗 + "hello" 对话
#     期望:跟 Sprint 3 本机行为一致

# 5.7 (诊断)三层日志
journalctl -u middlewared -f | grep -i "pipa"      # NAS middleware
journalctl -u tn_connect -f | grep -i "tunnel"     # NAS tunnel
docker compose -f fastconnect/docker-compose.prod.yml logs -f portal | grep -i "_plugins\|path"
# 期望:NAS 看到 path=/_plugins/pipa/ws;portal 看到 forward 成功
```

**失败排查**:

| 症状 | 排查 |
|------|------|
| 远端 `/_plugins/pipa/ws` 404 | FastAPI 路由没注册,看 `docker compose logs portal | grep browser_ws` |
| 404 但 fastconnect 端看到 `_plugins/` 已注册 | Caddyfile 把 `/_plugins/` 反代到了别的 backend |
| 远端 `WS 握手 1008 invalid host` | portal 反代没把 Host header 透传,看 nginx/caddy `proxy_set_header Host $host` |
| 远端 WS 握手 OK 但消息无回复 | `tn_connect.status` 看 tunnel 是不是断的 |
| 看到 `1011 Device offline` | NAS tunnel 没连 portal,重启 `systemctl restart middlewared` 触发重连 |

---

## 6. 自动化一键脚本

如果想一次跑完所有 sprint 的 sanity check:

```bash
# (在 NAS 上,root 用户)
bash /home/truenas_admin/work/OpenNAS/tools/check-pipa-status.sh
```

这个脚本会跑:
- `systemctl is-active pipa middlewared`
- `ls -l /run/pipa/pipa.sock`
- `midclt call pipa.status`
- `midclt call pipa.user_prefs.query | head`
- `curl -s -i http://127.0.0.1:6000/_plugins/pipa/ws | head -1`
- DB 加密验证 (SELECT substr api_key_encrypted)
- `tn_connect.status`(Sprint 5 才有意义)

期望输出:全 ✓ + 1 行总结。

---

## 7. 出问题报 bug 时附什么

最小可复现信息:

```
TrueNAS SCALE 版本: cat /etc/os-release | head -3
Sprint: (1/2/3/4/5)
失败点: (具体哪个命令/操作)
期望: (应该看到什么)
实际: (看到了什么)
journal 摘录: journalctl -u <pipa|middlewared|tn_connect> --since "5 min ago" --no-pager | tail -50
前端 console 报错: (浏览器 DevTools → Console)
WS 帧序列: (DevTools → Network → WS → Messages 标签导出)
DB 状态: SELECT * FROM pipa_user_prefs (脱敏,不含 api_key 明文)
```

---

## 参考

- `docs/fastconnect-pipa-tunnel.md` — Sprint 5 远端接入详情
- `middleware/.../plugins/pipa.py` — 全栈 plugin 入口
- `webdesktop/src/shared/sdk/pipa.ts` — 浏览器 SDK
- `pandacode/Makefile` + `debian/` — deb 打包