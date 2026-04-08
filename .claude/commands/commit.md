# Commit Command — PHS Multi-Repo

当用户执行 `/commit` 时，按照以下流程确定目标仓库并委托提交。

## 1. 确定目标子仓库

### 读取当前活跃子仓库

```bash
cat .claude/current
```

- 如果文件存在且非空，使用其中指定的子仓库
- 如果为空或不存在，执行自动检测

### 自动检测

```bash
git diff --name-only HEAD | head -20
```

分析输出的文件路径，确定涉及的子仓库：
- `webdesktop/*` → webdesktop
- `webui/*` → webui
- `middleware/*` → middleware
- 顶层文件（如 `CLAUDE.md`、`.claude/*`）→ 顶层 repo

## 2. 单仓库变更

直接委托给对应子仓库的 commit 命令：

```bash
# 切换到子仓库目录
cd <sub-repo>

# 执行子仓库的 commit 命令（参见对应 .claude/commands/commit.md）
# 注意：子仓库有独立的 commit 流程，包括 code review 和 test
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

### 顶层 Commit Message 格式

```
<type>: <subject>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**Type 类型**：
- `repo`: repo 配置文件变更
- `chore`: 构建/工具变更
- `docs`: 文档变更

## 5. 子仓库 Commit 委托

每个子仓库有独立的 commit 命令，详情需要时读取对应文件：

| 子仓库 | Commit 命令文件 |
|--------|----------------|
| webui | `webui/.claude/commands/commit.md` |
| webdesktop | `webdesktop/.claude/commands/commit.md` |
| middleware | 暂无独立配置，如有需要可参考其他子仓库创建 |

## 注意事项

- **不要在顶层直接执行子仓库的命令** — 先 `cd` 到对应目录
- **子仓库的 commit 是独立流程** — 包含 review 和 test，不是简单 git commit
- **跨仓库提交需要用户明确确认** — 多个子仓库同时修改时，先列出变更再逐个提交
