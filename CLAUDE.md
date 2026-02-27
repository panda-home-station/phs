# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Panda Home Station (PHS) is a unified Home Data Center that combines a Network Attached Storage (NAS) system with a high-performance game console. The entire platform is built primarily in Rust for performance, safety, and reliability.

## Repository Management

This project uses Google's `repo` tool to manage multiple Git repositories. The main repository is a manifest that references separate sub-projects.

### Initial Setup

```bash
# Install repo tool if not present
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.local/bin/repo
chmod a+x ~/.local/bin/repo

# Initialize repo (skip if .repo directory exists)
git clone https://github.com/panda-home-station/phs.git
cd phs
repo init . -m repos/default.xml

# Sync all repositories
repo sync
```

### Repository Structure

The `repos/` directory contains manifest definitions:
- `default.xml` - Main manifest including NAS, Desktop, and Tools
- `nas.xml` - NAS-related projects (nasserver, webdesktop, scripts, assets)
- `desktop.xml` - Desktop/JollyPad projects (jollypad, jolly-compositor, assets)
- `tools.xml` - Tool projects (checked in from repos/tools.xml)

### Sync Sub-Repositories

When working in this repository, always ensure sub-repositories are synced:
```bash
repo sync
```

## Installation

### One-Click Installation

The repository provides a complete installation script for Ubuntu/Debian systems:

```bash
./scripts/install.sh
```

This script orchestrates:
1. System dependencies installation (see `scripts/tasks/deps.sh`)
2. Repository synchronization
3. Database setup for NAS server
4. Building Debian packages for all components
5. Installing packages and services

### Installation Tasks

The installation is broken down into modular tasks in `scripts/tasks/`:
- `deps.sh` - Install system dependencies
- `service.sh` - Service management utilities
- `build.sh` - Build Debian packages
- `db_setup.sh` - Database initialization
- `install_deb.sh` - Package installation

## Sub-Projects

### NAS (`nas/`)

NAS server with React web frontend providing file storage, container management, downloads, and AI agent capabilities.

**Development:** See `nas/CLAUDE.md` for detailed development commands and architecture.

**Access:** Web UI available at `http://<your_ip>:8080`

**Components:**
- `nas/nasserver` - Rust backend (13 crates)
- `nas/webdesktop` - React/Vite frontend

### JollyPad (`jollypad/`)

Wayland-based desktop environment and game console for Linux handheld devices, built entirely in Rust with Slint UI.

**Development:** See `jollypad/CLAUDE.md` for detailed development commands and architecture.

**Build and Run:**
```bash
cd jollypad
cargo run --release --bin jolly-launcher
```

**Components:**
- `jollypad/crates/catacomb` - Wayland compositor (Smithay-based)
- `jollypad/apps/` - Slintint UI applications (launcher, home, nav, settings)
- `jollypad/crates/` - Shared libraries (core, ipc, ui-kit)

## Common Development Patterns

### Working Across Sub-Projects

When making changes that affect multiple sub-repositories:
1. Work in the appropriate sub-directory (`nas/` or `jollypad/`)
2. Each sub-project has its own build system (Cargo for Rust, npm for frontend)
3. Use `repo status` and `repo sync` to manage changes across all repos

### Environment Setup

**For JollyPad:**
- Rust (Cargo)
- System libraries: `libasound2-dev`, `libudev-dev`, `pkg-config`

**For NAS:**
- Rust (Cargo)
- Node.js (for frontend)
- PostgreSQL (database)

## System Integration

### Game Configuration

JollyPad games are configured via `.ini` files in `~/.jolly/app/` (e.g., `com.localhost.split.ini`):

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

## Architecture Notes

This is a monorepo using the `repo` tool to coordinate multiple independent projects. Each sub-project has:
- Its own CLAUDE.md with project-specific guidance
- Independent build systems (Cargo workspaces, npm, etc.)
- Independent testing and deployment workflows

The root-level `scripts/install.sh` provides a unified deployment path for the entire system.
