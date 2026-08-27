# PHS 当前部署环境速查

> 这是**机器 + 4 个可独立部署边界 + 各自命令**的单文档速查,改完代码去哪儿跑哪个 `make` / `deploy` 一目了然。架构细节看 `./CLAUDE.md` + `./middleware/CLAUDE.md` + `./webdesktop/CLAUDE.md`。

---

## 1. 两台机器

| 角色               | 接入方式                  | 跑什么                                                                 |
| ------------------ | ------------------------- | ---------------------------------------------------------------------- |
| **NAS box**        | 当前终端 (hostname: `truenas`) | TrueNAS 内核 + middlewared + nginx + webdesktop 前端 bundle             |
| **Cloud portal**   | `ssh fastconnect` (= 103.189.141.61) | `fastconnect/` 整套(FastAPI `api` + nginx `portal` + Caddy `caddy`)   |

- DNS: `fastconnect.host` A 记录指向 cloud portal;Caddy 持 `*.fastconnect.host` 通配 cert(Cloudflare DNS-01)。
- NAS 调用 `https://fastconnect.host` 是出公网,经过 NAS → 路由器 → FastConnect portal 这条路径。
- `popups`(门户绑定弹窗)由 webdesktop 用 `window.open(https://fastconnect.host/l/{id}?popup=1)` 打开。

---

## 2. 4 个可独立部署的代码边界

每个边界用 `git status` / 文件 md5 看是否需要重 build。

| 边界 | 源码目录                     | 部署到的路径                                    | 部署命令(各自子目录)                          |
| ---- | ---------------------------- | ----------------------------------------------- | ---------------------------------------------- |
| ❶ NAS Python lib    | `truenas_connect_utils/`           | NAS `/usr/lib/python3/dist-packages/truenas_connect_utils/`(deb) | `sudo make reinstall`     |
| ❷ NAS middleware    | `middleware/src/middlewared/`      | NAS `/usr/lib/python3/dist-packages/middlewared/`(deb) + restart | `sudo make reinstall`     |
| ❸ NAS web bundle   | `webdesktop/`                     | NAS `/usr/share/opennas/webdesktop/`(nginx serve) | `sudo make reinstall` |
| ❹ Cloud portal       | `fastconnect/`                    | Cloud `/opt/fastconnect/`(Docker compose up -d) | 本机: `./tools/deploy-fastconnect.sh`     |

> **❶ ❷ ❸ 都用 `sudo make reinstall`**,在 NAS box 当前终端跑(已经是 NAS)。
> **❹ 不需要 sudo**,走 `./tools/deploy-fastconnect.sh`,脚本自己 ssh + rsync + 远端 build/deb/docke compose。
> **写代码 vs 跑 deploy** 是两件不同的事。改完之后看 git status,知道改了哪个边界,只 deploy 那一个。

---

## 3. 各边界的"是不是该重 deploy"判断

`git status` 看到某边界有改动 → 跑对应边界的 `sudo make reinstall`(或 `./tools/deploy-nas.sh --target <id>`)。改之前可以先手工 md5 对比 sanity check:

```bash
md5sum /usr/lib/python3/dist-packages/middlewared/plugins/truenas_connect/register.py \
       /home/truenas_admin/work/OpenNAS/middleware/src/middlewared/middlewared/plugins/truenas_connect/register.py
# md5 一致 → NAS 不需重装;md5 不一致 → cd middleware/src/middlewared && sudo make reinstall
```

---

## 4. 部署命令速查

### ❶ truenas_connect_utils(NAS Python lib)

```bash
cd /home/truenas_admin/work/OpenNAS/truenas_connect_utils
sudo make reinstall
# 等价于: stop_service  →  clean (rm /usr/lib/python3/dist-packages/truenas_connect_utils)
#         build_deb (dpkg-buildpackage)
#         install    (dpkg -i python3-truenas-connect-utils_*.deb)
#         start_service (systemctl restart middlewared)
# 不需要重启 web shell,不需要重启 nginx。
```

退路(容器 / 无 systemd):`sudo make reinstall_container`。

### ❷ middleware(NAS 核心)

```bash
cd /home/truenas_admin/work/OpenNAS/middleware/src/middlewared
sudo make reinstall
# 等价于: stop_service (systemctl stop middlewared)
#         clean → build_deb (dpkg-buildpackage)
#         install (dpkg -i middlewared_*.deb)
#         start_service (daemon-reload + restart)
# 跑完 dashboard / webdesktop 的 API 走新版本。
```

### ❸ webdesktop(NAS 前端 bundle)

```bash
cd /home/truenas_admin/work/OpenNAS/webdesktop
sudo make reinstall
# 等价于: clean (rm dist/, debian/opennas-webdesktop/, node_modules/.vite, ../opennas-webdesktop*.deb)
#         build_deb (npm run build + dpkg-buildpackage)
#         install (dpkg -i opennas-webdesktop_*.deb)
# 跑完用户必须硬刷 Ctrl+Shift+R 才看到新 bundle(html 不强缓存)。
```

### ❹ FastConnect portal(Cloud)

```bash
cd /home/truenas_admin/work/OpenNAS
./tools/deploy-fastconnect.sh
# 脚本做: ssh 远端 → 停容器 → 备份 data → rsync 推代码 → 远端写 .env →
#         远端 build portal dist → docker compose build api + up -d →
#         等 api 起来 → 跑全套 smoke (GET /health, /v1/link/..., wildcard cert, ...)。
# 看到「==> 结果: X 通过, 0 失败, Y 跳过」+「==> 部署成功!」为 OK。
```

**Secret 自动管理**(脚本内置,**不要手动加** `SECRET_KEY=...`):

- 首次跑:`~/.fastconnect-secrets` 不存在 → 自动 `openssl rand -hex 32` 生成 `SECRET_KEY` + `TUNNEL_JWT_SECRET` 写文件 (chmod 600)
- 后续跑:`source ~/.fastconnect-secrets` 拿已存真值
- 轮换:export `NEW_SECRET_KEY` / `NEW_TUNNEL_JWT_SECRET` 触发,旧值作为 `PREVIOUS_*` 写过 24h 过渡期

```bash
# 显式 secret 轮换(老 token 24h 过渡期仍可用)
NEW_SECRET_KEY=$(openssl rand -hex 32) ./tools/deploy-fastconnect.sh
```

中途只改了 portal 代码、要快 deploy,可以直接:

```bash
ssh fastconnect 'cd /opt/fastconnect/portal && rm -rf dist && npm run build && docker compose restart portal'
```

---

## 5. 排除故障速查(常见三类)

### A. 改了 Python 库(❶ / ❷),但 NAS 还在跑老代码
- 检查 md5(见 §3)。不一致就是忘了 `sudo make reinstall`。
- `systemctl status middlewared` 看是哪个版本(进程启动时间 vs `dpkg -l middlewared`)。

### B. 改了 webdesktop TS(❸),但浏览器还看到旧 UI
- 99% 是浏览器 / Service Worker 缓存。**Ctrl+Shift+R 硬刷**。
- 看响应头 `Cache-Control`:`index.html` 是 `no-cache`(nginx 配置正确),但浏览器对 SPA 历史里访问过的 hash 文件名会自动长缓存。换 URL 路径绕过即可。

### C. 改了 portal(❹),但 cloud 上跑老代码
- 跑一遍 `./tools/deploy-fastconnect.sh`,看 smoke test 输出。
- 「`/l/nonexistent` 短链 SPA fallback 返 404」专门验证 A++ LinkApp 是否活;非 200 说明 `nginx.conf` 没刷出来(→ 容器没 restart)。

---

## 6. 这两台机器目前装了什么

| 项              | 来源                                                                        | 备注 |
| --------------- | --------------------------------------------------------------------------- | ---- |
| NAS middlewared | `/usr/lib/python3/dist-packages/middlewared/`                            | md5 与源码一致(已部署含 `init_resp['response']` / `portal_unreachable` / `absolute_popup_url`) |
| NAS truenas-connect-utils | `/usr/lib/python3/dist-packages/truenas_connect_utils/`                | md5 一致(已部署 `mode.lower()` + `absolute_popup_url`) |
| NAS webdesktop  | `/usr/share/opennas/webdesktop/`                                          | **bundle 尚未部署含 LinkApp 修复**(需要 `sudo make reinstall`,本地已 build 在 `/tmp/webdesktop-build/`) |
| Cloud portal    | `/opt/fastconnect/`                                                       | deploy OK,29/30 smoke pass(`/l/<uuid>` → link.html 200,title `FastConnect — 设备绑定`) |

---

## 7. 持续维护节奏

- 改完代码 → `git diff` 看落在哪 4 个边界 → 对应边界跑部署命令
- 部署后立刻进 NAS dashboard 或 portal 测试对应功能
- 出问题查中间状态(md5、`docker ps`、`systemctl status middlewared`、nginx 错误日志 `/var/log/nginx/error.log`)
