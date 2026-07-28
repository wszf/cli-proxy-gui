import XCTest
@testable import CLIProxyGUI

final class ProxyNodeTests: XCTestCase {
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
