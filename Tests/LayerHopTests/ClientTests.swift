import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LayerHop

let quoteJSON = #"{"best":{"quoteId":"q_1","provider":"relay","dstAmount":"612345678","dstAmountMin":"609283949","estimatedSeconds":8,"fees":{"ourFeeBps":20,"providerFeeUsd":0.12,"integratorFeeBps":10,"integrator":"myapp"},"expiresAt":1760000030},"quotes":[{"quoteId":"q_1","provider":"relay","dstAmount":"612345678","dstAmountMin":"609283949","estimatedSeconds":8,"fees":{"ourFeeBps":20},"expiresAt":1760000030}],"errors":[{"provider":"lifi","code":"PROVIDER_TIMEOUT","message":"Timed out"}]}"#

final class ClientTests: MockTestCase {
    func testDefaults() {
        let c = LayerHopClient()
        XCTAssertEqual(c.baseURL, "https://api.layerhop.com")
        XCTAssertEqual(c.options.channel, "api")
        XCTAssertEqual(c.options.userAgent, "layerhop-swift/0.6.0")
        XCTAssertEqual(LayerHop.version, "0.6.0")
        XCTAssertNil(c.options.apiKey)

        let c2 = LayerHopClient(apiKey: "", baseURL: "https://x.test///", channel: "", userAgent: "")
        XCTAssertEqual(c2.baseURL, "https://x.test")
        XCTAssertEqual(c2.options.channel, "api")
        XCTAssertEqual(c2.options.userAgent, LayerHop.defaultUserAgent)
        XCTAssertNil(c2.options.apiKey)
    }

    func testHealthChainsTokens() async throws {
        respond(#"{"ok":true,"providers":["relay","mock"]}"#)
        let h = try await client.health()
        XCTAssertTrue(h.ok)
        XCTAssertEqual(h.providers, ["relay", "mock"])
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.url.absoluteString, "https://api.test/v1/health")
        XCTAssertEqual(last.header("x-api-key"), "k1")
        XCTAssertEqual(last.header("user-agent"), "layerhop-swift/0.6.0")
        XCTAssertEqual(last.header("accept"), "application/json")
        XCTAssertNil(last.header("content-type"))

        respond(#"{"chains":[{"id":7565164,"slug":"solana","name":"Solana","vm":"svm","nativeSymbol":"SOL","nativeDecimals":9,"explorerTx":"https://solscan.io/tx/"}]}"#)
        let ch = try await client.chains()
        XCTAssertEqual(ch.count, 1)
        XCTAssertEqual(ch[0].id, LayerHop.solanaChainID)
        XCTAssertEqual(ch[0].vm, "svm")
        XCTAssertEqual(last.rawPath, "/v1/chains")

        respond(#"{"tokens":[{"chainId":8453,"address":"0x83","symbol":"USDC","decimals":6}]}"#)
        let tk = try await client.tokens(chain: "base")
        XCTAssertEqual(tk[0].symbol, "USDC")
        XCTAssertEqual(tk[0].decimals, 6)
        XCTAssertEqual(last.query, "chain=base")
    }

    func testNoAPIKeyHeaderWithoutKey() async throws {
        client = makeClient(.init(baseURL: "https://api.test"))
        respond(#"{"ok":true}"#)
        _ = try await client.health()
        XCTAssertNil(last.header("x-api-key"))
    }

    func testQuote() async throws {
        client = makeClient(.init(baseURL: "https://api.test", apiKey: "k1", integrator: "myapp", integratorFeeBps: 25))
        respond(quoteJSON)
        let q = try await client.quote(QuoteParams(
            srcChain: "base", srcToken: "USDC", amount: "100000000", dstChain: "solana", dstToken: "SOL",
            sender: "0xabc", recipient: "9Wz"))
        XCTAssertEqual(q.best.quoteId, "q_1")
        XCTAssertEqual(q.best.dstAmount, "612345678")
        XCTAssertEqual(q.best.fees.integratorFeeBps, 10)
        XCTAssertEqual(q.best.fees.providerFeeUsd, 0.12)
        XCTAssertNil(q.best.gasOnArrival)
        XCTAssertEqual(q.errors?.count, 1)
        XCTAssertEqual(q.errors?[0].code, "PROVIDER_TIMEOUT")
        XCTAssertNil(q.livemode)
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/quote")
        XCTAssertEqual(
            last.query,
            "amount=100000000&channel=api&dstChain=solana&dstToken=SOL&integrator=myapp&integratorFeeBps=25&recipient=9Wz&sender=0xabc&slippageBps=50&srcChain=base&srcToken=USDC")
    }

    func testQuoteEscapesAndSlippage() async throws {
        client = makeClient(.init(baseURL: "https://api.test", channel: "widget"))
        respond(quoteJSON)
        _ = try await client.quote(QuoteParams(
            srcChain: "8453", srcToken: "a b&c", amount: "1", dstChain: "solana", dstToken: "SOL",
            sender: "0x1", recipient: "r", slippageBps: 100))
        XCTAssertTrue(last.query.contains("srcToken=a%20b%26c"), last.query)
        XCTAssertTrue(last.query.contains("slippageBps=100"))
        XCTAssertTrue(last.query.contains("channel=widget"))
        XCTAssertFalse(last.query.contains("integrator"))
    }

    func testQuoteGasOnArrival() async throws {
        let resp = quoteJSON.replacingOccurrences(
            of: #""expiresAt":1760000030},"quotes""#,
            with: #""expiresAt":1760000030,"gasOnArrival":{"amount":"512000000000000","token":"0x0000000000000000000000000000000000000000","symbol":"ETH","decimals":18,"usd":2}},"quotes""#)
        respond(resp)
        var p = QuoteParams(
            srcChain: "solana", srcToken: "USDC", amount: "100000000", dstChain: "base", dstToken: "USDC",
            sender: "9Wz", recipient: "0xabc", gasOnArrival: true)
        let q = try await client.quote(p)
        let g = try XCTUnwrap(q.best.gasOnArrival)
        XCTAssertEqual(g.amount, "512000000000000")
        XCTAssertEqual(g.symbol, "ETH")
        XCTAssertEqual(g.decimals, 18)
        XCTAssertEqual(g.usd, 2)
        XCTAssertNil(q.quotes[0].gasOnArrival)
        XCTAssertTrue(last.query.contains("&gasOnArrival=true&"), last.query)
        XCTAssertFalse(last.query.contains("gasOnArrivalUsd"))

        p.gasOnArrivalUsd = 5.5
        _ = try await client.quote(p)
        XCTAssertTrue(last.query.contains("&gasOnArrivalUsd=5.5&"), last.query)
        XCTAssertFalse(last.query.contains("gasOnArrival="))

        p.gasOnArrivalUsd = 2
        _ = try await client.quote(p)
        XCTAssertTrue(last.query.contains("&gasOnArrivalUsd=2&"), last.query)

        p.gasOnArrival = false
        p.gasOnArrivalUsd = nil
        _ = try await client.quote(p)
        XCTAssertFalse(last.query.contains("gasOnArrival"))
    }

    func testBuildTxEvm() async throws {
        respond(#"{"quoteId":"q_1","provider":"relay","tx":{"vm":"evm","chainId":8453,"to":"0xto","data":"0xdead","value":"0","approval":{"token":"0xt","spender":"0xs","amount":"100"},"extraTxs":[{"to":"0xfee","data":"0xa9059cbb","value":"0"}]}}"#)
        let tx = try await client.buildTx(quoteId: "q_1")
        XCTAssertTrue(tx.isEVM)
        XCTAssertFalse(tx.isSVM)
        XCTAssertEqual(tx.vm, "evm")
        XCTAssertFalse(tx.sandbox)
        guard case let .evm(evm) = tx else { return XCTFail("not evm") }
        XCTAssertEqual(evm.chainId, 8453)
        XCTAssertEqual(evm.to, "0xto")
        XCTAssertEqual(evm.data, "0xdead")
        XCTAssertEqual(evm.value, "0")
        XCTAssertEqual(evm.approval?.amount, "100")
        XCTAssertEqual(evm.approval?.spender, "0xs")
        XCTAssertEqual(evm.extraTxs.count, 1)
        XCTAssertEqual(evm.extraTxs[0].to, "0xfee")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/orders")
        XCTAssertEqual(last.bodyString, #"{"quoteId":"q_1"}"#)
        XCTAssertEqual(last.header("content-type"), "application/json")
    }

    func testBuildTxSvm() async throws {
        respond(#"{"quoteId":"q_2","provider":"jupiter","tx":{"vm":"svm","serializedTx":"AQID","submitViaApi":true}}"#)
        let tx = try await client.buildTx(quoteId: "q_2")
        XCTAssertTrue(tx.isSVM)
        XCTAssertNil(tx.evm)
        let svm = try XCTUnwrap(tx.svm)
        XCTAssertEqual(svm.serializedTx, "AQID")
        XCTAssertTrue(svm.submitViaApi)
        XCTAssertFalse(svm.sandbox)

        // Missing optional flags default to false; extraTxs to [].
        respond(#"{"tx":{"vm":"svm","serializedTx":"AQ=="}}"#)
        let tx2 = try await client.buildTx(quoteId: "q_3")
        XCTAssertEqual(tx2.svm?.submitViaApi, false)
        respond(#"{"tx":{"vm":"evm","chainId":1,"to":"0x1","data":"0x","value":"5","sandbox":true}}"#)
        let tx3 = try await client.buildTx(quoteId: "q_4")
        XCTAssertEqual(tx3.evm?.extraTxs, [])
        XCTAssertTrue(tx3.sandbox)
    }

    func testBuildTxUnknownVMIsDecodingError() async {
        respond(#"{"tx":{"vm":"move","payload":"x"}}"#)
        let e = await expectLayerHopError { try await self.client.buildTx(quoteId: "q") }
        guard case let .decoding(msg)? = e else { return XCTFail("\(String(describing: e))") }
        XCTAssertTrue(msg.contains("POST /orders"), msg)
    }

    func testBuiltTxRoundTrip() throws {
        let json = #"{"vm":"evm","chainId":8453,"to":"0xto","data":"0x","value":"1","approval":{"token":"0xt","spender":"0xs","amount":"2"}}"#
        let tx = try JSONDecoder().decode(BuiltTx.self, from: Data(json.utf8))
        let again = try JSONDecoder().decode(BuiltTx.self, from: JSONEncoder().encode(tx))
        XCTAssertEqual(tx, again)
        let svm = try JSONDecoder().decode(BuiltTx.self, from: Data(#"{"vm":"svm","serializedTx":"AQ","submitViaApi":true}"#.utf8))
        XCTAssertEqual(try JSONDecoder().decode(BuiltTx.self, from: JSONEncoder().encode(svm)), svm)
    }

    func testSubmit() async throws {
        respond(#"{"provider":"jupiter","txHash":"5VER"}"#)
        let h = try await client.submit(quoteId: "q_1", signedTransaction: "c2lnbmVk")
        XCTAssertEqual(h, "5VER")
        XCTAssertEqual(last.rawPath, "/v1/orders/submit")
        XCTAssertEqual(last.json["quoteId"] as? String, "q_1")
        XCTAssertEqual(last.json["signedTransaction"] as? String, "c2lnbmVk")
    }

    func testReportSubmitted() async throws {
        respond(#"{"quoteId":"q_1","status":"submitted"}"#)
        let r = try await client.reportSubmitted(quoteId: "q_1", txHash: "0xhash")
        XCTAssertEqual(r.status, "submitted")
        XCTAssertEqual(r.quoteId, "q_1")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/orders/q_1/submitted")
        XCTAssertEqual(last.bodyString, #"{"txHash":"0xhash"}"#)
    }

    func testSimulate() async throws {
        respond(#"{"ok":false,"vm":"evm","gasEstimate":"21000","needsApproval":true,"error":{"code":"SIMULATION_FAILED","message":"reverted","logs":["l1"]},"tx":{"vm":"evm","chainId":1,"to":"0x","data":"0x","value":"0"}}"#)
        let s = try await client.simulate(quoteId: "q_1")
        XCTAssertFalse(s.ok)
        XCTAssertEqual(s.gasEstimate, "21000")
        XCTAssertTrue(s.needsApproval)
        XCTAssertEqual(s.error?.logs, ["l1"])
        XCTAssertEqual(s.tx?.isEVM, true)
        XCTAssertEqual(last.rawPath, "/v1/simulate")
        XCTAssertEqual(last.bodyString, #"{"quoteId":"q_1"}"#)

        // Numeric gas / compute units are accepted too.
        respond(#"{"ok":true,"vm":"svm","computeUnits":120000,"gasEstimate":null}"#)
        let s2 = try await client.simulate(quoteId: "q_2")
        XCTAssertTrue(s2.ok)
        XCTAssertEqual(s2.computeUnits, "120000")
        XCTAssertNil(s2.gasEstimate)
        XCTAssertFalse(s2.needsApproval)
    }

    func testStatusEscapesID() async throws {
        respond(#"{"provider":"debridge","id":"a/b c","state":"filled","srcTxHash":"0x1","dstTxHash":"sig"}"#)
        let s = try await client.status(provider: "debridge", id: "a/b c")
        XCTAssertEqual(s.state, .filled)
        XCTAssertTrue(s.state.isFinal)
        XCTAssertEqual(s.dstTxHash, "sig")
        XCTAssertEqual(last.rawPath, "/v1/orders/debridge/a%2Fb%20c")
    }

    func testListOrders() async throws {
        respond(#"{"orders":[{"quoteId":"q_1","provider":"relay","status":"filled","srcChainId":8453,"amount":"100","sender":"0xabc","unknownField":{"x":1}}],"nextCursor":"c2"}"#)
        let r = try await client.listOrders(ListOrdersParams(address: "0xabc", status: "filled", cursor: "c1", limit: 10))
        XCTAssertEqual(r.orders.count, 1)
        XCTAssertEqual(r.orders[0].srcChainId, 8453)
        XCTAssertNil(r.orders[0].dstChainId)
        XCTAssertEqual(r.nextCursor, "c2")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/orders")
        XCTAssertEqual(last.query, "address=0xabc&cursor=c1&limit=10&status=filled")

        respond(#"{"orders":[]}"#)
        _ = try await client.listOrders()
        XCTAssertEqual(last.query, "")
        XCTAssertEqual(last.url.absoluteString, "https://api.test/v1/orders")
    }

    func testServiceStatus() async throws {
        respond(#"{"status":"operational","updatedAt":"t","components":[{"id":"api","name":"API","group":"core","status":"operational","latencyMs":42,"uptime90d":99.98,"days":[{"date":"2026-10-18","uptime":null}]}],"incidents":[{"id":"i1","componentId":"api","component":"API","title":"Slow","startedAt":"t","resolvedAt":null}],"url":"https://status.layerhop.com"}"#)
        let s = try await client.serviceStatus()
        XCTAssertEqual(s.status, "operational")
        XCTAssertEqual(s.components[0].latencyMs, 42)
        XCTAssertNil(s.components[0].days?[0].uptime)
        XCTAssertNil(s.incidents[0].resolvedAt)
        XCTAssertEqual(last.rawPath, "/v1/status")
    }

    // MARK: Errors

    func testAPIError() async {
        respond(status: 410, #"{"error":{"code":"QUOTE_EXPIRED","message":"Quote expired, request a new one","requestId":"req-1","docsUrl":"x"}}"#)
        let e = await expectLayerHopError { try await self.client.buildTx(quoteId: "q_old") }
        XCTAssertEqual(e, .api(code: "QUOTE_EXPIRED", message: "Quote expired, request a new one", status: 410, requestId: "req-1"))
        XCTAssertEqual(e?.code, "QUOTE_EXPIRED")
        XCTAssertEqual(e?.status, 410)
        XCTAssertEqual(e?.requestId, "req-1")
        XCTAssertEqual(e?.docsURL?.absoluteString, "https://docs.layerhop.com/errors/QUOTE_EXPIRED")
        XCTAssertTrue(e?.description.contains("QUOTE_EXPIRED") ?? false)
        XCTAssertTrue(e?.description.contains("[requestId req-1]") ?? false)
    }

    func testAPIErrorFallback() async {
        respond(status: 502, "not json")
        let e = await expectLayerHopError { try await self.client.chains() }
        XCTAssertEqual(e, .api(code: "INTERNAL", message: "Bad Gateway", status: 502, requestId: "req-hdr"))
    }

    func testDecodingError() async {
        respond(#"{"chains":"nope"}"#)
        let e = await expectLayerHopError { try await self.client.chains() }
        guard case let .decoding(msg)? = e else { return XCTFail("\(String(describing: e))") }
        XCTAssertTrue(msg.hasPrefix("decode GET /chains"), msg)
        XCTAssertNil(e?.code)
    }

    func testNetworkError() async {
        respond { _ in MockResponse(error: URLError(.notConnectedToInternet)) }
        let e = await expectLayerHopError { try await self.client.health() }
        guard case let .network(u)? = e else { return XCTFail("\(String(describing: e))") }
        XCTAssertEqual(u.code, .notConnectedToInternet)
    }

    func testCancellation() async {
        respond(#"{"ok":true}"#)
        let task = Task { () -> Health in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await self.client.health()
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    // MARK: Watch

    private func statusSequence(_ states: [String]) {
        respond { _ in
            let i = min(MockURLProtocol.state.requests.count - 1, states.count - 1)
            return MockResponse(#"{"provider":"relay","id":"0x1","state":"\#(states[i])"}"#)
        }
    }

    func testWatchYieldsChangesUntilFinal() async throws {
        statusSequence(["unknown", "pending", "pending", "filled", "pending"])
        var got: [String] = []
        for try await st in client.watch(provider: "relay", id: "0x1", interval: 0.001) {
            got.append(st.state.rawValue)
        }
        XCTAssertEqual(got, ["unknown", "pending", "filled"])
        XCTAssertEqual(requestCount, 4)
        XCTAssertEqual(last.rawPath, "/v1/orders/relay/0x1")
    }

    func testWatchBreakStopsPolling() async throws {
        statusSequence(["pending"])
        for try await _ in client.watch(provider: "relay", id: "0x1", interval: 0.3) { break }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(requestCount, 1)
    }

    func testWatchTimeout() async {
        statusSequence(["pending"])
        var yielded = 0
        do {
            for try await _ in client.watch(provider: "relay", id: "0x1", interval: 0.005, timeout: 0.02) { yielded += 1 }
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? LayerHopError, .watchTimeout)
        }
        XCTAssertEqual(yielded, 1)
    }

    func testWatchStopsOnError() async {
        respond(status: 404, #"{"error":{"code":"ORDER_NOT_FOUND","message":"nope"}}"#)
        do {
            for try await _ in client.watch(provider: "relay", id: "0x1", interval: 0.001) { XCTFail("no value expected") }
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as? LayerHopError)?.code, "ORDER_NOT_FOUND")
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testWatchTaskCancellation() async throws {
        statusSequence(["pending"])
        let c = client!
        let task = Task { () -> Int in
            var n = 0
            for try await _ in c.watch(provider: "relay", id: "0x1", interval: 0.05) { n += 1 }
            return n
        }
        try await Task.sleep(nanoseconds: 120_000_000)
        task.cancel()
        // Cancelling the consumer ends the stream (normally or with CancellationError) and stops polling.
        if let n = try? await task.value { XCTAssertEqual(n, 1) }
        // Let a request issued just before the cancel reach the mock, then expect no more.
        try await Task.sleep(nanoseconds: 100_000_000)
        let polls = requestCount
        XCTAssertGreaterThanOrEqual(polls, 2)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(requestCount, polls)
    }

    func testIsFinal() {
        let cases: [(OrderState, Bool)] = [("filled", true), ("refunded", true), ("failed", true), ("pending", false), ("unknown", false)]
        for (s, want) in cases { XCTAssertEqual(s.isFinal, want, s.rawValue) }
        XCTAssertTrue(LimitOrderStatus.cancelled.isFinal)
        XCTAssertFalse(LimitOrderStatus.open.isFinal)
    }
}
