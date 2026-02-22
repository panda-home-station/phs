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
   git clone https://github.com/panda-home-station/phs.git
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

## 开发指南

### 1. JollyPad (游戏主机界面)

JollyPad 是基于 Rust 开发的原生界面，可以直接通过 Cargo 运行。

**前置依赖：**
- Rust (Cargo)
- 系统库：`libasound2-dev`, `libudev-dev`, `pkg-config` (Ubuntu/Debian 示例)

**编译与运行：**
```bash
cd jollypad
cargo run --release --bin jolly-launcher
```

**手动配置游戏路径：**
目前 JollyPad 需要手动配置游戏路径。请在 `~/.jolly/app/` 目录下创建 `.ini` 配置文件（例如 `com.localhost.split.ini`），内容如下：

```ini
[Game]
Name=Split
Type=flatpak
Icon=/home/jolly/.jolly/app/split.png
Exec=/home/jolly/games/Split/Binaries/Win64/SplitFiction.exe
Terminal=false
Categories=Game

[Env]
PROTON_NO_ESYNC=1
PROTON_NO_FSYNC=1
WINEDLLOVERRIDES=socialclub=n;nvapi=d;nvapi64=d;winedbg=d;amd_ags_x64=b
PROTON_ENABLE_WAYLAND=0
SDL_VIDEODRIVER=x11
PROTON_ENABLE_NVAPI=0
PROTON_LOG=1
WINEDEBUG=fixme+all,err+all
Steam_Language=schinese
```

### 2. NAS (Web 服务端与桌面)

NAS 部分包含 Rust 后端 (nasserver) 和 React 前端 (webdesktop)。

**前置依赖：**
- Rust (Cargo)
- Node.js (v18+) & npm
- PostgreSQL (需创建 `pnas_db` 数据库)
- 系统库：`libfuse3-dev`, `pkg-config`, `libssl-dev`

**一键启动 (推荐)：**
项目提供了开发脚本，可同时启动前后端服务：

```bash
# 1. 确保 PostgreSQL 正在运行且已创建数据库
# 默认配置连接地址：postgres://postgres@localhost/pnas_db 或使用 peer auth
createdb pnas_db

# 2. 运行开发脚本
./nas/scripts/run_dev.sh
```

脚本将自动：
- 启动 Rust 后端 (端口 8000)
- 启动 Web 前端 (端口 5173)
- 处理文件系统挂载清理
