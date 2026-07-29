# Security Policy

## Supported versions

安全修复只面向默认分支的最新代码。发布版本出现安全问题时，请先升级到最新版本
或最新提交确认问题仍然存在。

## Reporting a vulnerability

请不要为漏洞、凭证泄露或可复现的未授权访问创建公开 Issue。

仓库发布到 GitHub 后，请使用仓库 **Security → Report a vulnerability** 发起私密报告。
报告中请包含受影响版本、影响范围、复现步骤和建议修复；所有密钥、节点地址、日志和
账号信息都应先脱敏。

维护者确认问题后会尽快给出状态更新。修复发布前，请勿公开利用细节。

## Security boundary

- Management Key 存储在 macOS Keychain；节点名称和地址存储在 `UserDefaults`。
- 应用不上传遥测，不连接项目自有服务器，也不会把用户数据写入仓库。
- Management Key 会作为 Bearer Token 发送到用户配置的节点。使用 HTTP 时，这些
  数据没有传输层加密。
- 应用允许用户配置任意 HTTP(S) 地址，因此应将节点地址视为受信任配置。恶意节点
  可以返回伪造内容或记录所有发送给它的管理请求。
- 账号额度功能通过节点的 Management `api-call` 接口请求上游服务。OAuth Token
  由节点代入，不返回给 GUI；节点本身仍然持有并使用这些高敏感凭证。
- CAP Token Usage Tracker 的资源端点是否需要认证由插件和节点配置决定。将节点暴露
  到公网前，应验证这些端点不会泄露请求和用量明细。
- 应用不会绕过系统 TLS 验证，也不接受不受信任的证书。

## Deployment recommendations

- 公网和不可信网络始终使用有效证书的 HTTPS。
- 使用随机且唯一的 Management Key，不要与客户端 API Key 共用。
- 用防火墙、VPN 或反向代理限制 Management API 的来源地址。
- 仅在需要时启用远程管理，并及时升级 CLIProxyAPI 和插件。
- 分享截图、Issue 或日志前，删除域名、邮箱、请求内容、密钥和认证文件名。
