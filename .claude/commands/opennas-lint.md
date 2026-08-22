---
description: 跑 OpenNAS / Panda Home Station 开发规范 lint 套件
---

跑 `.claude/skills/opennas-dev-spec/scripts/lint-alembic-revisions.sh` 检测 alembic revision id。

如果用户给了 `args` (例如 `--strict`, `--with-detail`, `--dir <path>`),把它传给脚本。

## 步骤

1. 确认 cwd 是 OpenNAS 根目录(`pwd` 含 `OpenNAS`)。如果不是,先 `cd` 过去。
2. 跑脚本: `bash .claude/skills/opennas-dev-spec/scripts/lint-alembic-revisions.sh $args`
3. 看 exit code:
   - **0**: 通过。报告"所有 lint 通过"。
   - **1**: 发现手写 / 非 hex。报告失败 summary,告诉用户改哪里 + 怎么改。
     - 修复模板参见 `rules.md` §1「当你需要 rename 已 shipped 的 revision」。
4. 把 rules.md §1 链接给用户作参考。

## 风格

- 不要啰嗦,简短总结
- 有问题就直接说"哪个文件、哪个 id、怎么改"
- 通过就一行"All green"
