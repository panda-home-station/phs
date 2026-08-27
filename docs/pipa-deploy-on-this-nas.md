# Pipa 部署指南 (本 NAS: TrueNAS SCALE dev box)

当前环境探测结果(未装前):

```
TrueNAS SCALE (生产构建)                            ✓
node 20.19.2 + npm 9.0.0                  ✓
python 3.11.2 + dpkg-buildpackage          ✓
cargo / rustc                              ✗ (需 rustup)
middlewared.service 已 active,running       ✓
/usr/sbin/panda-app-server                 ✗ (没装)
/etc/systemd/system/pipa.service           ✗ (没装,且**不应装**)
/var/lib/panda                              ✗ (没装,且**不应建**)
/data/freenas-v1.db (sysdb)                ✓
```

> 重要差异(per-user daemon 时代):
> - 系统级 `pipa.service` **永远不该存在**;pandacode deb 不再 ship `dh_installsystemd` 任何文件。
> - 每用户的 daemon 由 middleware 在 `pipa.stream.connect` 时按 caller UID 拉起,跑在该用户的 `systemd --user` instance 下。
> - 每用户的 socket 是 `/run/user/<uid>/pipa.sock`(由 systemd `RuntimeDirectory=pipa` 自动建),不是 `/run/pipa/pipa.sock`。
> - 每用户的 `~/.panda/` 由 middleware 在首次 connect 时 `sudo -u <user> mkdir -p -m 0700` 预创建,daemon 自己写到那里。
> - middleware 的 postinst **不再** enable/start `pipa.service`(没东西可启)。

---

## 整体流程 (4 步,顺序敏感)

```
0. 装 rustup  (本机 build pandacode 用;纯 middleware + webdesktop 路径跳过)
1. ./tools/deploy-nas.sh --target middleware   # 装新 middleware deb + alembic upgrade head
2. ./tools/deploy-nas.sh --target pandacode    # 装 binary 到 /usr/sbin/,无 daemon 启停
3. ./tools/deploy-nas.sh --target webdesktop   # 装 SPA(浏览器硬刷)
4. bash tools/check-pipa-status.sh              # 总验收
```

> 第 4 步是验收,不是部署动作;`check-pipa-status.sh` 应该已经存在。

---

## Step 0: 装 rustup (若 cargo 不在)

```bash
which cargo
# 没输出 → 跑:

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
source $HOME/.cargo/env
rustc --version
# 期望: rustc 1.8x.x
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
# 包括 dpkg -i + alembic upgrade head,自动建 pipa_user_prefs 表(以及
# 第二次迁移加 multi-preset is_active / display_order / notes 列)
```

**期望输出**:
- 最后几行: `❷ middleware 部署完成` / `==> ✅ 部署成功`
- `systemctl status middlewared` 仍 active
- `sqlite3 /data/freenas-v1.db ".tables" | grep pipa_user_prefs` 有输出
- `sqlite3 /data/freenas-v1.db ".schema pipa_user_prefs"` 看到 `is_active`、`display_order`、`notes` 列
- alembic head 落到 `624a1c758ada`(multi-preset + notes)

> middleware 这次重启**不会**自动启动 pipa daemon — 没有任何系统 daemon 要启。pipa 是 lazy:首次有人按 Cmd+K 才拉。

---

## Step 2: deploy pandacode (binary,无 daemon 管理)

```bash
cd /home/truenas_admin/work/OpenNAS
sudo ./tools/deploy-nas.sh --target pandacode --dry-run

sudo ./tools/deploy-nas.sh --target pandacode
# reinstall 链: clean → build_deb → install
# 装到 /usr/sbin/panda-app-server,**完全不碰 systemd**(没单元要 daemon-reload)
```

**期望输出**:
- `ls -la /usr/sbin/panda-app-server` 存在且 mode 0755
- **没有** `systemctl status pipa`(系统 unit 不存在;这是正确状态)
- **没有** `/run/pipa/pipa.sock`(系统 socket 不存在;per-user socket 在 `/run/user/<uid>/`)
- deb 的 postinst 是 no-op(`configure` 分支 `:` 空命令)

> 装完 panda-app-server 后,**还没有任何进程在跑**——per-user daemon 在用户首次按 Cmd+K 时才被 middleware 拉起。

---

## Step 3: deploy webdesktop (SPA)

```bash
cd /home/truenas_admin/work/OpenNAS
sudo ./tools/deploy-nas.sh --target webdesktop --dry-run

sudo ./tools/deploy-nas.sh --target webdesktop
# webdesktop 没有 daemon,所以 reinstall 只 build + install(到 webserver serving dir)
# deploy-nas.sh 提示: 浏览器需 Ctrl+Shift+R 硬刷
```

**期望输出**:
- 装到 `/usr/share/opennas/webdesktop/` 或 `/usr/share/truenas/webdesktop/`(看 deb)
- `systemctl reload nginx`(若用 nginx)

---

## Step 4: 总验收(per-user daemon 视角)

**先准备**:用两个不同 TrueNAS 用户各登录一次 webdesktop,各按一次 Cmd+K(触发 lazy 拉起)。

```bash
bash /home/truenas_admin/work/OpenNAS/tools/check-pipa-status.sh
```

**期望输出**:全部 ✓,总结 `All green.`(脚本应该覆盖 per-user 状态检查)

**手工 per-user 验证**(不依赖脚本):

```bash
# 1. 系统级 unit 不应存在(确认 system daemon 已删)
systemctl status pipa.service
# expect: Unit pipa.service could not be found.

# 2. 列出所有 per-user daemon 进程(uid = 真实登录用户)
ps -eo pid,rss,user,args --no-headers | grep '[p]anda-app-server.*--listen unix:///run/user/'
# expect: 至少一行(每个触发过的用户一行);args 里能看到 /run/user/<uid>/pipa.sock

# 3. 列出 per-user socket
ls -la /run/user/*/pipa.sock
# expect: srw------- <user> <user>

# 4. per-user unit 文件
ls -la /home/<user>/.config/systemd/user/pipa.service
# expect: -rw-r--r-- <user> <user> (middleware 渲染时已 sudo -u 写)

# 5. per-user panda home
ls -la /home/<user>/.panda
# expect: drwx------ <user> <user>

# 6. linger 已开(否则 user 登出 daemon 跟着死)
loginctl show-user <uid> Linger=
# expect: Linger=yes

# 7. 当前登录用户的 daemon 状态(per-caller,任何登录用户都能查)
midclt call pipa.status
# expect: daemon_reachable: true

# 8. admin 查任意 uid 的 daemon 状态(需 PIPA_READ 角色)
midclt call pipa.supervisor.status <uid>
# expect: daemon_reachable: true
```

---

## 端到端人工验收

完整 10 步人工验收(浏览器 → Cmd+K → 流式 → Settings → DB → 多用户隔离 → middleware 重启存活)见 [pipa-test-runbook.md §3-§5](./pipa-test-runbook.md)。

---

## 回滚

```bash
# 1. middleware 重装回滚(从 git checkout 干净版)
cd /home/truenas_admin/work/OpenNAS/middleware
git checkout -- src/middlewared/middlewared/plugins/pipa.py \
                 src/middlewared/middlewared/plugins/pipa_supervisor.py \
                 src/middlewared/middlewared/api/v26_0_0/pipa.py
sudo ./tools/deploy-nas.sh --target middleware

# 2. 卸 pandacode deb(注意:卸完不会自动 kill 现存 per-user daemon,会持续运行
#    直到用户登出 + linger 失效或 systemd --user instance 被清理)
sudo dpkg -r panda-app-server
# 可选: 主动清掉每个用户的 daemon
for uid in $(loginctl list-users --no-legend | awk '{print $1}'); do
  sudo -u "#$uid" systemctl --user stop pipa.service 2>/dev/null || true
done

# 3. webdesktop 旧版本
cd /home/truenas_admin/work/OpenNAS/webdesktop
git checkout -- apps/pipa/ src/desktop/components/QuickPipaDialog.tsx
sudo ./tools/deploy-nas.sh --target webdesktop

# 4. 清理数据库(可选;默认保留 pipa_user_prefs 表)
sudo sqlite3 /data/freenas-v1.db "DROP TABLE IF EXISTS pipa_user_prefs;"
sudo -E alembic -c /usr/lib/python3/dist-packages/middlewared/alembic.ini stamp head
```

---

## 出问题怎么报

```
TrueNAS SCALE 版本: cat /etc/os-release | head -3
失败 Step: (0 / 1 / 2 / 3 / 4)
具体命令: (你跑的那条)
期望 vs 实际: (... ...)

Per-user daemon 日志(关键):
  sudo journalctl --user -u pipa.service -M <user>@.host -n 30 --no-pager

Middleware 日志:
  sudo journalctl -u middlewared -n 30 --no-pager

check-pipa-status.sh 输出
```

完整测试用例 (含失败排查表) 见 [docs/pipa-test-runbook.md](./pipa-test-runbook.md)。
AI→middleware 回调鉴权设计见 [docs/pipa-auth-model.md](./pipa-auth-model.md)。
FastConnect 隧道验收见 [docs/fastconnect-pipa-tunnel.md](./fastconnect-pipa-tunnel.md)。
