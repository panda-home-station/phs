# Pipa 部署指南 (本 NAS: TrueNAS SCALE 26.04 dev box)

当前环境探测结果(未装前):

```
TrueNAS SCALE 26.04.0-MASTER (生产构建)
node 20.19.2 + npm 9.0.0                  ✓
python 3.11.2 + dpkg-buildpackage          ✓
cargo / rustc                              ✗ (需 rustup)
middlewared.service 已 active,running       ✓
/usr/sbin/panda-app-server                 ✗ (没装)
/etc/systemd/system/pipa.service           ✗ (没装,见注)
/usr/lib/tmpfiles.d/pipa.conf              ✗ (没装)
/data/freenas-v1.db (sysdb)                ✓
```

> 注:`pipa.service` 由 **pandacode** 的 deb(`panda-app-server`)通过
> `dh_installsystemd` 自动安装到 `/lib/systemd/system/`,并在 middleware
> deb 的 postinst 里 `systemctl enable --now pipa.service`(仅当
> `panda-app-server` 已装时)。`/run/pipa/` 由单元里的 `RuntimeDirectory=pipa`
> 在 start 时自动创建,所以不再需要手工 `cp` 或 `systemd-tmpfiles --create`。
>
> 如果只想装 middleware 不装 pandacode(罕见),pipa 单元不会被触发;
> middleware 本身不依赖它。

---

## 整体流程 (4 步,顺序敏感)

```
0. 装 rustup  (本机 build pandacode 用)
1. ./tools/deploy-nas.sh --target middleware   # 装新 middleware deb + alembic
2. ./tools/deploy-nas.sh --target pandacode    # 装 binary + start_service
3. ./tools/deploy-nas.sh --target webdesktop   # 装 SPA(浏览器硬刷)
4. bash tools/check-pipa-status.sh              # 总验收
```

---

## Step 0: 装 rustup (若 cargo 不在)

```bash
which cargo
# 没输出 → 跑:

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
source $HOME/.cargo/env
rustc --version
# 期望: rustc 1.7x.x
```

如果不想在本 NAS 装 rust,可在 dev 机器上 build:

```bash
# dev 机器:
cd /home/truenas_admin/work/OpenNAS/pandacode
make build_deb
find . -name "*.deb" -not -path "*/target/*"
# 找到 build-pc-deb/ 下的 .deb,scp 到 NAS:
scp build-pc-deb/panda-app-server_*_amd64.deb nas:/tmp/

# NAS 上:跳过 Step 2 里的 cargo build,直接 dpkg -i:
sudo dpkg -i /tmp/panda-app-server_*_amd64.deb
```

---

## Step 1: deploy middleware (deb + alembic)

```bash
cd /home/truenas_admin/work/OpenNAS
sudo ./tools/deploy-nas.sh --target middleware --dry-run
# 看会做什么 (stop_service → clean → build_deb → install → migrate → start_service)

sudo ./tools/deploy-nas.sh --target middleware
# 内部跑 middleware/src/middlewared/Makefile 的 reinstall,
# 包括 dpkg -i + alembic upgrade head,自动建 pipa_user_prefs 表
```

**期望输出**:
- 最后几行: `❷ middleware 部署完成` / `==> ✅ 部署成功`
- `systemctl status middlewared` 仍 active
- `sqlite3 /data/freenas-v1.db ".tables" | grep pipa_user_prefs` 有输出
- 如果 `panda-app-server` 已装,middleware 的 postinst 会顺便 enable+start
  `pipa.service`(否则跳过,保持原状)。可用
  `systemctl is-active pipa.service` 验证。

---

## Step 2: deploy pandacode (binary + 启 daemon)

```bash
cd /home/truenas_admin/work/OpenNAS
sudo ./tools/deploy-nas.sh --target pandacode --dry-run
# 看会做什么 (stop_service → clean → build → install → start_service)

sudo ./tools/deploy-nas.sh --target pandacode
# stop_service = systemctl stop pipa.service (此时 stop 没害处,反正没运行)
# install = dpkg -i deb,其 postinst 会 daemon-reload + restart pipa.service
# start_service = 保险起见再 start 一次
```

**期望输出**:
- `ls -la /usr/sbin/panda-app-server` 存在且 mode 0755
- `systemctl status pipa` 显示 `active (running)`
- `ls -l /run/pipa/pipa.sock` 存在,前缀 `srw-r-----`
- `midclt call pipa.status` 返回 `daemon_reachable: true`

---

## Step 4: deploy webdesktop (SPA)

```bash
cd /home/truenas_admin/work/OpenNAS
sudo ./tools/deploy-nas.sh --target webdesktop --dry-run

sudo ./tools/deploy-nas.sh --target webdesktop
# webdesktop 没有 daemon,所以 reinstall 只 build + install (到 webserver serving dir)
# deploy-nas.sh 提示: 浏览器需 Ctrl+Shift+R 硬刷
```

**期望输出**:
- 装到 `/usr/share/opennas/webdesktop/` 或 `/usr/share/truenas/webdesktop/`(看 deb)
- `systemctl reload nginx`(若用 nginx)

---

## Step 5: 总验收

```bash
bash /home/truenas_admin/work/OpenNAS/tools/check-pipa-status.sh
```

**期望输出**:全部 8 项 ✓,总结 `All green.`

跑单元测试:

```bash
cd /home/truenas_admin/work/OpenNAS/middleware
python3 tests/run_unit_tests.py
# 重点:
# - test_pipa.py (4 个 EncryptedText 测试)
# - test_truenas_connect_path_mapping.py (13 个 path mapping 测试)
```

---

## 端到端人工验收

| 步骤 | 操作 | 期望 |
|------|------|------|
| 1 | 浏览器开 `https://<nas>/`,登录 webdesktop | SPA 加载,可见 apps 列表 |
| 2 | 按 `Cmd/Ctrl+K` | 弹窗 "和 Pipa 聊聊..." 浮现,右上角 `● 就绪` 绿点 |
| 3 | 输入 "hello" + Enter | apps/pipa 窗口打开,流式回复 |
| 4 | DevTools → Network → WS | URL = `wss://<nas>/_plugins/pipa/ws`,Status 101,Messages 看到 NDJSON 帧 |
| 5 | apps/pipa → Settings → 填 openai key → 保存 | 绿色 "已保存" toast |
| 6 | `sqlite3 /data/freenas-v1.db "SELECT substr(api_key_encrypted,1,30) FROM pipa_user_prefs"` | 不是明文 `sk-...` |
| 7 | `journalctl -u middlewared --since "5 min ago" \| grep audit \| grep pipa` | 看到 audit 行,无 `sk-` 明文 |

---

## 回滚

```bash
# 1. 停 pipa daemon
sudo systemctl disable --now pipa.service
sudo rm /etc/systemd/system/pipa.service /usr/lib/tmpfiles.d/pipa.conf
sudo systemctl daemon-reload

# 2. 卸 pandacode deb
sudo dpkg -r panda-app-server

# 3. middleware 重装回滚(从 git checkout 干净版)
cd /home/truenas_admin/work/OpenNAS/middleware
git checkout -- src/middlewared/middlewared/plugins/pipa.py
sudo ./tools/deploy-nas.sh --target middleware

# 4. webdesktop 旧版本
cd /home/truenas_admin/work/OpenNAS/webdesktop
git checkout -- apps/pipa/ src/desktop/components/QuickPipaDialog.tsx
sudo ./tools/deploy-nas.sh --target webdesktop
```

---

## 出问题怎么报

```
TrueNAS SCALE 版本: cat /etc/os-release | head -3
失败 Step: (0 / 1 / 2 / 3 / 4)
具体命令: (你跑的那条)
期望 vs 实际: (... ...)
journal 摘录:
  sudo journalctl -u pipa -n 30 --no-pager
  sudo journalctl -u middlewared -n 30 --no-pager
  sudo journalctl -u nginx -n 30 --no-pager
check-pipa-status.sh 输出
```

完整测试用例 (含失败排查表) 见 [docs/pipa-test-runbook.md](./pipa-test-runbook.md)。
FastConnect 隧道验收见 [docs/fastconnect-pipa-tunnel.md](./fastconnect-pipa-tunnel.md)。