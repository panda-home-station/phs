# Panda Home Station

[English](README.md)

![Panda Home Station Showcase](docs/show_pic1.png)

**Panda Home Station** 是一个全新的系统，将网络附加存储（NAS）系统和高性能游戏主机合二为一。该系统的目标是成为终极的**家庭数据中心**，能够满足数据存储、游戏主机的需求，同时提供 Web 桌面环境与桌面游戏环境。

## 核心特性

### 1. NAS 服务端与 Web 桌面
一个基础的Nas服务器，通过WebDesktop来访问，并且Nas系统内嵌 AI Agent，旨在提供一个更方便AI操作的系统。

### 2. JollyPad
一个完全基于 Rust 从零构建的代游戏主机。类似于PS5/XBox的游戏主机，充分利用 Rust 的效率和安全性。

---

## 仓库管理

本仓库使用 Google 的 `repo` 工具来管理多个 Git 项目。

### 初始设置

1. 安装 `repo` 工具（如果尚未安装）：
   ```bash
   curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.local/bin/repo
   chmod a+x ~/.local/bin/repo
   ```

2. 初始化仓库：
   ```bash
   git clone http://gitlab.pandamicro.com/panda-home-station/phs.git
   cd phs
   repo init . -m repos/default.xml
   ```

3. 同步所有仓库：
   ```bash
   repo sync
   ```

### 常用命令

- **同步最新更改**：`repo sync`
- **开始新分支**：`repo start <branch_name> --all`
- **上传更改**：`repo upload`
