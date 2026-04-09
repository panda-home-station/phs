# Commit Command — PHS Multi-Repo

当用户执行 `/commit` 时，按照以下流程确定目标仓库并委托提交。

## 1. 确定目标子仓库

根据对话上下文信息判断当前修改的代码仓库，或者根据各个子仓库的git状态进行判断。
其中包括：
./: 当前顶层仓库，主要负责子仓库的维护，以及AI上下文信息的维护
./webui: 旧前端代码
./middleware: 中间段代码
./webdesktop：前端的代码，上下文的文档包含: webdesktop/.claude/commands/commit.md

需要提交哪个仓库就在哪个仓库目录下进行操作。

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

## 4. 顶层 Repo 变更

如果只有顶层文件（`.claude/`、`CLAUDE.md` 等）变更，在顶层执行提交。