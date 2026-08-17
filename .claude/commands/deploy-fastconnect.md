# Deploy Command — FastConnect

当用户执行 `/deploy-fastconnect` 时，执行以下流程。

## 1. 部署 FastConnect

```bash
# 默认部署到生产(REMOTE 从脚本默认读)
bash tools/deploy-fastconnect.sh

# 或者覆盖环境变量(部署到不同环境)
REMOTE=root@1.2.3.4 BASE_DOMAIN=staging.example.com bash tools/deploy-fastconnect.sh
```

## 2. 验证部署

部署脚本会自带完整 smoke test 覆盖 Phase 1-6 所有端点 + 错误信封 + cert 验证。
脚本最后会输出 `通过/失败/跳过` 的数量,失败时自动打印远程日志。

如需手动验证:

```bash
ssh fastconnect "docker exec fastconnect_api python -c 'import urllib.request; print(urllib.request.urlopen(\"http://localhost:8000/health\").read().decode())'"
```

> SSH alias `fastconnect` → HostName `fastconnect.host` (随 DNS 自动漂移,2026-08-15 切换)

## 3. 检查日志

如有需要,查看 API 日志:

```bash
ssh fastconnect "docker logs fastconnect_api 2>&1 | tail -20"
```

## smoke test 覆盖范围(脚本里自动跑)

- Phase 1: 基础端点 / 子域名 cert 验证 / WebSocket 路由回归
- Phase 2: lookup + 错误信封 / 鉴权
- Phase 4: punch 端点
- Phase 5: fqdn 端点
- Phase 6: 错误信封通用验证
- Portal 容器 + 根域 React SPA

需要 `jq` 来跑 envelope 断言(可选,没装也不致命)

## 使用方式

```
/deploy-fastconnect    # 部署 FastConnect 到生产服务器
```
