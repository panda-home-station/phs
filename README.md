# Panda Home Station

[中文](README_zh.md)

## Project Introduction

**OpenNAS** is a modern AI-native home NAS system, built on TrueNAS core technology. It provides enterprise-grade data storage capabilities with deep AI integration, offering intelligent data management and service experience for home users.

### Core Features

- **AI-Native Architecture**: AI capabilities deeply integrated into the system core, supporting intelligent file management, automatic classification and retrieval
- **Web Desktop**: Access a complete desktop environment through your browser, manage data anytime, anywhere
- **Enterprise Storage**: Supports multiple storage protocols (SMB/NFS/iSCSI) with comprehensive data protection mechanisms
- **Plugin System**: Modular design, extensible system functionality through plugins

OpenNAS is committed to providing home users with an intelligent, reliable, and convenient data management center.

![OpenNAS Showcase](docs/show.png)

## Repository Management

This repository uses Google's `repo` tool to manage multiple Git projects.

### Initial Setup

1. Install `repo` (if not already installed):
   ```bash
   curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.local/bin/repo
   chmod a+x ~/.local/bin/repo
   ```

2. Initialize the repository:
   ```bash
   git clone https://github.com/panda-home-station/phs.git
   cd phs
   repo init . -m repos/default.xml
   ```

3. Sync all repositories:
   ```bash
   repo sync
   ```

## Development Guide
