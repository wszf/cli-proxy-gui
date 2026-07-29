# CLIProxy GUI

[English](README.en.md) | 简体中文

CLIProxy GUI 是一个只面向 macOS 的原生 SwiftUI 客户端，用来统一管理多个
[CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 节点。

项目目前处于早期阶段，Management API 或第三方额度接口变化时，部分功能可能需要同步适配。

> 本项目是独立的社区客户端，与 CLIProxyAPI、OpenAI、Anthropic 或 Moonshot AI
> 没有官方隶属或背书关系。

## 功能

- 保存、切换和并发检查多个 CLIProxyAPI 节点
- 展示延迟、版本、凭证健康、账号额度、可用模型、当日用量、插件和运行配置
- 读取和编辑完整 `config.yaml`，保存后由服务端触发热重载
- 管理客户端 API Keys，支持生成、修改和批量替换
- 查看、上传、启用、禁用和删除 JSON 认证文件
- 查看、搜索和清空节点运行日志
- 读取 CAP Token Usage Tracker 的趋势、模型、维度、请求明细和预估费用
- 将 Management Key 存储在 macOS Keychain
- 单实例运行，重复打开时激活已有窗口
- 打开节点自带的完整 Management Center
- 支持 HTTP 节点，但公网和不可信网络应使用 HTTPS

账号额度目前支持 Codex、Claude 和 Kimi OAuth 凭证。额度请求按账号并发执行，
每个节点至少间隔 3 分钟；认证文件变化后会立即刷新。

## 系统要求

- macOS 14 Sonoma 或更高版本
- CLIProxyAPI 节点允许远程管理
- 从源码构建需要 Xcode 26
- 修改项目配置时建议安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 用量页面需要节点安装并启用 `cap-token-usage-tracker`

## 使用

1. 在 CLIProxyAPI 配置中开启远程管理，并设置强 Management Key。
2. 启动应用，添加节点地址和 Management Key。
3. 节点地址可以是 `host:port`、完整 HTTP(S) URL，或带有
   `/v0/management`、`/management.html` 后缀的地址。

如果只填写 `host:port`，应用会按 HTTP 处理。HTTP 会让 Management Key 和管理数据
以明文在网络上传输，仅应在可信内网使用。

## 从源码构建

仓库已经包含生成后的 Xcode 工程，直接打开即可：

```bash
open CLIProxyGUI.xcodeproj
```

命令行构建和测试：

```bash
./Scripts/ci.sh
```

`project.yml` 是项目结构的来源。修改它以后重新生成 Xcode 工程：

```bash
xcodegen generate
```

## 数据和网络

- 节点名称和地址保存在本机 `UserDefaults`。
- Management Key 保存在 macOS Keychain，不写入项目目录或日志。
- 应用不包含遥测、分析服务、广告或项目自有服务器。
- 常规请求从 Mac 直接发送到用户添加的 CLIProxyAPI 节点。
- 读取账号额度时，应用把 `auth_index` 和目标请求模板发送给节点的 Management
  `api-call` 接口，由节点代入 OAuth 凭证并访问上游；OAuth Token 不会返回给应用。

更完整的风险边界和漏洞报告方式请阅读 [SECURITY.md](SECURITY.md)。

## 项目结构

```text
Sources/
  Models/       数据模型和解析辅助
  Networking/   Management API 与插件请求
  Security/     Keychain 存储
  Stores/       节点和刷新状态
  Views/        SwiftUI 界面
Tests/          单元测试
Config/         Info.plist
project.yml     XcodeGen 项目定义
```

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读
[CONTRIBUTING.md](CONTRIBUTING.md) 和 [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)。

## 许可证

本项目使用 [MIT License](LICENSE)。
