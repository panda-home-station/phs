# Panda Home Station

[中文](README_zh.md)

## Project Introduction

**OpenNAS** is a modern AI-native home NAS system, built on **TrueNAS core technology** for secondary development. It provides enterprise-grade data storage capabilities with deep AI integration, offering intelligent data management and service experience for home users.

### Why TrueNAS?

TrueNAS is an enterprise-grade open-source NAS solution with the following advantages:

- **Security**: Built on FreeBSD with SELinux support, regular security patches, and a proven track record in enterprise environments
- **Stability**: Mature and stable with 20+ years of development history, widely used in mission-critical deployments
- **Enterprise Features**: Supports ZFS filesystem with data integrity protection, snapshots, replication, and advanced storage management
- **Open Source**: Full source code availability, transparency, and community support
- **Rich Protocols**: Comprehensive protocol support including SMB/NFS/iSCSI/AFP/SFTP

### OpenNAS Core Features

Based on TrueNAS core technology, OpenNAS enhances the following capabilities:

- **AI-Native Architecture**: AI capabilities deeply integrated into the system core, supporting intelligent file management, automatic classification and retrieval
- **Web Desktop**: Access a complete desktop environment through your browser, manage data anytime, anywhere
- **Enterprise Storage**: Supports multiple storage protocols (SMB/NFS/iSCSI) with comprehensive data protection mechanisms
- **Plugin System**: Modular design, extensible system functionality through plugins
- **Enhanced UX**: Modern WebDesktop system based on React, providing a smoother desktop-class user experience
- **Localization**: Full Chinese language support with localized UI and documentation

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
