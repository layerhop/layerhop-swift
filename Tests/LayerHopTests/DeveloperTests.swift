import Foundation
import XCTest
@testable import LayerHop

let screeningJSON = #"{"source":"ofac_sdn","listUpdatedAt":"2026-10-28T00:00:00.000Z","sanctioned":[{"address":"0x098B716B8Aaf21512996dC57EB0615e2383E2f96","role":"recipient","lists":["OFAC SDN"]}]}"#

let x402PaymentJSON = #"{"id":"x402_1","object":"x402.payment","status":"settled","statusDetail":null,"network":"eip155:8453","chainId":8453,"asset":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","payer":"0x857b","payTo":"0xdep","amount":"10025","merchantAmount":"10000","feeBps":25,"resource":"https://api.example.com/v1/weather","transaction":"0x1234","sweepTx":null,"settledAt":"2026-11-04T10:00:00.000Z","createdAt":"2026-11-04T09:59:40.000Z","updatedAt":"2026-11-04T10:00:00.000Z"}"#

/// 0.9.0: exact output, live quotes, screening, checkout transfer / Bitcoin, usage, resend, x402.
final class DeveloperTests: MockTestCase {
    func queryItems(_ r: Recorded) -> [String: String] {
        let items = URLComponents(url: r.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Exact output

    func testQuoteExactOutput() async throws {
        let body = patch(quoteJSON, #""estimatedSeconds":8,"fees":{"ourFeeBps":20,"providerFeeUsd""#, #""estimatedSeconds":8,"srcAmount":"100120000","srcAmountMax":"100620600","fees":{"ourFeeBps":20,"providerFeeUsd""#)
        respond(patch(body, #""errors":["#, #""screening":\#(screeningJSON),"errors":["#))
        let r = try await client.quoteExactOutput(
            ExactOutputQuoteParams(
                srcChain: "base", srcToken: "USDC", dstAmount: "100000000", dstChain: "arbitrum", dstToken: "USDC",
                sender: "0x1", recipient: "0x2"))
        let q = queryItems(last)
        XCTAssertEqual(last.rawPath, "/v1/quote")
        XCTAssertEqual(q["dstAmount"], "100000000")
        XCTAssertNil(q["amount"])
        XCTAssertEqual(q["slippageBps"], "50")
        XCTAssertEqual(q["channel"], "api")
        XCTAssertEqual(r.best.srcAmount, "100120000")
        XCTAssertEqual(r.best.srcAmountMax, "100620600")
        XCTAssertNil(r.quotes[0].srcAmountMax)
        XCTAssertEqual(r.screening?.source, "ofac_sdn")
        XCTAssertEqual(r.screening?.sanctioned.first?.role, "recipient")
        XCTAssertEqual(r.screening?.sanctioned.first?.lists, ["OFAC SDN"])
    }

    // MARK: Live quotes

    func testStreamQuotes() async throws {
        let first = patch(quoteJSON, #"{"best":"#, #"{"seq":1,"best":"#)
        let second = patch(patch(quoteJSON, #"{"best":"#, #"{"seq":2,"best":"#), #""dstAmount":"612345678","dstAmountMin":"609283949","estimatedSeconds":8,"fees":{"ourFeeBps":20,"providerFeeUsd""#, #""dstAmount":"612400000","dstAmountMin":"609283949","estimatedSeconds":8,"fees":{"ourFeeBps":20,"providerFeeUsd""#)
        respond { _ in
            MockResponse(
                chunks: [
                    "event: ready\ndata: {\"intervalMs\":10000,\"expiresAt\":\"x\",\"retryMs\":3000}\n\n",
                    "event: quote\ndata: \(first)\n\n: ping\n\n",
                    "event: quote\r\ndata: \(second)\r\n\r\n",
                    "event: end\ndata: {\"reason\":\"expired\",\"quotesSent\":2}\n\n",
                    "event: quote\ndata: \(first)\n\n",
                ], headers: sseHeaders)
        }
        let p = QuoteParams(
            srcChain: "base", srcToken: "USDC", amount: "100000000", dstChain: "solana", dstToken: "SOL",
            sender: "0x1", recipient: "So1")
        var got: [QuoteStreamUpdate] = []
        for try await u in client.streamQuotes(p, intervalMs: 15000) { got.append(u) }
        XCTAssertEqual(got.map(\.seq), [1, 2])
        XCTAssertEqual(got[0].best.dstAmount, "612345678")
        XCTAssertEqual(got[1].best.dstAmount, "612400000")
        XCTAssertEqual(got[1].response.errors?.first?.provider, "lifi")
        XCTAssertEqual(last.rawPath, "/v1/quote/stream")
        XCTAssertEqual(last.header("accept"), "text/event-stream")
        let q = queryItems(last)
        XCTAssertEqual(q["amount"], "100000000")
        XCTAssertEqual(q["intervalMs"], "15000")
        XCTAssertEqual(q["dstChain"], "solana")
    }

    func testStreamQuotesErrorEvent() async throws {
        let first = patch(quoteJSON, #"{"best":"#, #"{"seq":1,"best":"#)
        respond { _ in
            MockResponse(
                chunks: [
                    "event: quote\ndata: \(first)\n\n",
                    "event: error\ndata: {\"status\":451,\"error\":{\"code\":\"ADDRESS_SANCTIONED\",\"message\":\"Listed\",\"requestId\":\"r_9\",\"details\":{\"role\":\"recipient\"}}}\n\n",
                ], headers: sseHeaders)
        }
        let p = ExactOutputQuoteParams(
            srcChain: "base", srcToken: "USDC", dstAmount: "5000000", dstChain: "base", dstToken: "USDT",
            sender: "0x1", recipient: "0x2")
        var n = 0
        do {
            for try await _ in client.streamQuotes(p) { n += 1 }
            XCTFail("expected an error")
        } catch let e as LayerHopError {
            XCTAssertEqual(e.code, "ADDRESS_SANCTIONED")
            XCTAssertEqual(e.status, 451)
            XCTAssertEqual(e.requestId, "r_9")
            XCTAssertEqual(e.details?["role"]?.stringValue, "recipient")
        }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(queryItems(last)["dstAmount"], "5000000")
        XCTAssertNil(queryItems(last)["intervalMs"])
    }

    func testStreamQuotesHTTPError() async throws {
        respond(status: 404, #"{"error":{"code":"NO_ROUTE","message":"No route","requestId":"r_1"}}"#)
        let p = QuoteParams(
            srcChain: "base", srcToken: "USDC", amount: "1", dstChain: "base", dstToken: "USDT",
            sender: "0x1", recipient: "0x2")
        do {
            for try await _ in client.streamQuotes(p) {}
            XCTFail("expected an error")
        } catch let e as LayerHopError {
            XCTAssertEqual(e.code, "NO_ROUTE")
            XCTAssertEqual(e.status, 404)
        }
    }

    // MARK: Screening

    func testScreen() async throws {
        respond(#"{"results":[{"address":"0x098B","sanctioned":true,"lists":["OFAC SDN"],"source":"ofac_sdn","listUpdatedAt":"2026-10-28T00:00:00.000Z"},{"address":"0x1111","sanctioned":false,"lists":[],"source":"ofac_sdn","listUpdatedAt":null}],"list":{"source":"ofac_sdn","name":"OFAC SDN","publishedAt":"2026-10-28T00:00:00.000Z","fetchedAt":"2026-11-04T06:00:00.000Z","addressCount":1081},"enforced":false}"#)
        let r = try await client.screen(addresses: ["0x098B", "0x1111"])
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/screen")
        XCTAssertEqual(last.bodyString, #"{"addresses":["0x098B","0x1111"]}"#)
        XCTAssertEqual(r.results.map(\.sanctioned), [true, false])
        XCTAssertNil(r.results[1].listUpdatedAt)
        XCTAssertEqual(r.list?.addressCount, 1081)
        XCTAssertFalse(r.enforced)

        respond(#"{"results":[],"list":null,"enforced":true}"#)
        let empty = try await client.screen(addresses: ["x"])
        XCTAssertNil(empty.list)
        XCTAssertTrue(empty.enforced)
    }

    func testCheckoutQuoteScreening() async throws {
        respond(#"{"sessionId":"cs_1","livemode":true,"amountDue":"1","best":{"quoteId":"q","provider":"direct","srcAmount":"1","dstAmount":"1","dstAmountMin":"1","estimatedSeconds":1,"fees":{"ourFeeBps":25},"expiresAt":1},"quotes":[],"screening":\#(screeningJSON)}"#)
        let r = try await client.quoteCheckoutSession(id: "cs_1", CheckoutQuoteParams(srcChain: "base", srcToken: "USDC", sender: "0x1"))
        XCTAssertEqual(r.screening?.sanctioned.count, 1)
    }

    // MARK: Checkout

    func testCreateCheckoutEmbedOrigins() async throws {
        respond(sessionJSON)
        _ = try await client.createCheckoutSession(
            CreateCheckoutParams(
                amount: "1", settleChain: "base", settleToken: "USDC", recipient: "0x2",
                embedOrigins: ["https://shop.example"]))
        XCTAssertEqual(last.json["embedOrigins"] as? [String], ["https://shop.example"])

        _ = try await client.createCheckoutSession(
            CreateCheckoutParams(amount: "1", settleChain: "base", settleToken: "USDC", recipient: "0x2"))
        XCTAssertNil(last.json["embedOrigins"])
    }

    func testStartCheckoutTransfer() async throws {
        let transfer = #""transferAvailable":true,"embedOrigins":["https://shop.example"],"branding":false,"transfer":{"kind":"evm_splitter","chainId":8453,"token":"0x83","symbol":"USDC","decimals":6,"address":"0xdep","amount":"49122500","amountDue":"49000000","fee":{"bps":25,"amount":"122500"},"uri":"ethereum:0x83@8453/transfer?address=0xdep&uint256=49122500","transferUri":null,"reference":null,"received":"0","seen":"0","state":"waiting","txs":[{"hash":"0xaa","amount":"1","at":null}],"startedAt":"2026-11-04T10:00:00.000Z","sweepTxHash":null},"createdAt""#
        var body = patch(sessionJSON, #""createdAt""#, transfer)
        body = patch(body, #""payment":{"quoteId":"q_9","#, #""payment":{"method":"transfer","quoteId":null,"#)
        respond(body)
        let s = try await client.startCheckoutTransfer(id: "cs_1")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_1/transfer")
        XCTAssertEqual(last.bodyString, "{}")
        XCTAssertEqual(s.transferAvailable, true)
        XCTAssertEqual(s.embedOrigins, ["https://shop.example"])
        XCTAssertEqual(s.branding, false)
        XCTAssertEqual(s.payment?.method, "transfer")
        XCTAssertNil(s.payment?.quoteId)
        let t = try XCTUnwrap(s.transfer)
        XCTAssertEqual(t.kind, "evm_splitter")
        XCTAssertEqual(t.fee?.amount, "122500")
        XCTAssertEqual(t.state, "waiting")
        XCTAssertEqual(t.txs.first?.hash, "0xaa")
        XCTAssertNil(t.txs.first?.at)
        XCTAssertNil(s.bitcoin)
    }

    func testStartCheckoutBitcoin() async throws {
        let btc = #""bitcoinAvailable":true,"bitcoin":{"address":"bc1qdep","amountSats":"71234","amountBtc":"0.00071234","uri":"bitcoin:bc1qdep?amount=0.00071234","amountOut":"49000000","expiresAt":"2026-11-04T10:10:00.000Z","expired":false,"status":"waiting","seenSats":"0","requestId":"0xreq","feeBps":25,"refundAddress":"bc1qrefund","quotes":[{"address":"bc1qdep","amountSats":"71234","status":"waiting","requestId":"0xreq","createdAt":"2026-11-04T10:00:00.000Z"}]},"createdAt""#
        respond(patch(sessionJSON, #""createdAt""#, btc))
        let s = try await client.startCheckoutBitcoin(id: "cs_1", refundAddress: "bc1qrefund")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_1/bitcoin")
        XCTAssertEqual(last.bodyString, #"{"refundAddress":"bc1qrefund"}"#)
        XCTAssertEqual(s.bitcoinAvailable, true)
        let b = try XCTUnwrap(s.bitcoin)
        XCTAssertEqual(b.amountSats, "71234")
        XCTAssertEqual(b.uri, "bitcoin:bc1qdep?amount=0.00071234")
        XCTAssertEqual(b.feeBps, 25)
        XCTAssertFalse(b.expired)
        XCTAssertEqual(b.quotes.count, 1)
        // The existing session fixture still decodes (payment.method absent, quoteId set).
        XCTAssertNil(s.payment?.method)
        XCTAssertEqual(s.payment?.quoteId, "q_9")

        _ = try await client.startCheckoutBitcoin(id: "cs_1")
        XCTAssertEqual(last.bodyString, "{}")
    }

    // MARK: Webhooks and usage

    func testResendWebhookEvent() async throws {
        respond(status: 202, #"{"eventId":"evt_1","type":"order.filled","livemode":false,"deliveries":[{"id":"whd_1","endpointId":"whe_1"}]}"#)
        let r = try await client.resendWebhookEvent(id: "evt_1", endpointId: "whe_1")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/webhooks/events/evt_1/resend")
        XCTAssertEqual(last.bodyString, #"{"endpointId":"whe_1"}"#)
        XCTAssertEqual(r.type, .orderFilled)
        XCTAssertEqual(r.deliveries.first?.endpointId, "whe_1")

        respond(status: 202, #"{"eventId":"evt_1","deliveries":[]}"#)
        let none = try await client.resendWebhookEvent(id: "evt_1")
        XCTAssertEqual(last.bodyString, "{}")
        XCTAssertTrue(none.deliveries.isEmpty)
    }

    func testStreamWebhookEventsSince() async throws {
        respond { _ in MockResponse(chunks: ["event: event\ndata: \(eventJSON)\n\n"], headers: sseHeaders) }
        var n = 0
        for try await _ in client.streamWebhookEvents(since: "2026-11-04T10:00:00.000Z") { n += 1 }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(last.rawPath, "/v1/webhooks/stream")
        XCTAssertEqual(queryItems(last)["since"], "2026-11-04T10:00:00.000Z")
    }

    func testX402WebhookEvent() throws {
        let json = #"{"id":"evt_x","type":"x402.payment.settled","livemode":true,"createdAt":"t","data":{"payment":\#(x402PaymentJSON)}}"#
        let e = try JSONDecoder().decode(WebhookEvent.self, from: Data(json.utf8))
        XCTAssertEqual(e.type, .x402PaymentSettled)
        XCTAssertEqual(e.data.payment?.merchantAmount, "10000")
    }

    func testUsage() async throws {
        respond(#"{"bucket":"day","from":"2026-10-05T10:00:00.000Z","to":"2026-11-04T10:00:00.000Z","livemode":true,"keyId":"key_1","totals":{"requests":1480,"errors":21,"byStatusClass":{"2xx":1459,"3xx":0,"4xx":19,"5xx":2},"avgMs":318,"p50Ms":212,"p95Ms":1240},"series":[{"ts":"2026-11-04T00:00:00.000Z","requests":61,"errors":1,"byStatusClass":{"2xx":60,"3xx":0,"4xx":1,"5xx":0},"p50Ms":null,"p95Ms":null}],"byEndpoint":[{"group":"quote","requests":1210,"errors":18,"byStatusClass":{"2xx":1192,"3xx":0,"4xx":17,"5xx":1},"avgMs":352.5,"p50Ms":240,"p95Ms":1320}],"errorCodes":[{"code":"NO_ROUTE","count":12,"byEndpoint":{"quote":12}}]}"#)
        let r = try await client.usage(UsageParams(bucket: .day, from: "2026-10-05", keyId: "key_1"))
        XCTAssertEqual(last.rawPath, "/v1/usage")
        let q = queryItems(last)
        XCTAssertEqual(q["bucket"], "day")
        XCTAssertEqual(q["from"], "2026-10-05")
        XCTAssertNil(q["to"])
        XCTAssertEqual(q["keyId"], "key_1")
        XCTAssertEqual(r.bucket, .day)
        XCTAssertEqual(r.totals.byStatusClass.status2xx, 1459)
        XCTAssertEqual(r.totals.byStatusClass.status5xx, 2)
        XCTAssertEqual(r.totals.p95Ms, 1240)
        XCTAssertNil(r.series[0].p50Ms)
        XCTAssertEqual(r.byEndpoint[0].avgMs, 352.5)
        XCTAssertEqual(r.errorCodes[0].byEndpoint["quote"], 12)

        _ = try? await client.usage()
        XCTAssertEqual(last.query, "")
    }

    func testUsageErrors() async throws {
        respond(#"{"livemode":true,"errors":[{"ts":"2026-11-04T09:58:12.120Z","keyId":"key_1","requestId":"0d5e","method":"GET","path":"/v1/quote","endpointGroup":"quote","status":404,"code":"NO_ROUTE","latencyMs":812}]}"#)
        let errors = try await client.usageErrors(UsageErrorsParams(code: "NO_ROUTE", limit: 10))
        XCTAssertEqual(last.rawPath, "/v1/usage/errors")
        XCTAssertEqual(last.query, "code=NO_ROUTE&limit=10")
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].code, "NO_ROUTE")
        XCTAssertEqual(errors[0].latencyMs, 812)
    }

    // MARK: x402

    func testX402Supported() async throws {
        respond(#"{"kinds":[{"x402Version":2,"scheme":"exact","network":"eip155:8453"},{"x402Version":1,"scheme":"exact","network":"base"}],"extensions":[],"signers":{},"settle":false}"#)
        let r = try await client.x402Supported()
        XCTAssertEqual(last.rawPath, "/v1/x402/supported")
        XCTAssertEqual(r.kinds.map(\.network), ["eip155:8453", "base"])
        XCTAssertFalse(r.settle)
    }

    func testX402Requirements() async throws {
        respond(#"{"payee":{"id":"x4p_1","network":"eip155:8453","chainId":8453,"asset":"0x83","depositAddress":"0xdep","merchant":"0x2222","resource":"https://api.example.com/v1/weather","feeBps":25,"factory":"0xfac","lastSweepTx":null,"lastSweptAt":null},"price":"10000","amount":"10025","fee":{"bps":25,"amount":"25"},"accepts":[{"scheme":"exact","network":"eip155:8453","amount":"10025","asset":"0x83","payTo":"0xdep","maxTimeoutSeconds":60,"extra":{"name":"USD Coin","version":"2"}}],"acceptsV1":[{"scheme":"exact","network":"base","maxAmountRequired":"10025"}],"paymentRequired":{"x402Version":2,"accepts":[]}}"#)
        let r = try await client.x402Requirements(
            X402RequirementsParams(amount: "10000", payTo: "0x2222", resource: "https://api.example.com/v1/weather", description: "Weather"))
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/x402/requirements")
        XCTAssertEqual(last.bodyString, #"{"amount":"10000","description":"Weather","payTo":"0x2222","resource":"https://api.example.com/v1/weather"}"#)
        XCTAssertEqual(r.payee.depositAddress, "0xdep")
        XCTAssertEqual(r.amount, "10025")
        XCTAssertEqual(r.accepts[0].payTo, "0xdep")
        XCTAssertEqual(r.accepts[0].extra?["version"]?.stringValue, "2")
        XCTAssertEqual(r.acceptsV1[0]["maxAmountRequired"]?.stringValue, "10025")
        XCTAssertEqual(r.paymentRequired["x402Version"]?.intValue, 2)
    }

    func testX402VerifyAndSettle() async throws {
        let payload: JSONValue = .object([
            "x402Version": .int(2),
            "payload": .object(["signature": .string("0xsig"), "authorization": .object(["nonce": .string("0x01")])]),
        ])
        let reqs: JSONValue = .object(["scheme": .string("exact"), "network": .string("eip155:8453")])
        respond(#"{"isValid":false,"invalidReason":"insufficient_funds","payer":"0x857b"}"#)
        let v = try await client.x402Verify(X402FacilitatorRequest(paymentPayload: payload, paymentRequirements: reqs, x402Version: 2))
        XCTAssertEqual(last.rawPath, "/v1/x402/verify")
        XCTAssertEqual(last.json["x402Version"] as? Int, 2)
        XCTAssertEqual((last.json["paymentPayload"] as? [String: Any])?["x402Version"] as? Int, 2)
        XCTAssertFalse(v.isValid)
        XCTAssertEqual(v.invalidReason, "insufficient_funds")

        respond(#"{"success":false,"errorReason":"settlement_pending","payer":"0x857b","transaction":"0x1234","network":"eip155:8453"}"#)
        let s = try await client.x402Settle(X402FacilitatorRequest(paymentPayload: payload, paymentRequirements: reqs))
        XCTAssertEqual(last.rawPath, "/v1/x402/settle")
        XCTAssertNil(last.json["x402Version"])
        XCTAssertEqual(s.errorReason, "settlement_pending")
        XCTAssertEqual(s.transaction, "0x1234")

        respond(status: 403, #"{"error":{"code":"FORBIDDEN","message":"x402 settlement is not enabled"}}"#)
        let e = await expectLayerHopError { try await self.client.x402Settle(X402FacilitatorRequest(paymentPayload: payload, paymentRequirements: reqs)) }
        XCTAssertEqual(e?.code, "FORBIDDEN")
    }

    func testX402Payments() async throws {
        respond(#"{"payments":[\#(x402PaymentJSON)],"nextCursor":"c2"}"#)
        let page = try await client.listX402Payments(ListX402PaymentsParams(status: "settled", limit: 20))
        XCTAssertEqual(last.rawPath, "/v1/x402/payments")
        XCTAssertEqual(last.query, "limit=20&status=settled")
        XCTAssertEqual(page.payments[0].feeBps, 25)
        XCTAssertNil(page.payments[0].sweepTx)
        XCTAssertEqual(page.nextCursor, "c2")

        respond(x402PaymentJSON)
        let p = try await client.getX402Payment(id: "x402_1")
        XCTAssertEqual(last.rawPath, "/v1/x402/payments/x402_1")
        XCTAssertEqual(p.status, "settled")
        XCTAssertEqual(p.chainId, 8453)
    }
}
