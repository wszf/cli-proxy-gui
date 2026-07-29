# Releasing

本文件供项目维护者发布新版本时使用。

## 发布前

1. 确认工作区干净，默认分支已经同步。
2. 更新 `project.yml` 中的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
3. 运行 `xcodegen generate`，提交生成后的 Xcode 工程。
4. 把 Unreleased 内容整理到 `CHANGELOG.md` 的新版本标题下。
5. 运行 `./Scripts/ci.sh`。
6. 检查应用内版本、图标、隐私清单和 HTTP 安全提示。
7. 使用不含个人节点和凭证的 macOS 账户做一次基本操作检查。

## 构建发行包

推送与版本一致的 `vX.Y.Z` 标签后，`.github/workflows/release.yml` 会运行测试，
构建 arm64 和 x86_64 通用应用，并创建带有 SHA-256 校验文件的 GitHub Release：

```bash
git tag -a v0.7.0 -m "CLIProxy GUI v0.7.0"
git push origin v0.7.0
```

当前自动化产物使用临时签名，适用于公开测试，但未经过 Apple 公证。

公开分发的 macOS 应用应使用 Developer ID Application 证书签名，并提交 Apple
Notary Service 公证。签名身份、Team ID 和公证凭证属于维护者私密配置，不应写入
仓库或 GitHub Actions 日志。

建议通过 Xcode 的 **Product → Archive** 创建 Release 归档，再执行签名、公证和
Staple。不要把未签名的本地 Debug 构建作为正式发行包。

## 发布

1. 为提交创建签名标签，例如 `v0.7.0`。
2. 创建 GitHub Release，标题与标签一致。
3. 附上签名、公证后的 ZIP 或 DMG，以及 SHA-256 校验值。
4. Release Notes 摘要引用 `CHANGELOG.md`，并明确不兼容变化。
5. 在一台未安装开发证书的 Mac 上下载并验证最终附件。

## 仓库首次公开前

- 设置仓库描述、项目主页和 `macos`、`swiftui`、`cliproxyapi` 等 Topics。
- 启用 Issues、GitHub Actions、Dependabot 和 Private vulnerability reporting。
- 保护默认分支，要求 CI 通过后才能合并。
- 确认公开 Git 历史没有真实凭证、节点地址、账号数据或大体积构建产物。
- 如需提供支持邮箱或其他私密报告方式，更新 `SECURITY.md`。
