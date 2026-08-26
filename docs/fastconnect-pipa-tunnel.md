# Pipa via FastConnect Tunnel — Verification Guide

## 1. 结论先行:当前架构下,FastConnect **不需要为 Pipa 改任何代码**

Pipa 流式通道走 middleware 主 RPC + event channel(`pipa.stream`),
与 SMB / NFS / Docker / VM / FC 等完全同级 — FastConnect 隧道对路径透明,
**浏览器在远端走 `wss://qc-xxx.fastconnect.host/api/current` 一条隧道就够**,
不需要额外挂 `/_plugins/pipa/ws` route。

> 早期版本曾经计划加 `/_plugins/{path:path}` 透传路由,实测发现:
> - Pipa 走 event channel 同样能逐 token 推到浏览器(中间用 `should_send_event`
>   按 `ws.session_id` 单播,跨用户隔离天然成立)
> - 走主 RPC 不需要 `pre_freeze_setup` 钩子(`main.py` 保持不动)
> - FastConnect 隧道对 `/api/` 已经做了完整的 TLS / Origin / 鉴权透传,
>   Pipa 复用现有路径零工作量
>
> 因此决定:**`/_plugins/{path:path}` 路由不再为 Pipa 实现**。
> 如果日后 middleware 任何插件需要 raw WS 端点,再单独补,跟 Pipa 解耦。

---

## 2. 当前架构相对于早期方案的差异

| 早期方案(已废弃) | 当前架构 |
|---|---|
| 在 [fastconnect/app/api/browser_ws.py](../fastconnect/app/api/browser_ws.py) 加 `@router.websocket("/_plugins/{path:path}")` | **不改动** — `/_plugins/` 不存在 |
| 在 [middleware/.../plugins/truenas_connect/tunnel.py](../middleware/src/middlewared/middlewared/plugins/truenas_connect/tunnel.py) 加 `/_plugins/` 透传分支 | **不改动** — 只走 `/api/` |
| 浏览器连 `wss://qc-xxx.fastconnect.host/_plugins/pipa/ws` | 浏览器只连 `wss://qc-xxx.fastconnect.host/api/current`,Pipa 帧混在主 RPC 流里 |
| FastConnect 仓库至少 6 行新代码 | **0 行** |

---

## 3. 端到端验证

### 3.1 部署侧 (portal + NAS) — 无需为 Pipa 改任何东西

```bash
# 1. NAS 端 middleware 已升级到当前架构
midclt call core.get_events | python3 -c "import sys,json; d=json.load(sys.stdin); print('pipa.stream:', any(e['name']=='pipa.stream' for e in d))"
# 期望: pipa.stream: True

# 2. FastConnect 隧道配置不变
midclt call tn_connect.status
# 期望: state: CONNECTED, last_error: null

# 3. (重要回归)确认 FastConnect 代码里**没有**为 Pipa 加的特殊路由
grep -rn '_plugins' /home/truenas_admin/work/OpenNAS/fastconnect/app/api/ 2>/dev/null
# 期望: 无输出(或只有旧 _plugins/ 透传的提交残留,跟当前架构无关)
```

### 3.2 本机浏览器 (基线已通过)

```bash
# 在 NAS 上(确认 middleware 真的把 pipa.* namespace 暴露出来了):
midclt call pipa.status
# 期望: daemon_reachable: true(per-caller 状态)

# 注意: 不要 curl _plugins/pipa/ws(那个 URL 在当前架构里**不存在**):
curl -s http://127.0.0.1:6000/_plugins/pipa/ws -i | head -1
# 期望: HTTP/1.1 404 Not Found  ← 这是正确的,当前架构不挂这个 route
```

浏览器侧:打开 `https://nas.lan/`,按 `Cmd/Ctrl+K`,输入「hello」,确认
AI 流式回复正常(已通过)。

### 3.3 远端浏览器 (走 FastConnect)

1. 把 NAS 注册到 portal:`tn_connect` setup 流程
2. 在 portal 上拿到 system_id (e.g. `qc-aaa-bbb-ccc`)
3. 在 **远端浏览器** 打开 `https://qc-aaa-bbb-ccc.fastconnect.host/`
   (子域名格式) 或 `https://portal.fastconnect.host/fastconnect/qc-aaa-bbb-ccc/`
   (path 格式)
4. 登录 webdesktop(走 NAS user login,不要 portal login)
5. 按 `Cmd/Ctrl+K`,输入「hello」

期望:

- ✅ QuickPipaDialog 正常弹出
- ✅ 流式回复正常 (WS 帧能到达 browser)
- ✅ 浏览器 DevTools → Network → WS → **只看到主连接**
  `wss://qc-aaa-bbb-ccc.fastconnect.host/api/current`,
  Headers → `Status: 101 Switching Protocols`
- ✅ DevTools → Console 过滤 'pipa',看到 `pipa.stream` event delivery
  (`fields.frame` 里有 daemon 的 NDJSON)
- ✅ **没有** `_plugins/pipa/ws` 这个独立 WS 连接
- ✅ Messages 标签看不到 `_plugins/pipa/ws` 路径的请求

### 3.4 隧道诊断 (如果 3.3 失败)

逐层验证隧道:

```bash
# 1. portal 是否能解析到 NAS 系统
ssh portal-host
curl -s https://portal.fastconnect.host/api/v1/lookup/qc-aaa-bbb-ccc \
  -H "Authorization: Bearer <user_jwt>"
# 期望: status: ONLINE

# 2. portal 是否能给 browser 派 WS session
# 浏览器侧 DevTools 看主连接的 response code
# 期望: 101 Switching Protocols (在 /api/current)

# 3. NAS tunnel.py 收到 BIND_SESSION 时打印的 original_path
journalctl -u tn_connect -f | grep "BIND_SESSION\|path="
# 期望: path=/api/current (跟早期方案期望 path=/_plugins/pipa/ws 不同)

# 4. middleware 侧是否正常处理 pipa.stream
journalctl -u middlewared -f | grep "pipa"
# 期望: 看到 "pipa stream session opened: ...",没有 "connection failed"
```

### 3.5 单元测试

NAS 侧跑现有的 FastConnect path mapping 测试(没新增 case):

```bash
cd /home/truenas_admin/work/OpenNAS/middleware
python3 tests/run_unit_tests.py --path .
# 期望: 现有 test_truenas_connect_path_mapping 全过
# 不应**新增** _plugins 相关的 parametrize case(当前架构不走那条路)
```

---

## 4. 已知边界

| 项目 | 说明 | 何时处理 |
|------|------|----------|
| per-user thread 隔离 | 已用 per-user daemon 解决 | 已完成 ✅ |
| NAS context 注入 | AI 已经从 `initialize.userInfo` 拿到 username + roles | 已完成 ✅ |
| AI→middleware 回调的 session token 机制 | 当前 `userHome` + `userInfo` 已注入,但**没有**可验证 session token;AI 调回 middleware 的 RBAC 暂时不可强制 | Sprint L 后续方向 |
| 工具调用 + RBAC | AI 还不能调 `pool.extend` 等 | Sprint L 后续方向 |
| 高危操作审批 | 删 pool / dataset 不弹 modal | Sprint L 后续方向 |

完成里程碑:**本机 + 远端都能跟 AI 对话,且 Pipa 走主 RPC 通道,FastConnect 零代码改动**。

---

## 5. 改动一览 (本仓库)

无任何文件改动。

```
(middleware/src/middlewared/middlewared/plugins/truenas_connect/tunnel.py)
    — 不动 (Pipa 走主 RPC,不需 _plugins/ 透传)
    — 早期方案如果曾经加过 _plugins/ 透传,应在切回 event channel 时一并 revert

(middleware/src/middlewared/middlewared/pytest/unit/plugins/test_truenas_connect_path_mapping.py)
    — 不动 (现有 _plugins/ parametrize case 在当前架构下不再覆盖任何生产路径,
       如果团队希望精简,可以删除;但不影响功能)

(fastconnect/app/api/browser_ws.py)
    — 不动 (不挂 _plugins/{path:path} 路由)
```

无 deb 重打包(改动在 opcode.md 文档层 + middleware plugin 层,**无 fastconnect 改动**)。