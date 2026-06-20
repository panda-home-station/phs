# FastConnect 内网穿透 — 跨仓库 Code Review

- **日期**：2026-06-19
- **范围**：fastconnect / middleware (truenas_connect plugin) / truenas_connect_utils / webdesktop (FastConnect SDK)
- **目的**：在打下一个 release 前做一次完整的 adversarial review，按 P0/P1/P2/P3 排序，给出 file:line + 修复建议
- **状态**：临时文档，未提交根仓库（根仓库 git status 会显示为 untracked）

## 修复进度

| P0 # | 仓库 | 状态 | Commit | 备注 |
|---|---|---|---|---|
| #9 | truenas_connect_utils | ✅ done | `0ce1d7a` | cert 100% 失败（acme.py 字段覆盖） |
| #3 | fastconnect | ✅ done | `64f6e87` | 永久负缓存（host_resolver TTL） |
| #2 | fastconnect | ✅ done | `64d5c61` | ACME 路径穿越（qc_id 白名单） |
| #1 | fastconnect | ✅ done | `5c1e6dd` | finalize 鉴权绕过（删两个 bypass 分支） |
| #4 | fastconnect | ✅ done | `8d18349` | previous_secret 永不过期（24h TTL） |
| #5 | fastconnect | ✅ done | `32c9829` | share_link 竞态（with_for_update + 双保险） |
| #6 | middleware + fastconnect | ✅ done | `ba6b533` + `779dfd3` | 隧道 JWT 不再走 URL query（server-to-server 端） |
| #7 | middleware | ✅ done | `d9f43a5` | SSRF 防护加固（method 白名单 + 全控制字符 + 反斜杠 + scheme + 长度） |
| #8 | truenas_connect_utils + middleware | ✅ done | `2e513b7` + `8c1530b` | renewalInfo 缺失兜底（utils `.get()` + middleware expiry-based fallback） |
| #12 | truenas_connect_utils | ✅ done | `1f7599e` | debian/control 缺运行时依赖（aiohttp/cryptography/josepy/truenas-acme-utils） |
| #10 | middleware | ✅ done | `e025da0` | initiate_cert_generation 并发无锁（@job lock + 状态机入口检查） |
| #11 | truenas_connect_utils | ✅ done | `ae8048d` | `asyncio.timeout` Python 3.9 不兼容（改用 `asyncio.wait_for`） |
| #10 | truenas_connect_utils | ✅ done | `5f0d115` | `get_base_domain_from_hostnames` 对新 qc_id 架构永远 None（取最后 2 段） |
| #13 | webdesktop | ✅ done | `b28377f` | `waitForPunchMessage` 静默吞 PUNCH_ERROR / 不监听 onclose / listener leak（settle() 统一收尾 + 10 个测试） |
| #14 | webdesktop | ✅ done | `0f9d10e` | JWT in localStorage XSS 风险（改 sessionStorage + 老位置无条件清理 + 4 个测试） |
| #15 | webdesktop + fastconnect | ✅ done | `9d77403` + `82106fe` | Token in URL query（改 `bearer:<token>` subprotocol + server 拒绝 query 来源 + 9 个测试） |

## P1 修复进度

> **当前进度:P1 已修 41/41,剩余 0 项 — 全段清账 ✅** 详细 commit 见下方表格。
> (此前进度计数 "28" 是 review 初稿估算,实际 P1 段共 41 个编号项 #16-#56;已修 41 项=表格里所有 ✅。)

| P1 # | 仓库 | 状态 | Commit | 摘要 |
|---|---|---|---|---|
| #22 | fastconnect | ✅ done | `0c680f4` | Caddyfile `encode gzip` 断 WS（6 秒断连 → `handle @ws` + `handle` 分流） |
| #53 | webdesktop | ✅ done | `70f90d4` | LoginContainer console.log 无条件跑（`import.meta.env.DEV` gate + no-console disable） |
| #18 | fastconnect | ✅ done | `afc0096` | message.py 坏消息 ValueError 断 tunnel（`TunnelMessageError` + skip 单条） |
| #16 | fastconnect | ✅ done | `8e7921e` | SSO `_SSO_PENDING` 无锁（`asyncio.Lock` + size cap 10000 + 唯一性检查） |
| #20 | fastconnect | ✅ done | `849ea2a` | pending_requests cancel 不 pop（`finally` 块统一 pop） |
| #25 | middleware | ✅ done | `924ff5a6cd` | `decode_and_validate_token` 不验签 + 无 system_id 交叉校验（`system.global.id` cross-check + 2 个 call site 传参） |
| #24 | middleware | ✅ done | `7da0991270` | 异常 `str(e)` 直返 500 body 泄漏堆栈/DB URL（`build_safe_error_response` + correlation_id + 7 个测试） |
| #44 | truenas_connect_utils | ✅ done | `b9be360` | setup.py 用 distutils（3.12 移除）+ 无 install_requires（换 setuptools + 加依赖列表 + 8 个测试） |
| #21 | fastconnect | ✅ done | `bfcf35d` | `cleanup_old_events` 阻塞启动（`asyncio.create_task` + `to_thread` 后台跑 + 4 个测试） |
| #17 | fastconnect | ✅ done | `f8093e9` | punch_coordinator `initiate` 非原子 + `attach_browser` 静默覆盖(`_state_lock` 串行化 check+write + `PUNCH_SUPERSEDED` 通知旧 tab + `BrowserChannel.superseded` flag + 8 个测试) |
| #51 | webdesktop | ✅ done | `b63772a` | fastconnect SDK 无 AbortSignal 接入(`signal?: AbortSignal` 到 ConnectOptions / PunchOptions + `combineSignals` / `sleepWithSignal` 工具 + 透传到 lookup/probe/WS/retry sleep/start_at_ms 等待 + 9 个测试) |
| #23 | fastconnect | ✅ done | `1b58db1` | qc_id 大小写不一致 host 头 IGNORECASE vs path 严格小写(新 `normalize_qc_id` 工具 + 4 个 path 路由(directory/punch/share_link/acme)归一化 + 16 个测试) |
| #38 | truenas_connect_utils | ✅ done | `0493ccb` | `trust_env=True` JWT 经 HTTPS_PROXY 泄漏(改 `trust_env=False` + 静态扫描 + 本地 honeypot 端到端测试,5 个测试) |
| #45 | truenas_connect_utils | ✅ done | `01d85f5` | Makefile `clean` 用 `find /usr ... \| xargs rm -rf`(改为枚举 site/dist-packages + `case` 白名单校验 + 3 个 lint 测试) |
| #36 | middleware | ✅ done | `af4034a683` | `renew_cert` 写回 cert 但丢 private_key/CSR → fallback 路径 nginx key mismatch(写回 3 元组 + AST 静态断言 4 个测试) |
| #41 | truenas_connect_utils | ✅ done | `2f330bb` | `request.call` 无 retry/backoff,网络抖动整链失败(idempotent method 指数 backoff + POST/PATCH 单次保护 + 8 个测试) |
| #42 | truenas_connect_utils | ✅ done | `2f330bb` | `req.json()` 解析异常直接 raise(ContentTypeError/JSONDecodeError/ValueError 统一映射到 `response['error']` + 5 个测试) |
| #43 | truenas_connect_utils | ✅ done | `7fa7cf8` | `create_cert` 静默丢 `hostname_details`(非空时 `logger.warning` + 2 个 AST 静态测试) |
| #37 | truenas_connect_utils | ✅ done | `2e513b7` (P0-8) | `renewalInfo` KeyError 无 fallback —— 实际已在 P0-8 一并修(`directory.get('renewalInfo')`) |
| #30 | middleware | ✅ done | `e025da0` (P0-10) | `initiate_cert_generation` 无 job lock —— 实际已在 P0-10 一并修(`@job(lock='tn_connect_cert_generation')` + 入口状态机检查) |
| #39 | truenas_connect_utils | ✅ done | `8d76ec2` | `wait_for_records_to_propagate` 死 sleep 20s(改 dnspython poll TXT,授权 DNS / 60s cap / 2s 间隔 / 命中即返回 + 死 sleep 兜底 + 6 个测试) |
| #40 | truenas_connect_utils | ✅ done | `8d76ec2` | `perform/cleanup` blocking 但无 async-misuse 警告(入口 `asyncio.get_running_loop` 探测 + `logger.warning` + 5 个测试) |
| #31 | middleware | ✅ done | `17e6cffd3c` | `state.py` 用 `get_service(...).method()` 绕过 RPC(@job lock 失效是 P0-10 根因) → 改 `middleware.call('tn_connect.*')`,P0-10 入口检查变双保险 |
| #34 | middleware | ✅ done | `17e6cffd3c` | heartbeat:disk_mapping 循环外算一次(改循环内每轮刷新)+ 401 用快照 cert id(改重读 config + None-guard 才 delete_cert) |
| #35 | truenas_connect_utils | ✅ done | `ea0fcd3` | `normalize_acme_config` 不校验 `status=='valid'`(RFC 8555 §7.1.2)→ 加显式拒绝,revoke/deactivated 早 short-circuit |
| #26 | middleware | ✅ done | `30ab09b110` | `delete_cert` 不校验 cert 归属 TNC(加 `certificate.query` + `name.startswith(TNC_CERT_PREFIX)` 校验,不匹配 warn+return) |
| #32 | middleware | ✅ done | `30ab09b110` | `tnc_disabled` 路径 `ui_restart → delete_cert` 顺序错(改 `delete_cert → ui_restart`);`certificate.delete` 失败 logger.error 含 cert id + 手动清理命令 |
| #33 | middleware | ✅ done | `30ab09b110` | `hop_by_hop` 缺 `proxy-connection`(RFC 7230 §A.1.2)→ 加入 set;review 描述里"缺 transfer-encoding"是误指,set 里已有 |
| #27 | middleware | ✅ done | `b0ab29b93d` | `close()` 不能取消 connect_task(close 实际延迟数分钟)→ `__init__` 存 connect_task,close cancel + await |
| #28 | middleware | ✅ done | `b0ab29b93d` | 重连后 `_pending_punches` listener / outbound_task 累积泄漏→ 新 `_cleanup_pending_punches` 在 connect 重连入口 + close 出口清理 |
| #29 | middleware | ✅ done | `b0ab29b93d` | `_open_listener` 端口解析无断言(实测 asyncio 已 bind,review 描述"port=0 永远拿不到"是误诊;加固:显式 raise RuntimeError 让上层 PUNCH_RESULT false) |
| #46 | webdesktop | ✅ done | `364e6aa` | `flushPendingCalls` fire-and-forget,重发与 caller promise 脱钩(`pendingCalls` type 加 `reject` 字段 + 注释明确 best-effort 语义 + 9 个 AST 测试) |
| #47 | webdesktop | ✅ done | `364e6aa` | token 登出(hadToken → null)无 reset → reconnect timer / stale subscriptions 累积(加 `hadToken && !hasToken` 分支 + 新 `SubscriptionRegistry.reset()` 清 pending + entry backendId) |
| #52 | webdesktop | ✅ done | `364e6aa` | `resubscribeAll` 提前 clear + 无 try/catch,一个 sendSubscribe 失败阻断整组(改:不再 force-clear,每个 sendSubscribe 包 try/catch,失败 wsWarn 继续) |
| #48 | webdesktop | ✅ done | `98ce166` | `probeLan` HEAD 任意 localStorage URL(SSRF 风险)→ 新 `isLanHost` helper 校验 RFC 1918 / .local / loopback / ULA,公网 host 直接 return `{ok: false}` 不 fetch |
| #49 | webdesktop | ✅ done | `98ce166` | `PUNCH_RESULT false` send 后立即 ws.close,Edge 可能没收到协调锁释放 → `await new Promise(setTimeout, 50)` 缓冲 flush + close |
| #56 | webdesktop | ✅ done | `98ce166` | heartbeat 触发的 ws.close 不带 code(caller 区分不开 transport vs 业务错误)→ close code 4010 + `heartbeatClosing` flag,cleanup 用 `Transport closed: heartbeat timeout` reject |
| #55 | webdesktop | ✅ done | `9d77403` (P0-15) | `HTTP /v1/punch` 用 Authorization vs WS `/ws/punch/` 用 `?token=` 不一致 → 实际由 P0-15 修复,WS punch 已走 subprotocol `bearer:<token>`,URL 不再含 token |
| #50 | webdesktop | ✅ done | `587ce6a` | `connect()` 重试无 `maxTotalMs` 上限,baseRetryDelayMs=500 + maxRetries=10 累积 ~17 分钟 → 新 `ConnectOptions.maxTotalMs`(默认 30000),retry loop cap delay 到剩余预算,remaining ≤ 0 立即 break |

P1 还剩 0 项。**P1 段 41/41 全部清账 ✅**

---

## P2 修复进度

> **当前进度:P2 已修 6/30,剩余 24 项。** 详细 commit 见下方表格。

| P2 # | 仓库 | 状态 | Commit | 摘要 |
|---|---|---|---|---|
| #73 | truenas_connect_utils | ✅ done | `9c06e42` | `acme_config` 重复校验 `resp['response'].get('acme_details') is dict` — normalize_acme_config 内已检查,删外层(2 个 AST 测试) |
| #74 | truenas_connect_utils | ✅ done | `9c06e42` | 8 个 getter 都直接 `urllib.parse.urljoin` — 提 `_join(base, path)` helper,8 处调用统一(5 个运行时 parametrize + 2 个 AST 测试) |
| #76 | truenas_connect_utils | ✅ done | `9c06e42` | `send_event` 静默吞 callback 异常(全 logger.debug)→ 首次 warning + exc_info,后续 debug 抑制噪音(3 个运行时测试) |
| #65 | middleware | ✅ done | `abaa97097f` | `TNCTunnelConnection.proxy_request(method, path, headers, body, client_ip)` 5-arg 死代码 → 删除(RPC 走 service `proxy_request(payload)`) |
| #66 | middleware | ✅ done | `abaa97097f` | `_next_request_id` 标 `async def` 但只 `+=1` → 改 sync,caller 去掉 await |
| #69 | middleware | ✅ done | `abaa97097f` | `urlparse(tunnel_url).scheme` 三元 else 透传 typo scheme → if/elif/else,else raise ValueError 含 'scheme' 提示 |
| #58 | fastconnect | ✅ done | `804cf66` | `_fqdn_candidate` 信任用户输入 FQDN,不做 LAN/loopback 校验 → socket.getaddrinfo + ip.is_private 等检查,命中返 priority=9999 |
| #59 | fastconnect | ✅ done | `804cf66` | `hostnames_ask` 无 rate limit → per-IP 30/min + global 100/sec sliding window,触发 429 + Retry-After: 60 |
| #61 | fastconnect | ✅ done | `804cf66` | `proxy_request` body 无 max-size → `_MAX_PROXY_BODY_BYTES=64MB` + Content-Length 头预检 + 实际读到 body 二次校验,超限 413 |

P2 还剩 21 项。

---

## 跨仓库关键交叉问题（同一个根因，影响多端）

| # | 现象 | 三端耦合点 |
|---|------|-----------|
| 1 | **`renewalInfo` 缺失导致 cert 续期死循环** | fastconnect 不返回该字段 → middleware `acme.py:115-120` KeyError 被吞 → `truenas_connect_utils/acme.py:120` 不 fallback → 整条 cert 续期链路挂掉。修一处必须三处都改。 |
| 2 | **`qc_id` 校验规则不一致** | fastconnect `host_resolver.py:49` `re.IGNORECASE` / `qc_id.py:41` 严格大小写 / `truenas_connect_utils/short_id.py:14` 30 字符（注释错写 31）/ `webdesktop/fastconnect.ts:121` `/^qc-[a-z2-7]{12}$/`。建议在 devdocs 里拍板一份 spec。 |
| 3 | **JWT 传输路径不收敛** | fastconnect 签 `tunnel_jwt`、middleware 把它放进 URL query、webdesktop 把它放进 URL query + localStorage。端到端安全模型需要梳理。 |
| 4 | **Caddyfile 路由与 FastAPI 路由不一致** | `/ws/punch/*` 在 Caddyfile 完全没出现，浏览器 punch WS 永远不会到达 fastconnect server。 |
| 5 | **错误响应外壳不统一** | fastconnect `make_tnc_response` 5 份实现（3 种 shape）；middleware `request.py` 期望 `{'error': None, 'response': ..., 'status_code': ..., 'headers': ...}` 形态。改一边格式另一边解析就静默失败。 |

---

## P0 — 必须修，影响生产

### fastconnect

| # | 位置 | 问题 |
|---|------|------|
| 1 | `app/api/register.py:99-117, 128-153` | **`/v1/systems/finalize` 无认证自动在 account 1 下创建 System + 重新签发 JWT**。任何能猜到 `system_id` 或拿到 `claim_token` 的远程攻击者，都能在管理员账号下注册任意 NAS。**最严重鉴权绕过。** |
| 2 | `app/api/acme.py:124-176` | **`/v1/acme/cert/{hostname:path}` 路径穿越**。`..` 子串检查可绕过（`os.path.join` 仍解析 `..../` 等），任意已认证用户能 `stat` 服务器上任意文件，且响应回显绝对路径。 |
| 3 | `app/core/host_resolver.py:107-128` | **`_lookup_system_id` 把 `None` 永久缓存**。`@lru_cache` 没有 TTL，qc_id 暂时不存在就被永久否定缓存，导致 `/v1/lookup` / `/v1/hostnames/ask` 永久 404 直到进程重启。 |
| 4 | `app/auth/jwt.py:38-54` | **`previous_secret_key` 永不过期**。注释说"24h 后清空"，但没有 TTL 强制，老密钥泄露 = 永久漏洞。 |
| 5 | `app/api/share_link.py:304-306` | **`current_access += 1` 非原子**。两个并发请求都可读到 `9` 写入 `10`，绕过 `max_access=10` 限制（实际允许 11 次）。 |

### middleware (`plugins/truenas_connect/`)

| # | 位置 | 问题 |
|---|------|------|
| 6 | `tunnel.py:122-126` | **JWT 在 URL query 里**。任何反向代理 / 浏览器 DevTools / Sentry 都会拿到 `?token=...`。`websockets.connect` 在 server 端永远可以发 header，**没有理由保留 query 兜底**。 |
| 7 | `tunnel.py:787-799` | **SSRF 防护只做字符串检查**。不阻止 `\t` / `\x00` / `\\\\evil.com` 等变体，且不验证 HTTP `method` 白名单，攻击者可注入 `CONNECT` / `TRACE`。 |
| 8 | `acme.py:115-120` + 联动 `truenas_connect_utils/acme.py:120` | **`renewal_info` 缺失时进入死循环**。`directory['renewalInfo']` 是 ACME 可选字段，离线 Edge 不返回该字段时，`KeyError` 被吞，`check_renewal_needed` 一直返回 `(True, None)`，每秒触发 revoke。 |

### truenas_connect_utils

| # | 位置 | 问题 |
|---|------|------|
| 9 | `acme.py:55` | **`resp['acme_details'] = resp.pop('response')` 把外层响应覆盖到了内层 key**。后续 `normalize_acme_config` 读到的是包装后的 dict，`acme_details.get('account')` 永远 `None`，**cert 请求路径在生产中 100% 失败**。 |
| 10 | `hostname.py:12-17` | **`get_base_domain_from_hostnames` 对新 qc_id 架构永远返回 None**。`qc-{12char}.fastconnect.host` 只有 3 段，但函数要求 5 段（"wildcard" 形式）。新架构下 `base_domain` 永远是 None。 |
| 11 | `request.py:37` | **`asyncio.timeout` 是 Python 3.11+ API**。TrueNAS Scale Bullseye 装的是 Python 3.9，**`.deb` 安装会失败**。改用 `asyncio.wait_for` 或要求 `python3.11`。 |
| 12 | `debian/control:19-22` | **运行时依赖缺 `python3-aiohttp` / `python3-cryptography` / `python3-josepy`**。最小化 chroot 下 `ImportError`。 |

### webdesktop

| # | 位置 | 问题 |
|---|------|------|
| 13 | `src/shared/sdk/fastconnect.ts:522-548` | **`waitForPunchMessage` 非期望消息静默忽略**。如果先收到 `PUNCH_ERROR`，hang 直到超时；timer 和 promise 不被清理。 |
| 14 | `src/shared/stores/auth.ts:7, 54` | **JWT 存 `localStorage`**。任何 XSS 都能 `localStorage.getItem('phs:token')` 窃取 portal 访问令牌；本项目使用了 `react-markdown` / `marked`，用户 qc_id 流入 telemetry。 |
| 15 | `src/shared/sdk/fastconnect.ts:556-588` + `src/truenas/api/websocket-client.ts:415-421` | **Token 在 URL query**。FastConnect 访问日志 / 浏览器历史 / `Referer` 都会拿到。**`Sec-WebSocket-Protocol` subprotocol 是标准做法**（`new WebSocket(url, ['bearer', token])`），不要用 query。 |

---

## P1 — 应尽快修

### fastconnect

| # | 位置 | 问题 |
|---|------|------|
| 16 | `app/api/sso.py:67-79` | `_SSO_PENDING` 没并发锁，重复 `state` 静默覆盖；只在 login 清理，从不回调时清。 |
| 17 | `app/core/punch_coordinator.py:114-200, 231-236` | `initiate` 非原子（`has_active` 与写入之间可被中断）；`attach_browser` 覆盖旧浏览器不通知。 |
| 18 | `app/core/message.py:71-79` + `app/api/tunnel.py:185` | `MessageType(unpacked['type'])` 抛 `ValueError` 直接断连，应跳过单条坏消息继续读。 |
| 19 | `app/core/connection_pool.py:147-164` | `get` 在无锁下 mutate state，与 `broadcast_ping` 读 `last_ping` 存在竞态。 |
| 20 | `app/core/connection_pool.py:171-243` | `pending_requests` 在 `wait_for` 被 cancel 时不 pop，内存泄漏。 |
| 21 | `app/main.py:48-57` | `cleanup_old_events` 同步删除可阻塞 lifespan 数秒 → 启动 DoS。 |
| 22 | `Caddyfile.example:63` | 示例文件还保留全局 `encode gzip` → 6 秒 WS 断连 bug。 |
| 23 | `app/core/qc_id.py:41-45` 与 `app/core/host_resolver.py:49-59` | `extract_qc_id_from_host` 大小写不敏感、`validate_qc_id` 大小写敏感，混用导致 404。 |

### middleware

| # | 位置 | 问题 |
|---|------|------|
| 24 | `tunnel.py:301` | 内部异常 `str(e)` 直接作为 500 body 返回到浏览器，泄漏堆栈 / DB 连接串。 |
| 25 | `utils.py:25` | `decode_and_validate_token` 验签 `verify_signature=False`，且不与本地 `system.global.id` 交叉校验 → 受陷 finalize 端点可注入伪造 token。 |
| 26 | `update.py:255-263` | `delete_cert` 不校验 cert 是否归属 TNC，FK 误指会误删任意证书。 |
| 27 | `tunnel.py:880-929, 840-855` | `start()` 不持有 `connect_task`，`close()` 不能取消 1-300s `asyncio.sleep` → 实际关闭延迟数分钟。 |
| 28 | `tunnel.py:531-539` | `_pending_punches` 重连后不清理 → 监听器 / SYN 任务累积。 |
| 29 | `tunnel.py:680-690` | `_open_listener` 立刻读 `server.sockets` 永远是 `None`，`port=0` → 浏览器端 `PUNCH_READY` 永远连不上。 |
| 30 | `acme.py:103` + `update.py:294-298` | `initiate_cert_generation` 无 job lock，并发触发会插入多条 cert 行并双重 `ui_restart`。 |
| 31 | `state.py:30-57` | 用 `get_service` 而非 `middleware.call`，绕过 RPC 层的 job 跟踪和未来可能加入的 auth 中间件。 |
| 32 | `update.py:155-156` | `tnc_disabled` 路径先 `ui_restart` 后 `delete_cert`，nginx 仍持有已删 cert 的窗口；`certificate.delete` 失败也不回滚。 |
| 33 | `tunnel.py:1149-1154` | `hop_by_hop` 没去掉 `proxy-connection` 和 `Transfer-Encoding: chunked`（按 RFC 7230）。 |
| 34 | `heartbeat.py:46, 99-100` | `disk_mapping` 循环外捕获，热插拔会传陈旧数据；401 后删除 cert 不重新校验所有权。 |
| 35 | `acme.py:60-72` | placeholder key 检测在 load private key 之后；`status` 字段不验证 `=='valid'` → key confusion 攻击。 |

### truenas_connect_utils

| # | 位置 | 问题 |
|---|------|------|
| 36 | `acme.py:150-156` | `create_cert` 续期时重生成 RSA key + CSR，若中间件没把新 private_key 写回 DB，TLS 必坏。 |
| 37 | `acme.py:103-120` | `directory['renewalInfo']` KeyError 无 fallback，与 middleware 8 同源。 |
| 38 | `request.py:38` | `trust_env=True` → 任何 `HTTPS_PROXY` env 都代理出 TNC 流量（含 JWT）。 |
| 39 | `tnc_authenticator.py:30-31` | 固定 `time.sleep(20)` 不校验记录实际是否传播，ACME server 更严的超时会失败；应 poll LECA。 |
| 40 | `tnc_authenticator.py:51, 69` | 阻塞 `requests` 在公开 `perform()` 方法里被直接调用会阻塞 loop；只在外层用 `to_thread` 时才安全。 |
| 41 | `request.py:36-58` | 无 retry / 无 backoff，单次网络抖动永久失败；`aiohttp.ClientSession` 每调用创建，握手浪费。 |
| 42 | `request.py:57` | `req.json()` 解析异常未映射为 `error`，外层拿到 raw `JSONDecodeError`。 |
| 43 | `acme.py:140-150` | `hostname_details` 静默忽略，是 footgun，迁移回多 hostname 会拿错 SAN。 |
| 44 | `setup.py:1` | `distutils` Python 3.10+ deprecated、3.12 移除；且无 `install_requires`，`pip install .` 出来的包是坏的。 |
| 45 | `Makefile:15-17` | `clean` 用 `find /usr ...` 不检查 root / 限定包路径，会误删任何匹配目录。 |

### webdesktop

| # | 位置 | 问题 |
|---|------|------|
| 46 | `src/truenas/api/websocket-client.ts:770-779` | `flushPendingCalls` 重新发送的请求没有 rebind resolver → 重发失败的 RPC 调用方完全无感知。 |
| 47 | `src/truenas/api/websocket-client.ts:313-332` | token 变更订阅器只在 `!had && has` 触发，登出后仍在重连时拿 stale token；无 logout 重置。 |
| 48 | `src/shared/sdk/fastconnect.ts:265-299` | `probeLan` HEAD 任意 localStorage URL（XSS/污染后可被 SSRF），需校验 host 形态（RFC 1918 / `*.local` / 白名单）。 |
| 49 | `src/shared/sdk/fastconnect.ts:487-495` | `PUNCH_RESULT false` send 后立即 `ws.close()`，Edge 可能没收到协调锁释放。 |
| 50 | `src/shared/sdk/fastconnect.ts:643-700` | `connect()` 重试无 `maxTotalMs`，指数 backoff + 长 base delay 可锁住 UI 微任务循环。 |
| 51 | `src/shared/sdk/fastconnect.ts:39-66` | 无 `AbortSignal` 接入 → UI 取消按钮无法中断进行中的 lookup/probe/punch。 |
| 52 | `src/truenas/api/websocket-client.ts:217-233` | `pendingSubscriptions.clear()` 早于 resubscribe，老 WS 的 `onSubscribed` 迟到 → 后端订阅泄漏。 |
| 53 | `src/environments/environment.ts:62-69` | 模块导入时无条件 `console.log`，生产也跑，泄漏 host / build 信息。 |
| 54 | `src/shared/sdk/fastconnect.ts:301-325` | 并行 probe 与 LAN 串行 fetch，无 early-exit，高优先级成功时仍在后台跑 LAN HEAD。 |
| 55 | `src/shared/sdk/fastconnect.ts:412` / `websocket-client.ts:415-421` | HTTP `/v1/punch` 用 `Authorization` 头，WS `/ws/punch/` 用 `?token=`，不一致。统一用 subprotocol。 |
| 56 | `src/truenas/api/websocket-client.ts:689-710` | heartbeat 触发的 `ws.close()` 中断所有在飞 RPC，job 轮询区分不开传输关闭 vs 业务错误。 |

---

## P2 — 重要但不阻塞

### fastconnect

| # | 位置 | 问题 |
|---|------|------|
| 57 | `app/api/share_link.py:323-350` | `/v1/share-links/{token}/auth` 永返回 200 但没真正建 cookie/session，是个无效接口。 |
| 58 | `app/core/candidate_builder.py:161-175` | `_fqdn_candidate` 信任 DB 存的 FQDN，未做 RFC 1918 / loopback / link-local 拒绝。 |
| 59 | `app/api/hostnames_ask.py:50-60` | 匿名可触发 Let's Encrypt 签发，可被滥用打满 LE 速率配额。 |
| 60 | `app/core/config.py:34` + `app/auth/jwt.py:81` | `tunnel_jwt_algorithm` 配置可错配 HS256 秘钥当 RS256，错误信息晦涩。 |
| 61 | `app/api/proxy.py:95` | `request.body()` 无 max-size，恶意客户端 OOM。 |
| 62 | `app/api/proxy.py:89-94` | `Host` header 转发但 `X-Forwarded-Host` 不剥，与 `host_resolver` 校验的 host 不一致。 |
| 63 | `app/core/punch_coordinator.py:208-228` | `on_device_result` 成功后不推进 state，等不到 browser 报告就永久 `COORDINATED`，泄漏。 |
| 64 | `app/core/host_resolver.py:49-59` | `extract_qc_id_from_host` 不处理前导 `.` / 末尾 `.`。 |

### middleware

| # | 位置 | 问题 |
|---|------|------|
| 65 | `tunnel.py:937-971` vs `tunnel.py:787` | 死代码：第一个 `proxy_request(method, path, ...)` 永远不会被调用，命名混淆。 |
| 66 | `tunnel.py:835-838` | `_next_request_id` 是 async 但只做 `+=1`。 |
| 67 | `mixin.py` | `TNCAPIMixin` 是 1 行 `_call` 透传 + auth_headers 函数，可降为 `utils.py` 模块函数。 |
| 68 | `utils.py:103-120` | `calculate_sleep` 注释与实现不一致（"next attempt after previous" 错）；`group` 无上限。 |
| 69 | `tunnel.py:914-915` | `parsed.scheme == 'httpx'` 等 typo 不会报错，直接传给 `websockets.connect`。 |
| 70 | `register.py:93, 100-102` | `removeprefix('TRUENAS-')` 对 `None` 抛 `AttributeError`；`raw_license` 放 URL query。 |
| 71 | `register.py:62-67` | `call_later(30, ...)` finalize 延迟硬编码 30s。 |
| 72 | `update.py:181` | `update_environment` 无 audit log（虽然 `do_update` 有）。 |

### truenas_connect_utils

| # | 位置 | 问题 |
|---|------|------|
| 73 | `acme.py:41-58` 与 `acme.py:64-106` | `acme_config` 与 `normalize_acme_config` 重复校验，删一边。 |
| 74 | `urls.py:18-60` | 8 个函数都做同样的 urljoin，提一个 `_join(base, path)` helper。 |
| 75 | `event.py:12-35` | `EventCallback.CALLBACKS` 类级别可变 list，多实例会互相污染。 |
| 76 | `event.py:38-43` | `send_event` 静默吞所有异常，应 warning（首错）+ debug（重复）。 |
| 77 | `setup.cfg` | 无 `[tool:pytest]` / `[mypy]` / `[isort]`。 |
| 78 | `LICENSE` + `setup.py:15` | `license='GNU3'` 不是合法 SPDX（应 `GPL-3.0-or-later`）。 |

### webdesktop

| # | 位置 | 问题 |
|---|------|------|
| 79 | `src/shared/sdk/fastconnect.ts:94, 802` | `ConnectError.candidatesTried` 实际是全部候选而非"试过"，命名误导。 |
| 80 | `src/truenas/api/websocket-client.ts:34-48, 538-578` | `IncomingMessage` 类型允许 `method+params` 与 `id+result` 同存，运行时分支混乱。 |
| 81 | `src/environments/environment.ts:55` | `build: 'development'` 硬编码，生产构建也显示 development。 |
| 82 | `src/shared/sdk/fastconnect.ts:625, 663, 687, 728, 737, 750, 785` | 同一 `await import('./telemetry')` 7 次，可静态 import。 |
| 83 | `src/shared/sdk/fastconnect.test.ts:44-54` + `telemetry.test.ts:24-34, 129-139` | `mockFetchSequence` 在 3 个测试文件复制 3 次。 |
| 84 | `src/shared/sdk/fastconnect.ts:121-124` | qc_id 正则字母表与服务端不一致风险，未链规范。 |
| 85 | `src/shared/sdk/nat.ts:41-44` | STUN servers 硬编码 Google + Cloudflare，无 `iceServers` 覆盖选项。 |
| 86 | `src/truenas/api/websocket-client.ts:124, 165, 186, 227, 232` | `SubscriptionEntry.pendingCallId` 赋值后从不读，死字段。 |

---

## P3 — 风格 / 测试覆盖 / 死代码

| # | 仓库 | 问题 |
|---|------|------|
| 87 | fastconnect | `make_tnc_response` 5 个文件 5 份实现（3 种 shape），`app/core/response.py:19-65` 的 `TNCResponse` 没人用。 |
| 88 | fastconnect | `get_account_from_token` 在 `hostname.py` / `acme.py` / `heartbeat.py` 重复 3 次。 |
| 89 | fastconnect | `_client_ip` 在 `rate_limit.py` 和 `analytics.py` 各一份。 |
| 90 | fastconnect | `punch_coordinator.py:70-72` `PeerAddr.from_dict` / `message.py:81-166` 大半 `create_*` 类方法死代码。 |
| 91 | fastconnect | `PunchState.PUNCH_SENT` 是没人用的中间状态。 |
| 92 | fastconnect | SQLAlchemy v1 `declarative_base` import（`database.py:4`）。 |
| 93 | fastconnect | `python-jose`（已停维护）与 `joserfc` 混用，应统一。 |
| 94 | fastconnect | 测试空白：`PUNCH_READY` 端到端、`register.py:99-117` 危险分支、`_allocate_qc_id` 冲突、`previous_secret_key` 轮换、`ws/punch/*` 路由 Caddyfile 转发（**目前 Caddyfile 没有 `/ws/punch/*`**，punch WS 永远到不了 FC）。 |
| 95 | middleware | `tunnel.py:14-32` 死 import（`ssl`, `dataclass`）。 |
| 96 | middleware | `tunnel.py:34` 用模块级 `logger` 而非 `self.logger`。 |
| 97 | middleware | `state.py:73-74` 注释中文、其他文件英文。 |
| 98 | middleware | `private_models.py` 缺字段 `description=`，`test_api_docstrings` 会失败。 |
| 99 | middleware | 测试空白：`tunnel.py:463-639` PUNCH 协议、`finalize_registration` 边缘情况、`heartbeat` 401 级联、`LocalProxyService._resolve_route`、`acme.renew_cert` ARI 窗口。 |
| 100 | truenas_connect_utils | 整个仓库无 `tests/` 目录。需至少 `test_request.py`、`test_urls.py`、`test_short_id.py`、`test_acme.py`、`test_hostname.py`、`test_upnp_probe.py`。 |
| 101 | truenas_connect_utils | `acme.py:3` `import sys` 未使用。 |
| 102 | webdesktop | 测试空白：`connectPunch` happy path、`waitForPunchMessage` 非匹配消息、`mdns.ts` SSR/无 window、token 过期重连、STUN 分类、`environment.ts` regex。 |
| 103 | webdesktop | `CONNECT_ERROR_MESSAGES` 在 SDK 里属 i18n 串，违反分层。 |
| 104 | webdesktop | `fastconnect.ts` 中混用 `;` 与无 `;`，prettier 没跑。 |

---

## 修复顺序建议（按风险收益比）

**第 1 周 — P0 鉴权 / 路径穿越 / cert 100% 失败**：

1. fastconnect #1 #2 #3 #4 #5（注册鉴权绕过、ACME 路径穿越、永久负缓存、密钥轮换、share_link 竞态）。
2. middleware #6 #7 #8（隧道 JWT 泄漏、SSRF、`renewalInfo` 死循环）。
3. truenas_connect_utils #9 #10 #11 #12（cert 100% 失败、Python 3.9 兼容、缺 aiohttp/cryptography）。

**第 2 周 — P0 安全模型 + 跨仓库一致**：

4. webdesktop #13 #14 #15（waitForPunchMessage 死锁、JWT localStorage、token 在 URL）。
5. ACME `renewalInfo` 跨仓库统一处理（fastconnect 不依赖它或 middleware/utils 显式兜底）。
6. Caddyfile `/ws/punch/*` 路由 + JWT subprotocol 端到端梳理。

**第 3 周 — P1 状态机 / 重连**：

7. fastconnect P1 状态机与连接池竞态。
8. middleware P1 状态机（PUNCH / heartbeat / state.py / cert attachment）。
9. webdesktop P1 重连 / 取消 / 并行 probe。

**之后**：

10. 死代码 / 重构（5.x / 6.x / 7.x）。
11. 补测试（每仓库补齐覆盖率，尤其是 PUNCH 协议、JWT 轮换、cert 续期、qc_id 提取）。

---

## 修复脚本建议

- 单条 P0 修复建议统一采用这样的格式写到后续 commit message：

  ```
  fix(<repo>): <one-line summary>

  P0 - <#>: <file:line>

  <explanation 1-2 sentences>

  <verification / test note>
  ```

- 涉及跨仓库的（如 `renewalInfo`、qc_id spec），先在 `devdocs/fastconnect/` 新建对应 spec，再三方分别引用。

---

**注**：本文件是临时汇总，未提交 OpenNas 根仓库。如需后续归档：
- 选择 1：直接 commit 到 OpenNas 根仓库 `tmp/code-review-2026-06-19.md`，配 `chore: 临时归档 2026-06-19 跨仓库 code review`。
- 选择 2：作为下一次 dev session 的输入，等修复完相关条目后再删除。