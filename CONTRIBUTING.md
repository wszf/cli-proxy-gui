# Contributing

感谢你参与 CLIProxy GUI。

## 开始之前

- Bug、兼容性问题和小型改进可以直接提交 Pull Request。
- 大型功能、数据模型变化或 Management API 假设变化，请先开 Issue 对齐范围。
- 安全问题不要提交公开 Issue，请按 [SECURITY.md](SECURITY.md) 私下报告。

## 开发环境

- macOS 14 或更高版本
- Xcode 26
- XcodeGen 2.45 或兼容版本（仅在修改 `project.yml` 时需要）

仓库已包含 Xcode 工程。修改代码后运行：

```bash
./Scripts/ci.sh
```

修改 `project.yml` 后还需运行：

```bash
xcodegen generate
git diff --check
```

## 提交要求

- 保持改动聚焦，一个提交对应一个完整功能或修复。
- 推荐使用 `feat:`、`fix:`、`docs:`、`test:`、`chore:` 等提交前缀。
- 新行为应尽量补充测试。
- UI 文案目前使用简体中文；新增文案请保持用词一致。
- 不要提交真实节点地址、Management Key、API Key、认证文件、日志或账号信息。
- 测试数据使用 `example.com` 和明显的占位值。
- 不要提交 `DerivedData/`、`.build/`、`build/` 或个人 Xcode 配置。

## Pull Request

请在描述中说明：

1. 解决的问题。
2. 主要实现和兼容性影响。
3. 验证方式。
4. 涉及界面时提供已脱敏的截图。

提交贡献即表示你同意按项目的 MIT License 发布你的贡献。

维护者发布版本时请参考 [docs/RELEASING.md](docs/RELEASING.md)。
