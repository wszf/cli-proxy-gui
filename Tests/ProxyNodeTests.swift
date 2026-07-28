import XCTest
@testable import CLIProxyGUI

final class ProxyNodeTests: XCTestCase {
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
          "routing-strategy": "round-robin"
        }
        """.utf8))
        XCTAssertEqual(JSONMetrics.arrayCount(keys: ["api-keys"], in: config), 2)
        XCTAssertEqual(JSONMetrics.providerCount(in: config), 3)
        XCTAssertEqual(JSONMetrics.string(keys: ["routing-strategy"], in: config), "round-robin")
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
