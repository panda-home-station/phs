# TrueNAS WebUI Migration Project

This directory contains two repositories for migrating TrueNAS WebUI from Angular to React.

## Repositories

### `webui/` - Original Angular Application
- **Framework**: Angular 21.2
- **Technology**: TypeScript, NgRx, Angular Material
- **API**: WebSocket (JSON-RPC 2.0)
- **Status**: Production (original implementation)
- **Purpose**: Source of truth for business logic, API methods, and type definitions

### `webdesktop/` - New React Application (Target)
- **Framework**: React 18 + Vite
- **Technology**: TypeScript, webdesktop UI framework
- **API**: WebSocket (JSON-RPC 2.0) - to be migrated
- **Status**: Development (branch: `truenas`)
- **Purpose**: Modern replacement with desktop-like UI

## Migration Strategy

### Goal
Replace Angular webui with React-based webdesktop implementation while maintaining all TrueNAS functionality.

### Approach
1. **Use webdesktop as UI framework base**
   - Window management system
   - Desktop environment (Desktop, Taskbar, Launcher)
   - Modern UI components

2. **Migrate business logic from webui**
   - WebSocket API services
   - Type definitions and interfaces
   - Helper functions
   - Domain-specific logic

3. **Create TrueNAS applications as desktop apps**
   - Each TrueNAS module (Storage, Settings, Dashboard, etc.) becomes a desktop app
   - Apps run in windows managed by webdesktop

## Current Status

### ✅ Completed
- Created `truenas` branch in webdesktop
- Removed original webdesktop business apps
- Removed original REST API layer
- Set up TrueNAS API structure (WebSocket client placeholder)
- Simplified App.tsx

### 🚧 In Progress
- Migrating TrueNAS WebSocket API service from webui
- Porting type definitions from webui/src/interfaces/

### 📋 Planned
- Port authentication system
- Create Dashboard app
- Port other TrueNAS modules (Storage, Settings, Network, etc.)

## Development Workflow

### Working on webdesktop
```bash
cd webdesktop
npm run dev  # http://localhost:5173
```

### Reference webui code
```bash
cd webui
# Browse source files at:
# src/app/modules/websocket/ - WebSocket implementation
# src/app/interfaces/ - Type definitions
# src/app/helpers/ - Utilities
```

## Notes

- This is a complete rewrite, not a direct translation
- Focus on modern UI/UX with desktop-like interface
- All business logic should be ported from webui
- webui remains the reference until migration is complete
