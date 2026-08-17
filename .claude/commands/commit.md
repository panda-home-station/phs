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