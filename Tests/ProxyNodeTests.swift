import XCTest
@testable import CLIProxyGUI

final class ProxyNodeTests: XCTestCase {
    func testManagementKeyVaultRoundTrip() throws {
        let firstNodeID = UUID()
        let secondNodeID = UUID()
        var vault = ManagementKeyVault()
        vault[firstNodeID] = "first-key"
        vault[secondNodeID] = "second-key"

        let data = try JSONEncoder().encode(vault)
        var decoded = try JSONDecoder().decode(ManagementKeyVault.self, from: data)

        XCTAssertEqual(decoded.version, ManagementKeyVault.currentVersion)
        XCTAssertEqual(decoded[firstNodeID], "first-key")
        XCTAssertEqual(decoded[secondNodeID], "second-key")

        decoded[firstNodeID] = nil
        XCTAssertNil(decoded[firstNodeID])
        XCTAssertEqual(decoded[secondNodeID], "second-key")
    }

    func testSingleInstanceLockExcludesSecondOwnerAndReleases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        var first: SingleInstanceLock? = SingleInstanceLock(
            identifier: "single-instance-test",
            directory: directory
        )
        let second = SingleInstanceLock(
            identifier: "single-instance-test",
            directory: directory
        )

        XCTAssertTrue(first?.acquire() == true)
        XCTAssertFalse(second.acquire())

        first = nil
        XCTAssertTrue(second.acquire())
    }

    func testNormalizesCommonManagementAddresses() {
        XCTAssertEqual(
            ProxyNode.normalize("example.com:8317/v0/management/"),
            "http://example.com:8317"
        )
        XCTAssertEqual(
            ProxyNode.normalize("https://example.com/management.html"),
            "https://example.com"
        )
    }

    func testBuildsManagementURL() {
        let node = ProxyNode(name: "Test", address: "https://example.com:8317")
        XCTAssertEqual(
            node.managementBaseURL?.absoluteString,
            "https://example.com:8317/v0/management"
        )
    }

    func testBuildsClaudeCodeConfigurationExample() {
        let example = ClientConfigurationExamples.claudeCode(
            nodeAddress: "https://proxy.example.com/",
            apiKey: "sk-test"
        )

        XCTAssertTrue(example.contains("ANTHROPIC_BASE_URL='https://proxy.example.com'"))
        XCTAssertTrue(example.contains("ANTHROPIC_AUTH_TOKEN='sk-test'"))
        XCTAssertTrue(example.hasSuffix("claude"))
    }

    func testBuildsCodexConfigurationExample() {
        let config = ClientConfigurationExamples.codexConfig(
            nodeAddress: "proxy.example.com:8317",
            apiKey: "key-with-\"quote"
        )

        XCTAssertTrue(config.contains("model_provider = \"cliproxyapi\""))
        XCTAssertTrue(config.contains("model = \"gpt-5.6-sol\""))
        XCTAssertTrue(config.contains("model_reasoning_effort = \"xhigh\""))
        XCTAssertTrue(config.contains("plan_mode_reasoning_effort = \"xhigh\""))
        XCTAssertTrue(config.contains("base_url = \"http://proxy.example.com:8317/v1\""))
        XCTAssertTrue(config.contains("wire_api = \"responses\""))
        XCTAssertTrue(config.contains("experimental_bearer_token = \"key-with-\\\"quote\""))
        XCTAssertTrue(config.contains("stream_idle_timeout_ms = 900000"))
    }

    func testBuildsModelAndAPIExamples() {
        let models = ClientConfigurationExamples.availableModels(
            nodeAddress: "https://proxy.example.com/",
            apiKey: "key-with-'quote"
        )
        let responses = ClientConfigurationExamples.responsesRequest(
            nodeAddress: "https://proxy.example.com/",
            apiKey: "sk-test"
        )
        let claude = ClientConfigurationExamples.claudeMessagesRequest(
            nodeAddress: "https://proxy.example.com/",
            apiKey: "sk-test"
        )

        XCTAssertTrue(models.contains("'https://proxy.example.com/v1/models'"))
        XCTAssertTrue(models.contains("'Authorization: Bearer key-with-'\"'\"'quote'"))
        XCTAssertTrue(models.contains("jq -r '.data[].id'"))
        XCTAssertTrue(responses.contains("'https://proxy.example.com/v1/responses'"))
        XCTAssertTrue(responses.contains("\"model\": \"gpt-5.6-sol\""))
        XCTAssertTrue(claude.contains("'https://proxy.example.com/v1/messages'"))
        XCTAssertTrue(claude.contains("'anthropic-version: 2023-06-01'"))
        XCTAssertTrue(claude.contains("\"model\": \"claude-sonnet-4-6\""))
    }

    func testExtractsDashboardMetrics() throws {
        let config = try JSONSerialization.jsonObject(with: Data("""
        {
          "api-keys": ["a", "b"],
          "codex-api-key": [{}, {}],
          "openai-compatibility": [{}],
          "debug": true,
          "request-log": false,
          "logging-to-file": true,
          "usage-statistics-enabled": true,
          "proxy-url": "http://proxy.internal:8080",
          "request-retry": 3,
          "tls": {"enable": true},
          "routing-strategy": "round-robin"
        }
        """.utf8))
        XCTAssertEqual(JSONMetrics.arrayCount(keys: ["api-keys"], in: config), 2)
        XCTAssertEqual(JSONMetrics.providerCount(in: config), 3)
        XCTAssertEqual(JSONMetrics.string(keys: ["routing-strategy"], in: config), "round-robin")

        let runtime = JSONMetrics.runtimeOverview(in: config)
        XCTAssertEqual(runtime.debug, true)
        XCTAssertEqual(runtime.requestLogging, false)
        XCTAssertEqual(runtime.fileLogging, true)
        XCTAssertEqual(runtime.usageStatistics, true)
        XCTAssertEqual(runtime.tlsEnabled, true)
        XCTAssertEqual(runtime.proxyConfigured, true)
        XCTAssertEqual(runtime.requestRetry, 3)
    }

    func testGroupsAvailableModelsByProviderFamily() throws {
        let response = try JSONSerialization.jsonObject(with: Data("""
        {
          "data": [
            {"id": "gpt-5.6-sol", "display_name": "GPT 5.6 Sol"},
            {"id": "o3"},
            {"id": "claude-sonnet-4-6"},
            {"id": "kimi-k2.7-code", "alias": "Kimi Code"},
            {"id": "custom-model"},
            {"id": "gpt-5.6-sol"}
          ]
        }
        """.utf8))

        let groups = JSONMetrics.availableModelGroups(in: response)

        XCTAssertEqual(groups.map(\.label), ["GPT", "Claude", "Kimi", "其他"])
        XCTAssertEqual(groups[0].models.map(\.name), ["gpt-5.6-sol", "o3"])
        XCTAssertEqual(groups[0].models.first?.alias, "GPT 5.6 Sol")
        XCTAssertEqual(groups[1].models.map(\.name), ["claude-sonnet-4-6"])
        XCTAssertEqual(groups[2].models.first?.alias, "Kimi Code")
        XCTAssertEqual(groups[3].models.map(\.name), ["custom-model"])
    }

    func testExtractsCredentialHealth() throws {
        let authFiles = try JSONSerialization.jsonObject(with: Data("""
        {
          "files": [
            {"type": "codex", "disabled": false, "unavailable": false},
            {"provider": "codex", "disabled": true, "unavailable": false},
            {"type": "claude", "disabled": false, "unavailable": true}
          ]
        }
        """.utf8))

        let health = JSONMetrics.credentialHealth(in: authFiles)
        XCTAssertEqual(health.total, 3)
        XCTAssertEqual(health.available, 1)
        XCTAssertEqual(health.disabled, 1)
        XCTAssertEqual(health.unavailable, 1)
        XCTAssertEqual(health.providers.count, 2)
        XCTAssertEqual(health.providers.first(where: { $0.provider == "codex" })?.total, 2)
        XCTAssertEqual(health.providers.first(where: { $0.provider == "claude" })?.unavailable, 1)
    }

    func testExtractsCredentialQuotaTargets() throws {
        let authFiles = try JSONSerialization.jsonObject(with: Data("""
        {
          "files": [
            {
              "name": "codex.json",
              "type": "codex",
              "auth_index": "codex-1",
              "email": "me@example.com",
              "id_token": {
                "https://api.openai.com/auth": {
                  "chatgpt_account_id": "account-1",
                  "chatgpt_plan_type": "plus"
                }
              }
            },
            {
              "name": "disabled.json",
              "type": "claude",
              "auth_index": "claude-1",
              "disabled": true
            },
            {
              "name": "unsupported.json",
              "type": "gemini",
              "auth_index": "gemini-1"
            }
          ]
        }
        """.utf8))

        let targets = CredentialQuotaParser.targets(in: authFiles)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets[0].account, "me@example.com")
        XCTAssertEqual(targets[0].accountID, "account-1")
        XCTAssertEqual(targets[0].plan, "plus")
    }

    func testParsesCodexQuotaWindows() throws {
        let payload = try JSONSerialization.jsonObject(with: Data("""
        {
          "plan_type": "plus",
          "rate_limit": {
            "primary_window": {
              "used_percent": 25,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 3600
            },
            "secondary_window": {
              "used_percent": 70,
              "limit_window_seconds": 604800,
              "reset_at": 1800000000
            }
          }
        }
        """.utf8))
        let target = CredentialQuotaTarget(
            id: "codex-1",
            authIndex: "codex-1",
            provider: "codex",
            account: "me@example.com",
            accountID: nil,
            plan: nil
        )

        let summary = CredentialQuotaParser.summary(target: target, payload: payload)
        XCTAssertEqual(summary.plan, "plus")
        XCTAssertEqual(summary.windows.map(\.label), ["5 小时", "每周"])
        XCTAssertEqual(summary.windows.map(\.remainingPercent), [75, 30])
        XCTAssertNotNil(summary.windows[0].resetsAt)
    }

    func testParsesClaudeAndKimiQuotaWindows() throws {
        let claude = try JSONSerialization.jsonObject(with: Data("""
        {
          "five_hour": {"utilization": 20, "resets_at": "2026-08-01T10:00:00Z"},
          "seven_day": {"utilization": 45, "resets_at": "2026-08-05T10:00:00Z"}
        }
        """.utf8))
        let kimi = try JSONSerialization.jsonObject(with: Data("""
        {
          "limits": [{
            "detail": {"name": "Weekly", "limit": 1000, "remaining": 250}
          }]
        }
        """.utf8))
        let claudeTarget = CredentialQuotaTarget(
            id: "claude-1",
            authIndex: "claude-1",
            provider: "claude",
            account: "Claude",
            accountID: nil,
            plan: nil
        )
        let kimiTarget = CredentialQuotaTarget(
            id: "kimi-1",
            authIndex: "kimi-1",
            provider: "kimi",
            account: "Kimi",
            accountID: nil,
            plan: nil
        )

        let claudeSummary = CredentialQuotaParser.summary(target: claudeTarget, payload: claude)
        let kimiSummary = CredentialQuotaParser.summary(target: kimiTarget, payload: kimi)
        XCTAssertEqual(claudeSummary.windows.map(\.remainingPercent), [80, 55])
        XCTAssertEqual(kimiSummary.windows.first?.remainingPercent, 25)
    }

    func testExtractsPluginOverview() throws {
        let plugins = try JSONSerialization.jsonObject(with: Data("""
        {
          "plugins_enabled": true,
          "plugins": [
            {"id": "cap-token-usage-tracker", "effective_enabled": true},
            {"id": "another-plugin", "effective_enabled": false}
          ]
        }
        """.utf8))

        let overview = try XCTUnwrap(JSONMetrics.pluginOverview(in: plugins))
        XCTAssertTrue(overview.globallyEnabled)
        XCTAssertEqual(overview.installed, 2)
        XCTAssertEqual(overview.active, 1)
        XCTAssertTrue(overview.tokenTrackerActive)
    }

    func testVersionComparison() {
        XCTAssertTrue(VersionComparison.isNewer("v7.2.0", than: "7.1.9"))
        XCTAssertFalse(VersionComparison.isNewer("7.2.0", than: "v7.2.0"))
        XCTAssertFalse(VersionComparison.isNewer("7.1.9", than: "7.2.0"))
        XCTAssertTrue(VersionComparison.isNewer("7.2.0-beta.1", than: "7.1.9"))
    }

    func testDecodesTokenUsagePluginResponse() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let snapshot = try decoder.decode(TokenUsageSnapshot.self, from: Data("""
        {
          "schema_version": 1,
          "generated_at": "2026-07-28T10:00:00Z",
          "range": "24h",
          "retained_since": "2026-07-01T00:00:00Z",
          "last_used": "2026-07-28T09:59:00Z",
          "summary": {
            "requests": 3,
            "failed_requests": 1,
            "input_tokens": 100,
            "output_tokens": 50,
            "reasoning_tokens": 20,
            "cached_tokens": 10,
            "cache_read_tokens": 8,
            "cache_creation_tokens": 2,
            "total_tokens": 170,
            "total_latency_ns": 3000000000,
            "total_ttft_ns": 600000000,
            "latency_samples": 3,
            "ttft_samples": 2
          },
          "groups": [],
          "series": [{
            "hour": "2026-07-28T09:00:00Z",
            "requests": 3,
            "failed_requests": 1,
            "input_tokens": 100,
            "output_tokens": 50,
            "reasoning_tokens": 20,
            "cached_tokens": 10,
            "cache_read_tokens": 8,
            "cache_creation_tokens": 2,
            "total_tokens": 170,
            "total_latency_ns": 3000000000,
            "total_ttft_ns": 600000000,
            "latency_samples": 3,
            "ttft_samples": 2
          }]
        }
        """.utf8))

        XCTAssertEqual(snapshot.summary.totalTokens, 170)
        XCTAssertEqual(snapshot.summary.totalTTFTNS, 600_000_000)
        XCTAssertEqual(snapshot.series.first?.totalLatencyNS, 3_000_000_000)
    }

    func testDecodesTokenUsageCostSeries() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let costs = try decoder.decode(TokenUsageCosts.self, from: Data("""
        {
          "schema_version": 1,
          "generated_at": "2026-08-04T06:47:12Z",
          "range": "24h",
          "currency": "USD",
          "estimate_basis": "current_price_book",
          "price_book_revision": 2,
          "summary": {
            "requests": 2,
            "priced_requests": 2,
            "unpriced_requests": 0,
            "input_usd": 1.25,
            "output_usd": 2.5,
            "cache_read_usd": 0.5,
            "cache_creation_usd": 0,
            "total_usd": 4.25
          },
          "models": [{
            "provider": "claude",
            "model": "kimi-k3",
            "requests": 2,
            "priced_requests": 2,
            "unpriced_requests": 0,
            "input_usd": 1.25,
            "output_usd": 2.5,
            "cache_read_usd": 0.5,
            "cache_creation_usd": 0,
            "total_usd": 4.25
          }],
          "series": [{
            "hour": "2026-08-04T06:00:00Z",
            "provider": "claude",
            "model": "kimi-k3",
            "requests": 2,
            "priced_requests": 2,
            "unpriced_requests": 0,
            "input_usd": 1.25,
            "output_usd": 2.5,
            "cache_read_usd": 0.5,
            "cache_creation_usd": 0,
            "total_usd": 4.25
          }]
        }
        """.utf8))

        XCTAssertEqual(costs.priceBookRevision, 2)
        XCTAssertEqual(costs.summary.totalUSD, 4.25)
        XCTAssertEqual(costs.models.first?.model, "kimi-k3")
        XCTAssertEqual(costs.series.first?.totalUSD, 4.25)
    }

    func testDecodesTokenUsageExchangeRate() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rate = try decoder.decode(TokenUsageExchangeRate.self, from: Data("""
        {
          "schema_version": 1,
          "base": "USD",
          "quote": "CNY",
          "rate": 6.765857,
          "effective_at": "2026-08-04T00:02:31Z",
          "fetched_at": "2026-08-04T07:36:32Z",
          "source": "open.er-api.com",
          "stale": false
        }
        """.utf8))

        XCTAssertEqual(rate.base, "USD")
        XCTAssertEqual(rate.quote, "CNY")
        XCTAssertEqual(rate.rate, 6.765857, accuracy: 0.000001)
        XCTAssertFalse(rate.stale)
    }

    func testDecodesTokenUsagePriceBook() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let book = try decoder.decode(TokenUsagePriceBook.self, from: Data("""
        {
          "schema_version": 1,
          "revision": 3,
          "prices": {
            "claude-sonnet-4-6": {
              "input": 3,
              "output": 15,
              "cache_read": 0.3,
              "cache_creation": 3.75,
              "context_tiers": [{
                "threshold": 200000,
                "input": 6,
                "output": 22.5,
                "cache_read": 0.6,
                "cache_creation": 4.5
              }],
              "source": "models.dev",
              "catalog_provider": "anthropic",
              "catalog_model": "claude-sonnet-4-6"
            }
          },
          "sync_settings": {
            "provider_priority": ["openai", "anthropic"],
            "ignored_suffixes": ["-preview"],
            "mappings": []
          }
        }
        """.utf8))

        let price = try XCTUnwrap(book.prices["claude-sonnet-4-6"])
        XCTAssertEqual(book.revision, 3)
        XCTAssertEqual(price.input, 3)
        XCTAssertEqual(price.cacheCreation, 3.75)
        XCTAssertEqual(price.contextTiers.first?.threshold, 200_000)
        XCTAssertEqual(price.source, "models.dev")
        XCTAssertEqual(book.syncSettings.providerPriority, ["openai", "anthropic"])
    }

    func testDecodesTokenUsagePriceBookWithNullMappings() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let book = try decoder.decode(TokenUsagePriceBook.self, from: Data("""
        {
          "schema_version": 2,
          "revision": 2,
          "prices": {
            "kimi-k2": {
              "input": 0.575,
              "output": 2.3,
              "cache_read": 0,
              "cache_creation": 0,
              "source": "models.dev",
              "catalog_provider": "302ai",
              "catalog_model": "kimi-k2-thinking",
              "updated_at": "2026-08-01T18:22:17.955061908Z"
            }
          },
          "sync_settings": {
            "provider_priority": ["openai", "google", "anthropic"],
            "ignored_suffixes": ["-thinking"],
            "mappings": null
          },
          "last_sync": {
            "source": "models.dev",
            "completed_at": "2026-08-01T18:22:17.955061908Z",
            "observed": 8,
            "matched": 7,
            "created": 0,
            "updated": 7,
            "skipped_manual": 0,
            "unmatched": 1
          }
        }
        """.utf8))

        XCTAssertEqual(book.schemaVersion, 2)
        XCTAssertEqual(book.prices["kimi-k2"]?.input, 0.575)
        XCTAssertTrue(book.syncSettings.mappings.isEmpty)
        XCTAssertEqual(book.lastSync?.matched, 7)
    }

    func testMatchesModelsDevPricesWithProviderPriorityAndContextTier() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let catalog = try decoder.decode([String: ModelsDevCatalogProvider].self, from: Data("""
        {
          "openai": {
            "id": "openai",
            "models": {
              "gpt-5": {
                "id": "gpt-5",
                "cost": {
                  "input": 1,
                  "output": 5,
                  "cache_read": 0.1,
                  "cache_write": 2,
                  "tiers": [{
                    "input": 2,
                    "output": 8,
                    "cache_read": 0.2,
                    "cache_write": 3,
                    "tier": {"type": "context", "size": 200000}
                  }]
                }
              }
            }
          },
          "other": {
            "id": "other",
            "models": {
              "vendor/gpt-5": {
                "id": "vendor/gpt-5",
                "cost": {"input": 9, "output": 9}
              }
            }
          }
        }
        """.utf8))

        let result = ModelsDevPriceMatcher.match(
            catalog: catalog,
            models: ["gpt-5-high", "gpt-5"],
            settings: PriceSyncSettings(),
            updatedAt: "2026-08-02T00:00:00Z"
        )

        XCTAssertEqual(result.observed, 2)
        XCTAssertEqual(result.matched, 2)
        XCTAssertEqual(result.unmatched, 0)
        XCTAssertEqual(result.prices["gpt-5-high"]?.input, 1)
        XCTAssertEqual(result.prices["gpt-5-high"]?.catalogProvider, "openai")
        XCTAssertEqual(result.prices["gpt-5-high"]?.contextTiers.first?.threshold, 200_000)
    }

    func testAggregatesUsageByModel() {
        let first = usageGroup(model: "gpt-5", provider: "openai", requests: 2, tokens: 100)
        let second = usageGroup(model: "gpt-5", provider: "azure", requests: 1, tokens: 50)
        let rows = ModelUsageRow.aggregate([first, second])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].model, "gpt-5")
        XCTAssertEqual(rows[0].provider, "azure, openai")
        XCTAssertEqual(rows[0].requests, 3)
        XCTAssertEqual(rows[0].totalTokens, 150)
    }

    func testFiltersUsageDimensions() {
        let group = usageGroup(model: "gpt-5", provider: "openai", requests: 2, tokens: 100)

        XCTAssertTrue(group.matchesDimensionQuery(""))
        XCTAssertTrue(group.matchesDimensionQuery("GPT-5"))
        XCTAssertTrue(group.matchesDimensionQuery("openai"))
        XCTAssertTrue(group.matchesDimensionQuery("成功"))
        XCTAssertFalse(group.matchesDimensionQuery("anthropic"))
    }

    func testUsageRequestPaginationState() {
        let firstPage = UsageRequestPage(total: 120, offset: 0, limit: 50, items: [])
        let emptyLastPage = UsageRequestPage(total: 100, offset: 100, limit: 50, items: [])

        XCTAssertFalse(firstPage.hasPreviousPage)
        XCTAssertTrue(firstPage.hasNextPage)
        XCTAssertNil(firstPage.displayedRange)
        XCTAssertTrue(emptyLastPage.hasPreviousPage)
        XCTAssertFalse(emptyLastPage.hasNextPage)
    }

    private func usageGroup(
        model: String,
        provider: String,
        requests: UInt64,
        tokens: UInt64
    ) -> UsageGroup {
        UsageGroup(
            provider: provider,
            executorType: "",
            model: model,
            alias: "",
            source: "",
            authType: "",
            serviceTier: "",
            reasoningEffort: "",
            failed: false,
            failureStatus: 0,
            requests: requests,
            failedRequests: 0,
            inputTokens: tokens,
            outputTokens: 0,
            reasoningTokens: 0,
            cachedTokens: 0,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            totalTokens: tokens,
            totalLatencyNS: 0,
            totalTTFTNS: 0,
            latencySamples: 0,
            ttftSamples: 0,
            averageLatencyNS: 0,
            averageTTFTNS: 0
        )
    }
}
