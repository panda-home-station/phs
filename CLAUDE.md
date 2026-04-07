# Panda Home Station

**Panda Home Station** 是一个全新的系统，将网络附加存储（NAS）系统和高性能游戏主机合二为一。该系统的目标是实现一个全新的**家庭数据中心**，能够同时满足数据存储、游戏主机的需求。同时提供 Web 桌面环境与桌面游戏环境。

## Repositories
PHS 是一个由andoird的repo工具管理的多代码仓库，根目录仓库用来作为repo的管理以及项目入口。其中包含子仓库(独立git管理)：

- **webui**: truenas原始的完整web系统
- **webdesktop**: 使用 React 开发的一个webdesktop前端系统，一个完整的桌面系统
- **middleware**: TrueNAS 中间件源码仓库，负责处理远程过程调用(RPC)和事件通知，通过插件系统实现服务，支持 WebSocket 和 RESTful API 访问

## 任务
当前的目标是将 webui的功能完全迁移到 webdesktop上面，实现一个nas web桌面，而不是仅仅一个webui。

## 开发
开发调试都在webdesktop目录下，npm运行也需要在webdesktop目录下。

## Document Reference (需要时读取)

### 1.1 子系统的Claude.md文件
- webui/Claude.md
- webdesktop/Claude.md

### 1.2 TrueNAS 开发者文档索引(需要时读取) (middleware/docs/source/)

**说明**: 这是 TrueNAS 的开发者文档，面向参与 TrueNAS 开发的开发者。文档采用 Sphinx 格式，涵盖了系统架构、开发流程、构建、测试、以及各个子系统的实现细节。

#### 一级文档索引 (middleware/docs/)

| 文件 | 说明 |
|------|------|
| middleware/docs/source/index.rst | 文档首页，包含所有模块的目录索引 |

#### 二级文档目录
middleware/docs/source路径下子目录

| 目录 | 说明 |
|------|------|
| middleware/docs/source/accounts | 账户系统首页 |
| middleware/docs/source/api | API 系统首页 |
| middleware/docs/source/audit | 审计系统首页 |
| middleware/docs/source/build | 构建系统首页 |
| middleware/docs/source/database | 数据库首页 |
| middleware/docs/source/dev-workspace | 开发工作区首页 |
| middleware/docs/source/external-services | 外部服务首页 |
| middleware/docs/source/middleware | 中间件首页 |
| middleware/docs/source/middleware/plugins | 插件首页 |
| middleware/docs/source/os | OS 首页 |
| middleware/docs/source/services | 服务首页 |
| middleware/docs/source/simulating | 模拟首页 |
| middleware/docs/source/testing/integration-tests | 集成测试首页 |

### 1.3 Middlewared 文档索引(需要时读取) (middleware/src/middlewared/)

**说明**: Middlewared 文档分为两部分：
1. 核心文档：位于 `middleware/src/middlewared/middlewared/docs/`，描述中间件架构、服务类型（service/config/crud）、任务系统、WebSocket/DDP 协议等
2. API 文档：位于 `middleware/src/middlewared_docs/docs/`，提供 JSON-RPC 协议、任务系统、查询方法等 API 使用指南

#### Middlewared 核心文档

| 文件 | 说明 |
|------|------|
| src/middlewared/middlewared/docs/index.rst | Middlewared 核心文档，包含 WebSocket、DDP 协议、API 调用等 |

#### API 文档生成器相关文档

| 文件 | 说明 |
|------|------|
| src/middlewared_docs/docs/index.rst | API 文档首页 |
| src/middlewared_docs/docs/jsonrpc.rst | JSON-RPC 协议文档 |
| src/middlewared_docs/docs/jobs.rst | 任务系统文档 |
| src/middlewared_docs/docs/query_methods.rst | 查询方法文档 |