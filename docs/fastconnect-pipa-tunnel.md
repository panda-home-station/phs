# Pipa via FastConnect Tunnel — Verification Guide

远端用户通过 FastConnect 隧道也能跟 Pipa 对话。本文档涉及改动
**只在两处,共 6 行代码**:

| 文件 | 改动 | 原因 |
|------|------|------|
| [middleware/src/middlewared/middlewared/plugins/truenas_connect/tunnel.py](../middleware/src/middlewared/middlewared/plugins/truenas_connect/tunnel.py) | `map_remote_path_to_local` 加 `/_plugins/` 透传分支 + `/api/_plugins/` 剥前缀分支 | NAS 端要知道把 `wss://portal/_plugins/pipa/ws` 转发到本地 `/_plugins/pipa/ws` |
| [fastconnect/app/api/browser_ws.py](../fastconnect/app/api/browser_ws.py) | `@router.websocket("/_plugins/{path:path}")` 挂在同一个 handler 上 | FastAPI 路由层新增 Pipa 入口,让浏览器侧 `wss://qc-xxx.fastconnect.host/_plugins/pipa/ws` 能命中 |

**fastconnect 仓库其他文件零改动**——隧道协议对 path 透明,只是多挂一条路由。

---

## 1. 部署侧 (portal + NAS)

### 1.1 portal 反代:确认 WS Upgrade 放行

FastConnect 用 Caddy/uvicorn 直连,不经过 nginx。如果以后 portal
前面套 nginx/caddy 反代,需要确认 `/_plugins/` 走 WS Upgrade:

```nginx
# nginx example
location /_plugins/ {
    proxy_pass http://fastconnect-backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 86400;        # 防止长连接被切断
}
```

如果 portal 已经为 `/api/` 和 `/websocket/` 配置过 WS Upgrade,新增
`/_plugins/` 只需要复制同一组 directive 即可。

### 1.2 NAS 侧:重启 middleware 加载新路由

```bash
# middleware 重新编译 + 重启
cd /home/truenas_admin/work/OpenNAS/middleware
make reinstall_container    # 容器构建,或
make reinstall              # 完整包重建

# fastconnect 重启(Caddyfile 改了的话)
cd /home/truenas_admin/work/OpenNAS/fastconnect
docker compose -f docker-compose.prod.yml restart portal
```

### 1.3 隧道自检

NAS 侧确保 `tn_connect` 服务在线,tunnel 已连到 portal:

```bash
midclt call tn_connect.status
# 期望: state: CONNECTED, last_error: null
```

---

## 2. 端到端验证 (Sprint 5 验收)

### 2.1 本机浏览器 (Sprint 3 基线已通过,这次再 sanity-check)

```bash
# 在 NAS 上:
curl -s http://127.0.0.1:6000/_plugins/pipa/ws -i | head -1
# 期望: HTTP/1.1 426 Upgrade Required  (curl 不带 Upgrade 头)
# 这是正确的,WS 端点拒绝 HTTP GET。

systemctl status pipa
# 期望: active (running)

ls -l /run/pipa/pipa.sock
# 期望: srw-r----- 1 root root ...  (socket 文件存在)
```

浏览器侧:打开 `https://nas.lan/`,按 `Cmd/Ctrl+K`,输入「hello」,确认
AI 流式回复正常(Sprint 3 已通过)。

### 2.2 远端浏览器 (Sprint 5 新增)

1. 把 NAS 注册到 portal:`tn_connect` setup 流程
2. 在 portal 上拿到 system_id (e.g. `qc-aaa-bbb-ccc`)
3. 在 **远端浏览器** 打开 `https://qc-aaa-bbb-ccc.fastconnect.host/`
   (子域名格式) 或 `https://portal.fastconnect.host/fastconnect/qc-aaa-bbb-ccc/`
   (path 格式)
4. 登录 webdesktop
5. 按 `Cmd/Ctrl+K`,输入「hello」

期望:

- ✅ QuickPipaDialog 正常弹出
- ✅ 流式回复正常 (WS 帧能到达 browser)
- ✅ 浏览器 DevTools → Network → WS → 看到连接到
  `wss://qc-aaa-bbb-ccc.fastconnect.host/_plugins/pipa/ws`,
  Headers → `Status: 101 Switching Protocols`
- ✅ Messages 标签看到 NDJSON 帧:
  `{"jsonrpc":"2.0","method":"item/agentMessage/delta",...}` 等

### 2.3 隧道诊断 (如果 2.2 失败)

逐层验证隧道:

```bash
# 1. portal 是否能解析到 NAS 系统
ssh portal-host
curl -s https://portal.fastconnect.host/api/v1/lookup/qc-aaa-bbb-ccc \
  -H "Authorization: Bearer <user_jwt>"
# 期望: status: ONLINE

# 2. portal 是否能给 browser 派 WS session
# 浏览器侧 DevTools 看 connect 帧的 response code
# 期望: 101 Switching Protocols

# 3. NAS tunnel.py 收到 BIND_SESSION 时打印的 original_path
journalctl -u tn_connect -f | grep "BIND_SESSION\|path="
# 期望: path=/_plugins/pipa/ws (或 /api/_plugins/pipa/ws)

# 4. middleware 的 pipa.ws_handler 是否到达
journalctl -u middlewared -f | grep "pipa"
# 期望: "pipa connection failed" 不应出现,正常的 frame forwarder 在跑
```

### 2.4 单元测试

NAS 侧跑 `map_remote_path_to_local` 的测试:

```bash
cd /home/truenas_admin/work/OpenNAS/middleware
python3 tests/run_unit_tests.py --path .
# 期望: test_truenas_connect_path_mapping.py 全过 (8 + 1 = 9 个 case)
```

或更精确:

```bash
pytest -vv \
  src/middlewared/middlewared/pytest/unit/plugins/test_truenas_connect_path_mapping.py
```

---

## 3. 已知边界 / 不在 Sprint 5 范围

| 项目 | 说明 | 何时处理 |
|------|------|---------|
| per-user thread 隔离 | Sprint 5 共用 `$CODEX_HOME=/root/.panda`,alice 和 bob 看到彼此 thread | Sprint 11 |
| NAS context 注入 | AI 还不知道这是 NAS / 当前用户是谁 | Sprint 9 |
| 工具调用 + RBAC | AI 不能调 `pool.extend` 等 | Sprint 7 |
| 高危操作审批 | 删 pool / dataset 不弹 modal | Sprint 8 |

Sprint 5 完成里程碑:**本机 + 远端都能跟 AI 对话,AI 能做通用编程/问答任务
(但还没成为 NAS 级助手)**。

---

## 4. 改动一览 (本仓库 Sprint 5 commit)

```
middleware/src/middlewared/middlewared/plugins/truenas_connect/tunnel.py
    + map_remote_path_to_local: 增加 /_plugins/ 透传 + /api/_plugins/ 剥前缀

middleware/src/middlewared/middlewared/pytest/unit/plugins/test_truenas_connect_path_mapping.py
    + 5 个新 parametrize case (覆盖 _plugins/* + api/_plugins/*)
    + 1 个 test_plugins_passthrough_no_double_slash 回归 test

fastconnect/app/api/browser_ws.py
    + @router.websocket("/_plugins/{path:path}") 挂在同一 handler
```

无 deb 重打包(改动是 module-level 函数 + WS route decorator,无 schema 变化)。