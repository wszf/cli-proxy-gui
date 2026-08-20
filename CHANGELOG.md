# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构，
版本号使用语义化版本。

## Unreleased

## 0.7.3 - 2026-08-20

### Added

- API Keys 页面支持为每个 Key 添加备注，备注仅保存于本机，不写入 CLIProxyAPI 后台。

## 0.7.2 - 2026-08-06

### Fixed

- 修正 Codex 缓存命中率分母重复计入缓存 Token 的问题，与 cap-token-usage-tracker v1.3.1 的统计口径保持一致。

## 0.7.1 - 2026-08-05

### Added

- 模型价格页面展示插件同步的服务等级价格，请求明细区分请求 Tier 与实际计价 Tier。

### Fixed

- 适配 cap-token-usage-tracker v1.3.2 的 `service_tiers` 价格簿，客户端同步与手工保存不再丢失 priority 等等级价格。

## 0.7.0 - 2026-08-04

### Added

- API Keys 页面新增 Claude Code、Codex、模型查询与 API 测试示例，支持按 Key 生成并一键复制。
- 概览页面展示 `/v1/models` 返回的具体模型，并按 GPT、Claude、Kimi 等提供方分组。
- 客户端配置示例的 API Key 选择器增加序号，便于区分多个脱敏 Key。
- Token 用量页面新增模型价格管理，可编辑 Input、Output、缓存价格，并从 Models.dev 同步当前模型价格。
- Token 用量页面新增费用、模型占比和效率图表，以及可交互的汇总指标卡。
- 请求明细补齐来源、Tier、延迟、TPS、缓存、价格等 18 个字段，并支持列设置、排序与分页。
- 账号额度卡片新增本地自动更新的重置倒计时。

### Fixed

- Models.dev 同步在 VPS 返回 502/504 时自动切换为客户端获取目录，适配无法访问外网的部署节点。
- 兼容价格同步接口返回空映射的情况。
- 修复图表悬浮明细缺失、提示卡遮挡及裁剪问题。

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
