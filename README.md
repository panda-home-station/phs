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

## Development Guide

To simplify deployment, this repository provides a one‑click installation script for Panda Home Station.
Currently, only Ubuntu/Debian systems are supported.

After cloning the repository, run:

```bash
./scripts/install.sh
```

Once the script completes, the system is ready to use.

### 1. NAS Access
After installation, you will see output similar to:

```
➡️  --------------------------------------
➡️  🎉 Web UI deployed successfully!
➡️
➡️  Visit http://<your_ip>:8080 to access the Web UI.
➡️  --------------------------------------
```
Open your browser and visit: `http://<your_ip>:8080`

### 2. JollyPad (Game Console Interface)

After successful installation, JollyPad is added to the session list of your display manager. On Ubuntu, simply choose “JollyPad” on the login screen to enter the console UI.

**Prerequisites:**
- Rust (Cargo)
- System Libraries: `libasound2-dev`, `libudev-dev`, `pkg-config` (Ubuntu/Debian examples)

**Build and Run:**
```bash
cd jollypad
cargo run --release --bin jolly-launcher
```

**Manual Game Configuration:**
Currently, JollyPad requires manual configuration for game paths. Please create an `.ini` configuration file in the `~/.jolly/app/` directory (e.g., `com.localhost.split.ini`) with the following content:

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

---
