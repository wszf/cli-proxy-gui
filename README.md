# CLIProxy GUI

一个只面向 macOS 的原生 SwiftUI 多节点管理客户端，用于统一查看多个
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 实例。

## 当前能力

- 保存和切换多个 CLIProxyAPI 节点
- 并发检查所有节点状态
- 查看版本、认证文件、API Key、上游提供商和路由策略概览
- 原生读取和编辑完整 `config.yaml`，保存后触发服务热重载
- 管理客户端 API Keys，支持生成、修改和批量替换
- 查看、上传、启用、禁用和删除 JSON 认证文件
- 查看、搜索和清空节点运行日志
- 原生读取 CAP Token Usage Tracker 的请求、Token 趋势、模型用量、完整维度明细、逐请求明细和预估费用
- Management Key 存储在 macOS Keychain
- 一键打开节点自带的完整 Management Center
- 支持用户配置的 HTTP 节点（公网部署仍强烈建议使用 HTTPS）

## 要求

- macOS 14 或更高版本
- Xcode 26（项目使用 Swift 6）
- 远程节点已设置 `remote-management.allow-remote: true`
- 如需查看 Token 用量，节点需安装并启用 `cap-token-usage-tracker`

## 开发运行

```bash
xcodegen generate
open CLIProxyGUI.xcodeproj
```

也可以直接构建和测试：

```bash
xcodebuild -project CLIProxyGUI.xcodeproj \
  -scheme CLIProxyGUI \
  -destination 'platform=macOS' \
  build test
```

节点地址支持 `host:port`、完整 HTTP(S) URL，或带有
`/v0/management`、`/management.html` 后缀的地址。
