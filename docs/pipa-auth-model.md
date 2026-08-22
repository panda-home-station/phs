# Pipa 授权模型设计

> 状态:已落地
> 适用版本:middleware dev 分支(26 链)
> 关联代码:
> - [`middleware/src/middlewared/middlewared/plugins/pipa.py`](middleware/src/middlewared/middleware/plugins/pipa.py)
> - [`middleware/src/middlewared/middlewared/api/v26_0_0/pipa.py`](middleware/src/middlewared/middleware/api/v26_0_0/pipa.py)

## 一句话总结

**Pipa 是系统级基础服务,任何登录用户都能调用 `pipa.user_prefs.*` 配自己的 AI 助手。**

不需要 admin 在 Privileges 页面授权。所有 per-user 隔离由 service 内部 `_user_id_for_session()` 强制执行。

---

## 设计动机

Pipa 给每个 TrueNAS 用户一个独立的 AI 助手(provider / model / 加密 API key / skills / quota / 自动审批策略)。类比:

| 系统基础服务 | 类比 | 谁能用 |
|---|---|---|
| 文件管理器 | 任何登录用户访问自己的 home dir | 任何登录用户 |
| shell | 任何登录用户执行自己的命令 | 任何登录用户 |
| **pipa** | **任何登录用户配自己的 AI** | **任何登录用户** |

这些服务的共同点:
- 任何登录用户直接可用,不需要 admin 单独授权
- per-user 数据隔离由服务自身强制(文件系统权限 / UID 检查 / session 注入 `user_id` 过滤)
- 没有"全系统共享"的写操作需要 admin 单独管

## 关键澄清:Framework 的硬约束

TrueNAS middleware 对 **public CRUDService** 有两条**不可绕过**的硬约束:

1. `role_prefix` 必须非空([`crud_service.py:65-66`](middleware/src/middlewared/middleware/service/crud_service.py#L65-L66))
2. `<role_prefix>_READ` 和 `<role_prefix>_WRITE` 必须在 [`role.py`](middleware/src/middlewared/middleware/role.py) 注册——`main.py:447-457` 在 plugin load 阶段无条件 `add_roles_to_method` 注册,角色不存在就抛 `Invalid role`

这两条**跟 `authorization_required` / `event_register` / `private` 无关**,是 framework 的硬编码。所以方案里必须注册 `PIPA_READ`/`PIPA_WRITE` 两个角色。

**它们不是 RBAC 角色,不需要被授权给任何用户**——framework 在 plugin load 时校验它们存在,但运行时如果方法标了 `authorization_required=False`,dispatcher 跳过角色检查,所以这两个角色不会被实际用来鉴权。它们的存在**纯粹是为了让 `add_roles_to_resource` 不抛异常**。

## 落地方式

### `@api_method(..., authorization_required=False)`

TrueNAS middleware 的 `@api_method` 支持 `authorization_required=False`,意思是:

```python
@api_method(
    PipaUserPrefsQueryArgs, PipaUserPrefsQueryResult,
    pass_app=True,
    authorization_required=False,  # 跳过角色检查,只看认证
)
async def query(self, app, filters, options):
    caller_uid = await self._user_id_for_session(app)
    ...
```

请求处理流水线变成:
```
[authn] 用户登录了吗?  ── 没登录 → 401
   ↓ 是
直接调用方法  ── service 内部 _user_id_for_session() 做 per-user 隔离
```

**没有 `[authz] 用户持有角色 X 吗?` 这一步**。

### 6 个方法,统一策略

| API | 方法 | 守护 |
|---|---|---|
| `pipa.user_prefs.query` | `query` | `authorization_required=False` |
| `pipa.user_prefs.create` | `do_create` | `authorization_required=False` |
| `pipa.user_prefs.update` | `do_update` | `authorization_required=False` |
| `pipa.user_prefs.delete` | `do_delete` | `authorization_required=False` |
| `pipa.status` | `status` | `authorization_required=False` |
| `pipa.test_provider` | `test_provider` | `authorization_required=False` |

`pipa.status` / `pipa.test_provider` 也是 `authorization_required=False`:
- `status`:探测 pandacode daemon 是否在线——系统级探针,任何用户都能看
- `test_provider`:用户测自己的 API key 是否能用——per-user 操作,任何用户都能测自己的

### `PipaUserPrefsService.Config` 的两个细节

```python
class Config:
    namespace = 'pipa.user_prefs'
    cli_namespace = 'pipa.user_prefs'
    datastore = 'pipa_user_prefs'
    role_prefix = 'PIPA'  # framework derives PIPA_READ/PIPA_WRITE at plugin load
    event_register = False  # per-user prefs; cross-user .query events not needed
    entry = PipaUserPrefsEntry
```

**1. `role_prefix = 'PIPA'`** —— framework 在 [`main.py:447-457`](middleware/src/middlewared/middleware/main.py#L447-L457) 派生 `PIPA_READ`/`PIPA_WRITE` 给 implicit methods。如果这俩角色不在 `role.py` 里注册,**plugin load 直接抛 `Invalid role`**。

**2. `event_register = False`** —— **不广播 `pipa.user_prefs.query` 事件**。

CRUDService 默认会 `self.middleware.event_register(f'{namespace}.query', ..., roles=[f'{role_prefix}_READ'])`。per-user 场景下用户 A 改 prefs 不需要广播给用户 B,关掉既契合设计意图,也避开了对 `<role_prefix>_READ` 角色名的额外校验(虽然 PIPA_READ 已经注册了)。

副作用:webdesktop 不能订阅 `pipa.user_prefs.query` 变更通知。前端通过 `pipa.test_provider` / 自家 WS bridge 拿到自己那条的最新状态即可,不需要跨用户的通知。

### `PipaStreamService.Config` 的特殊性

```python
class PipaStreamService(Service):
    class Config:
        namespace = 'pipa.stream'
        private = True
```

**整个 Service 标 `private=True`**,因为 `ws_handler` 不是 JSON-RPC API:

- 它返回 `web.WebSocketResponse`(原生 aiohttp WS),不是 Pydantic Result
- 它直接挂到 `middleware.app.router.add_route('*', '/_plugins/pipa/ws', handler)`,不走 JSON-RPC dispatcher
- 它从 `middleware.call('pipa.stream.ws_handler')` 内部拿 handler,然后 aiohttp 路由转发

[`base.py:77`](middleware/src/middlewared/middleware/service/base.py#L77) 的 `validate_api_method_schema_class_names` 在 `private=True` 时跳过整个类,`cli_namespace` 强制要求也跳过([`utils/plugins.py:113`](middleware/src/middlewared/middleware/utils/plugins.py#L113))。TrueNAS 自己的 `dlm.py` / `keyvalue.py` / `acme_protocol.py` / `dns_client.py` / `post_install.py` / `zettarepl.py` 都是这套模式。

WS handler 的鉴权由它内部的 `self.middleware.ws_can_access(ws, origin)` / `ws.authenticated` 自己管,跟 service 层的 `roles` 无关。

## 安全分析

### 谁能改自己的 prefs?

**任何登录用户**。`authorization_required=False` 不做角色检查,只看登录状态。

### 谁能改别人的 prefs?

**没有任何人**。Service 内部强制:

| 操作 | 隔离代码 |
|---|---|
| `query` | `scoped = list(filters or []) + [['user_id', '=', caller_uid]]` —— 强制 filter |
| `do_create` | `data['user_id'] = caller_uid` —— 强制覆盖 payload 里的 user_id |
| `do_update` | `if existing[0]['user_id'] != caller_uid: raise CallError(..., errno=13)` |
| `do_delete` | `if existing[0]['user_id'] != caller_uid: raise CallError(..., errno=13)` |

`root` 用户 (`username == 'root'`) 是特例,`caller_uid = 0` 作为 sentinel —— 不映射到 `account_bsdusers` 行,等于"root 没有 prefs"。如果要让 root 也有,改 `_user_id_for_session` 单独处理。

### API key 泄露风险

`PipaUserPrefsEntry`(`api/v26_0_0/pipa.py`)**永远不返回** `api_key` 明文,只返回 `api_key_set: bool`。SQLAlchemy 列是 `EncryptedText()`,落盘加密。审计日志只记 `api_key_set` / `api_key_cleared` / `api_key_unchanged` 三个离散事件,不写明文。

跟授权模型独立 —— 即使将来切换到 RBAC,这套加密/审计约束仍然成立。

## 被拒绝的替代方案

### 方案 A:注册 `PIPA_READ` / `PIPA_WRITE` **+ 真实授权**

`role.py` 注册新角色,`role_prefix = 'PIPA'`,方法用 `roles=['PIPA_WRITE']` / `['PIPA_READ']`,**并且** admin 通过 Privileges 把 `PIPA_WRITE` 授给所有用户。

- ❌ 新装/默认状态下不可用,admin 必须为每个用户手动授权
- ❌ 跟我们"系统基础服务"的定位冲突

**为什么没用**:违背产品意图。

### 方案 B:用 `SHARING_ADMIN` 角色 + 凑 `SHARING_ADMIN_READ`

保留 `roles=['SHARING_ADMIN']`,但在 `role.py` 注册 `SHARING_ADMIN_READ = Role()`(空定义)。

- ✅ 任何有 `SHARING_ADMIN` 的用户都能用
- ❌ `SHARING_ADMIN` 只授予 admin / sharing 角色用户,普通用户仍然被 403 挡
- ❌ 凑出来的 `SHARING_ADMIN_READ` 角色名违反 TrueNAS 命名惯例(应该是 `<SERVICE>_READ`)

**为什么没用**:核心用户群(普通登录用户)拿不到权限,而且角色命名违规。

### 方案 C(当前):`authorization_required=False` + 注册空 `PIPA_*` 角色

```python
# role.py
'PIPA_READ': Role(),
'PIPA_WRITE': Role(includes=['PIPA_READ']),
```

```python
# pipa.py
@api_method(..., authorization_required=False)
async def query(self, app, filters, options): ...
```

**关键点**:`PIPA_READ`/`PIPA_WRITE` **不是授权角色,是 framework satisfiers**——framework 在 plugin load 时硬编码派生它们(`main.py:447-457` 不接受空 `role_prefix`,只能用这个方式满足)。运行时 `authorization_required=False` 让 dispatcher 跳过角色检查,所以这两个角色**永远不会被实际用来鉴权**,**不需要把 `PIPA_WRITE` 授给任何用户**。

**为什么用**:
- ✅ 任何登录用户都能用,不需要 privilege 配置
- ✅ per-user 隔离由 service 内部强制,跟其他系统基础服务一致
- ⚠️ 关闭了 `.query` 事件广播——可接受,因为 per-user 场景不需要跨用户通知

## 部署/迁移影响

**没有**。

- 现有用户不用做任何事,登录就能调 `pipa.*`
- **不**需要在 install hook / db migration 里给 `PIPA_WRITE` 授权——它是 framework satisfier,运行时 dispatcher 不查它
- Webdesktop 不用改(API 调用层不变,只多了 `authorization_required=False` 这种后端标志)
- Pandacode 不用改(WS bridge 走的是 `pipa.stream.ws_handler`,跟 RBAC 无关)

## 未来可能的扩展

如果以后 pipa 加入**跨用户**功能(比如 admin 统一配 API key 给所有用户),可以**加挂**一个 `pipa.user_prefs.admin` 方法,用 `roles=['FULL_ADMIN']` 保护。普通用户的 `pipa.user_prefs.*` 保持 `authorization_required=False` 不变。两个入口并存,不破坏现有用户流程。
