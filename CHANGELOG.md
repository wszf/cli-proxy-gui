# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构，
版本号使用语义化版本。

## Unreleased

### Added

- API Keys 页面新增 Claude Code、Codex、模型查询与 API 测试示例，支持按 Key 生成并一键复制。
- 概览页面展示 `/v1/models` 返回的具体模型，并按 GPT、Claude、Kimi 等提供方分组。

## 0.6.2 - 2026-07-29

### Added

- 开源项目文档、贡献规范、安全策略和持续集成。
- 通过 Git 标签自动构建通用 macOS 应用并发布 GitHub Release。

### Fixed

- 将多个节点的 Management Key 合并到一个钥匙串条目，避免启动时按节点重复弹出授权。

## 0.6.1 - 2026-07-29

### Added

- 多节点 Management API 管理。
- 配置、API Keys、认证文件和日志页面。
- CAP Token Usage Tracker 趋势、维度和请求分页。
- 节点概览、凭证健康和 Codex、Claude、Kimi 账号额度。
- Management Key 的 macOS Keychain 存储。
- 单实例运行和原生应用图标。

### Changed

- 账号额度采用并发查询，并限制为每个节点至少间隔 3 分钟。
