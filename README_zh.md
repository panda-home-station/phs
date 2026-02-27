# Panda Home Station

[English](README.md)

![Panda Home Station Showcase](docs/show_pic1.png)

**Panda Home Station** 是一个全新的系统，将网络附加存储（NAS）系统和高性能游戏主机合二为一。该系统的目标是实现一个全新的**家庭数据中心**，能够同时满足数据存储、游戏主机的需求。同时提供 Web 桌面环境与桌面游戏环境。

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

## 开发指南

为了更方便的部署，此仓库实现一个一键部署脚本，用于快速部署Panda Home Station系统。

目前仅支持在 Ubuntu/Debian 系统上部署。

在完成仓库克隆之后。执行以下命令即可部署系统：

```bash
./scripts/install.sh
```
提示完成部署即可使用。

### 1. NAS 访问
安装完成之后，会有如下提示：
```
➡️  --------------------------------------
➡️  🎉 Web UI deployed successfully!
➡️
➡️  Visit http://<your_ip>:8080 to access the Web UI.
➡️  --------------------------------------
```
直接浏览器访问： `http://<your_ip>:8080` 即可

### 2. JollyPad (游戏主机界面)
在成功安装完成之后，JollyPad会写入到登录器的选择界面，ubuntu只用在登录的时候选择JollyPad即可登录到游戏主机界面。

**手动配置游戏路径：**
目前 JollyPad 需要手动配置游戏路径。请在 `~/.jolly/app/` 目录下创建 `.ini` 配置文件（例如 `com.localhost.split.ini`），内容参考如下，针对不同的配置，不同的游戏需要不同的配置：

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
