# Panda Home Station

[中文](README_zh.md)

![Panda Home Station Showcase](docs/show_pic1.png)

**Panda Home Station** is a revolutionary system that unifies a Network Attached Storage (NAS) and a high-performance game console into a single, cohesive platform. Designed to be the ultimate **Home Data Center**, it is implemented entirely in **Rust** for maximum performance, safety, and reliability.

## Core Features

### 1. NAS Server & Web Desktop
A powerful storage solution featuring a modern, web-based desktop environment. At its heart is an embedded **AI Agent** system that intelligently manages your data and enhances your interaction with the platform.

### 2. JollyPad
A next-generation game console built from the ground up in Rust. JollyPad aims to deliver a console gaming experience comparable to the PS5, leveraging the efficiency and safety of Rust.

---

## Repository Management

This repository uses Google's `repo` tool to manage multiple Git projects.

### Initial Setup

1. Install `repo` tool (if not already installed):
   ```bash
   curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.local/bin/repo
   chmod a+x ~/.local/bin/repo
   ```

2. Initialize the repo:
   ```bash
   git clone https://github.com/panda-home-station/phs.git
   cd phs
   repo init . -m repos/default.xml
   ```

3. Sync all repositories:
   ```bash
   repo sync
   ```

### Common Commands

- **Sync latest changes**: `repo sync`
- **Start a new branch**: `repo start <branch_name> --all`
- **Upload changes**: `repo upload`
