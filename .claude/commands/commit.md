# Commit Command — PHS Multi-Repo

当用户执行 `/commit` 时，按照以下流程确定目标仓库并委托提交。

## 1. 确定目标子仓库

**必须先运行检查脚本**：

```bash
tools/check-git-status.sh
```

这会扫描所有仓库并报告哪些有变更。根据输出确定需要提交的仓库。

其中包括：
- `.`: 当前顶层仓库，主要负责子仓库的维护，以及AI上下文信息的维护
- `./webdesktop`: 前端的代码，上下文的文档包含: webdesktop/.claude/commands/commit.md
- `./webui`: 旧前端代码
- `./middleware`: 中间段代码

## 2. 单仓库变更

直接委托给对应子仓库的 commit 命令：

```bash
# 切换到子仓库目录
cd <sub-repo>

# 执行子仓库的 commit 命令（参见对应 .claude/commands/commit.md）
# 注意：子仓库有独立的 commit 流程需要读取子仓库的commit命令
```

## 3. 跨仓库变更

如果修改涉及多个子仓库，需要**分别**对每个子仓库执行提交：

```
检测到变更: webdesktop/ + webui/
1. 先提交 webdesktop 的变更
2. 再提交 webui 的变更
3. 如果顶层也有变更，单独处理
```

按照以下顺序提交（如果有多个）：
1. webdesktop
2. webui
3. middleware
4. top（顶层）

## 4. 顶层 Repo 变更

如果只有顶层文件（`.claude/`、`CLAUDE.md` 等）变更，在顶层执行提交。

## 5. Code Review — 提交前必跑

委托给子仓库 commit 之前，先扫一遍本次 diff 把以下硬伤干掉再去提交。规则参考 memory `no-indexed-annotations`：

```bash
# 在目标子仓库根目录
git diff -- ':!*.lock' | grep -nE '\b(M[0-9]+|P[0-9]+|C[0-9]+|Sprint[0-9]+|Phase [0-9]+)\b|2026-|202[0-9]-Q[0-9]|[0-9]+\.[0-9]+\.[0-9]+-pandacode-[0-9]+|// *[0-9]+\)|^\s*\*.*\(C[0-9]'
```

命中后逐条处理：

- **代号** (`M0`/`P2-3`/`Sprint2`/`8.15` 等需要查路线图才知道含义的) → 删；如果是阶段标记，改成该阶段的实际行为描述。
- **阶段号** (`Phase 1`/`Phase 2`/`step 1 of 3`/`// 1) ...`) → 删编号，只留行为描述。
- **日期** (`2026-08-17`/`2026-Q2`/`Earlier (2026-08-17)` 这类散落在注释里的) → 删；阶段史归 changelog。
- **版本号** (`v0.1.0-pandacode-3`/`0.1.0-pandacode-4` 在代码注释里) → 删；版本史归 debian/changelog。
- **数字 cardinality** (`1:1`/`1-to-1`) → 改成 `one-to-one`。
- **alembic 文件名** + **Create Date 那一行** → 保留，那是 alembic 约定。
- **debian/changelog** 的日期 + 版本号 → 保留，那是 Debian 约定。

判断标准：**"六个月后另一个人看到这一行,知不知道什么意思?"** 不知道就改。阶段史如果要留，放 docs/roadmap 或 ADR，不在代码注释里塞。