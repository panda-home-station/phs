---
name: opennas-dev-spec
description: OpenNAS / Panda Home Station monorepo 开发规范 (Chinese term for "dev convention / coding standards / process rules"). Trigger when the user asks about coding conventions, project structure, "is this OK", "review", "PR", "deploy", "alembic", "pipa", "middleware plugin", "pandacode", or wants to start a new feature in OpenNAS — load this skill first.
metadata:
  type: project
  scope: monorepo
  version: 1
  last-updated: 2026-08-20
  zh-name: 开放网络附加存储 开发规范
---

# OpenNAS 开发规范 (Dev Spec)

> **TL;DR** — 这是 OpenNAS / Panda Home Station 的**项目级开发规范总入口**。所有 dev 跟 AI 助手在 review、写代码、deploy 前都按这规范走。规则有 10 大块,详见 [`rules.md`](rules.md)。**lint 一键**:`/opennas-lint` (顶层命令) 或者 `bash .claude/skills/opennas-dev-spec/scripts/lint-alembic-revisions.sh`.

## 这个 monorepo 的结构

```
OpenNAS/
├── webui/         TrueNAS 原始 web 系统 (Angular) — 维护中,但不是 dev 重点
├── webdesktop/    React 桌面系统 — dev 主战场
├── middleware/    TrueNAS 中间件 (Python + aiohttp + SQLAlchemy + Alembic) — RPC/WS
├── pandacode/     Pipa AI 助手后端 (Rust daemon + Node.js bridge)
├── repos/         Repo 工具的 manifest + 设备相关
├── docs/          系统设计文档
├── tools/         部署脚本总集 (deploy-nas.sh / check-pipa-status.sh)
└── .claude/       Claude Code 项目级配置 (本目录)
```

每个子仓库独立 git 管理。**顶层 OpenNAS 仓库**只协调 + 聚合。**写代码在子仓库**。

## 什么时候读这个 skill

- ✅ 写新 middleware plugin / service
- ✅ 写新 alembic migration
- ✅ 写新版 pandacode binary / Rust API
- ✅ 写新 webdesktop React feature / 组件
- ✅ 提交前 / PR review / pre-deploy 检查
- ✅ "我对某段代码不确定" → 触发本 skill 找规则

## 18 大规则(每条都另附细则)

### 1-10: dev 直接写的代码规范

1. **alembic revisions** — 必须 `alembic revision -m`,绝不手写 hex
2. **middleware plugin 命名 + cli_namespace** — `app.namespace.method`,三个名字必填
3. **@private + @staticmethod 冲突** — 不要 `@private @staticmethod` 同用
4. **Sensitive 数据** — 所有 API key / token 用 EncryptedText,不能明文
5. **Multi-user 隔离** — 全局 HOME 不安全,每个 WS 连接用独立 user_home
6. **注释不写代号 / 阶段号 / 日期** — 可索引的字符串别进 docstring
7. **跨仓库修改** — 4 个仓库独立 commit 独立 PR
8. **本地部署** — `tools/deploy-nas.sh --target <id>`,禁散打 sudo
9. **cwd 子仓库对齐** — 写代码前先 cd 进去
10. **凭证管理** — sudo_askpass / pwenc_secret 不进 git

### 11-18: 从 memory 收敛的架构 / 部署 / 流程规范

11. **@api_method 薄壳包装** — internal call 必须 `*args` 兼容
12. **App architecture 三个"不要"** — 不改 main.py, 不写 raw WebSocket, 不绑 port
13. **Pipa architecture** — JSON-RPC + middleware event channel,不再切 raw WS
14. **PANDA_HOME vs CODEX_HOME** — pandacode fork 读 PANDA_HOME
15. **systemd unit packaging** — 绑 binary 所在 deb,跟其他 deb 跨边界
16. **Repo ownership matrix** — 4 仓库各自改各自范围
17. **Bash deploy subshell exit 陷阱** — subshell exit 只退 subshell,不等 main 退
18. **Commit checklist: 无 indexed annotations** — PR review 必查

详细 ↘ [`rules.md`](rules.md)

## 一键 lint

```bash
# alembic 手写 id 检测
bash .claude/skills/opennas-dev-spec/scripts/lint-alembic-revisions.sh

# 走全套 lint (将来会扩展)
bash .claude/skills/opennas-dev-spec/scripts/lint-all.sh
```

或者在 Claude Code 里:

```
/opennas-lint
```

## 子仓库 CLAUDE.md 索引

- [middleware/CLAUDE.md](../../middleware/CLAUDE.md) — Service / API / Datastore 详细规范
- [webdesktop/CLAUDE.md](../../webdesktop/CLAUDE.md) — React 项目工作流
- [webui/CLAUDE.md](../../webui/CLAUDE.md) — Angular 维护
- [pandacode/CLAUDE.md](../../pandacode/CLAUDE.md) — Rust + Node.js

## 触发示例

用户说「我要加一个新的 Pipa skill」→ 触发本 skill →
读 `rules.md` §2 (plugin 命名) + §3 (Sensitive 数据) + §6 (无代号) →
跑 `lint-alembic-revisions.sh` 确认 revision 可以 → 写代码 →
`/opennas-lint` 跑一遍 → commit。

## 修改日志

- **1.0 (2026-08-20)** — 第 1 版 digitize,合并 14-reviews Pipa 教训 + 跨仓库 deploy 流程
