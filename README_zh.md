# Panda Home Station

[English](README.md)

## 项目介绍

**OpenNAS** 是一个现代化的 AI 原生家庭 NAS 系统，基于 TrueNAS 核心技术构建。不仅提供企业级数据存储能力，深度融合 AI 技术，为家庭用户提供智能化的数据管理与服务体验。

### 核心特性

- **AI 原生架构**：AI 能力深度融入系统核心，支持智能文件管理、自动分类与检索
- **Web 桌面**：通过浏览器访问完整桌面环境，随时随地管理数据
- **企业级存储**：支持多种存储协议（ SMB/NFS/iSCSI ），提供完善的数据保护机制
- **插件系统**：模块化设计，支持通过插件扩展系统功能

OpenNAS 致力于为家庭用户提供一个智能、可靠、便捷的数据管理中心。

![OpenNAS 展示](docs/show.png)

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
