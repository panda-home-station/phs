# Check-Sync Command — Source vs Deployed md5 同步检查

当用户执行 `/check-sync` 时,执行以下流程。

## 1. 检查 source vs deployed 同步状态

```bash
# 默认严格模式:不一致 exit 1,适合 CI / pre-commit
bash tools/check-deploy-sync.sh

# 仅检查某个边界
bash tools/check-deploy-sync.sh --target middleware
bash tools/check-deploy-sync.sh --target tnc,middleware

# soft 模式:不一致只警告不 exit,适合嵌入其他脚本
bash tools/check-deploy-sync.sh --soft
```

输出格式:
- `═══ ❷ middleware (middlewared) ═══`
- `✗  MISMATCH: plugins/truenas_connect/tunnel.py`
- `    src md5: 25b51c...`
- `    dst md5: 588f9c...`
- 总结 + 修复命令

## 2. 检查范围(本机 3 边界)

| 边界 | src | dst |
|---|---|---|
| ❶ truenas_connect_utils | `truenas_connect_utils/truenas_connect_utils/` | `/usr/lib/python3/dist-packages/truenas_connect_utils/` |
| ❷ middleware | `middleware/src/middlewared/middlewared/` (跳过 `test/` `build/` `.pybuild/` `debian/` `alembic/`) | `/usr/lib/python3/dist-packages/middlewared/` |
| ❸ webdesktop | `webdesktop/dist/` | `/usr/share/opennas/webdesktop/` |

❹ fastconnect (cloud portal) 不在范围 —— 走 `tools/deploy-fastconnect.sh`。

## 3. 修不一致

```bash
# 单边界
cd middleware/src/middlewared && sudo make reinstall
cd truenas_connect_utils        && sudo make reinstall
cd webdesktop                   && sudo make reinstall

# 或一键
./tools/deploy-nas.sh --target middleware
./tools/deploy-nas.sh --target middleware,tnc,webdesktop
```

## 4. 自动跑(无需手动触发)

`.claude/settings.json` 已配置 SessionStart hook,每次 dev session 启动自动跑 `--soft`,不一致时输出进对话上下文让 Claude 立刻知道。

## 使用方式

```
/check-sync                  # 严格模式,不一致 exit 1
/check-sync --soft           # soft 模式
/check-sync --target middleware
```