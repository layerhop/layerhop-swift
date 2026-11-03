import Foundation
import XCTest
@testable import LayerHop

let tronTxJSON = #"{"quoteId":"q_t","provider":"relay","tx":{"vm":"tvm","chainId":728126428,"from":"TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf","call":{"to":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","data":"0xa9059cbb","value":"0","feeLimit":"150000000"},"unsigned":{"txID":"a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90","raw_data_hex":"0a02","raw_data":{"contract":[{"parameter":{"value":{"data":"a9059cbb","owner_address":"41aa","contract_address":"41bb"},"type_url":"type.googleapis.com/protocol.TriggerSmartContract"},"type":"TriggerSmartContract"}],"ref_block_bytes":"1234","expiration":1761650000000,"fee_limit":150000000,"timestamp":1761649400000},"visible":false},"approval":{"token":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","spender":"TSpender1111111111111111111111111","amount":"5000000","call":{"to":"TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t","data":"0x095ea7b3","value":"0","feeLimit":"100000000"},"unsigned":{"txID":"ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00ff00","raw_data_hex":"0a03","raw_data":{"expiration":1761650000000}}}}}"#

let gaslessBuildJSON = #"{"quoteId":"q_g","provider":"0x","gasless":{"chainId":8453,"approval":{"type":"permit","eip712":{"types":{"Permit":[{"name":"owner","type":"address"}]},"domain":{"name":"USD Coin","chainId":8453},"message":{"owner":"0xabc","value":"1000000"},"primaryType":"Permit"}},"trade":{"type":"settler_metatransaction","eip712":{"types":{"Meta":[{"name":"x","type":"uint256"}]},"domain":{"name":"Settler"},"message":{"x":"1"},"primaryType":"Meta"}},"gasFee":{"amount":"12000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"}}}"#

let splitJSON = #"{"id":"sp_1","url":"https://layerhop.com/split/sp_1","status":"open","note":"Dinner","recipient":"0x2222","recipientName":"ada.eth","chainId":8453,"chain":"base","token":{"address":"0x83","symbol":"USDC","decimals":6},"total":"90000000","collected":"30000000","paidCount":1,"shares":[{"index":0,"label":"Ada","amount":"30000000","received":"30000000","status":"paid","payments":1,"pending":0},{"index":1,"label":"","amount":"30000000","received":"0","status":"unpaid","payments":0,"pending":0}],"createdAt":"t","updatedAt":"t"}"#

final class PlatformTests: MockTestCase {
    // MARK: Tron

    func testTronTxDecode() async throws {
        respond(tronTxJSON)
        let tx = try await client.buildTx(quoteId: "q_t")
        XCTAssertTrue(tx.isTVM)
        XCTAssertEqual(tx.vm, "tvm")
        XCTAssertFalse(tx.sandbox)
        let t = try XCTUnwrap(tx.tvm)
        XCTAssertEqual(t.chainId, LayerHop.tronChainID)
        XCTAssertEqual(t.call.feeLimit, "150000000")
        XCTAssertEqual(t.unsigned?.txID.count, 64)
        XCTAssertEqual(t.unsigned?.rawDataHex, "0a02")
        XCTAssertEqual(t.unsigned?.visible, false)
        XCTAssertEqual(t.unsigned?.rawData["expiration"]?.intValue, 1_761_650_000_000)
        XCTAssertEqual(t.unsigned?.rawData["contract"]?[0]?["type"]?.stringValue, "TriggerSmartContract")
        XCTAssertEqual(t.approval?.spender, "TSpender1111111111111111111111111")
        XCTAssertEqual(t.approval?.call.data, "0x095ea7b3")
        XCTAssertNil(t.approval?.unsigned?.visible)

        // The unsigned tx serializes back with the node's own keys, numbers exact.
        let json = try XCTUnwrap(t.unsigned?.jsonString())
        XCTAssertTrue(json.contains(#""raw_data_hex":"0a02""#), json)
        XCTAssertTrue(json.contains(#""expiration":1761650000000"#), json)
        XCTAssertTrue(json.contains(#""txID":"a1b2"#), json)

        // Round trip through BuiltTx keeps vm.
        let data = try JSONEncoder().encode(tx)
        XCTAssertEqual(try JSONDecoder().decode(BuiltTx.self, from: data), tx)
    }

    func testSimulateTron() async throws {
        respond(#"{"quoteId":"q_t","provider":"relay","ok":true,"vm":"tvm","energyUsed":64285,"simulated":"tx","tx":{"vm":"tvm","chainId":728126428,"from":"T1","call":{"to":"T2","data":"0x","value":"0","feeLimit":"1"},"sandbox":true}}"#)
        let s = try await client.simulate(quoteId: "q_t")
        XCTAssertEqual(s.vm, "tvm")
        XCTAssertEqual(s.energyUsed, 64285)
        XCTAssertEqual(s.tx?.sandbox, true)
        XCTAssertNil(s.tx?.tvm?.unsigned)
    }

    // MARK: Gasless

    func testGasless() async throws {
        respond(gaslessBuildJSON)
        let g = try await client.buildGasless(quoteId: "q_g")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/orders")
        XCTAssertEqual(last.bodyString, #"{"quoteId":"q_g"}"#)
        XCTAssertEqual(g.chainId, 8453)
        XCTAssertEqual(g.approval?.type, "permit")
        XCTAssertEqual(g.trade.eip712.primaryType, "Meta")
        XCTAssertEqual(g.trade.eip712.message["x"]?.stringValue, "1")
        XCTAssertEqual(g.gasFee?.amount, "12000")
        let typed = try g.approval!.eip712.jsonString()
        XCTAssertEqual(typed, #"{"domain":{"chainId":8453,"name":"USD Coin"},"message":{"owner":"0xabc","value":"1000000"},"primaryType":"Permit","types":{"Permit":[{"name":"owner","type":"address"}]}}"#)

        // buildTx on a gasless quote is a clear error, not a decoding failure.
        let e = await expectLayerHopError { try await self.client.buildTx(quoteId: "q_g") }
        XCTAssertEqual(e, .decoding("This quote is gasless; use buildGasless"))

        respond(#"{"quoteId":"q_g","provider":"0x","orderId":"0xhash","state":"pending"}"#)
        let st = try await client.submitGasless(quoteId: "q_g", tradeSignature: "0xt", approvalSignature: "0xa")
        XCTAssertEqual(st.state, .pending)
        XCTAssertEqual(last.rawPath, "/v1/orders/gasless")
        assertJSON(last.body, #"{"quoteId":"q_g","signatures":{"trade":"0xt","approval":"0xa"}}"#)
        _ = try await client.submitGasless(quoteId: "q_g", tradeSignature: "0xt")
        XCTAssertEqual(last.bodyString, #"{"quoteId":"q_g","signatures":{"trade":"0xt"}}"#)

        respond(#"{"quoteId":"q_g","provider":"0x","orderId":"0xhash","state":"failed","reason":"order_expired"}"#)
        let s2 = try await client.gaslessStatus(quoteId: "q_g")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/orders/gasless/q_g")
        XCTAssertEqual(s2.reason, "order_expired")
        XCTAssertTrue(s2.state.isFinal)

        respond(#"{"quoteId":"q_1","provider":"relay","tx":{"vm":"svm","serializedTx":"AQ"}}"#)
        let e2 = await expectLayerHopError { try await self.client.buildGasless(quoteId: "q_1") }
        XCTAssertEqual(e2, .decoding("This quote is not gasless; use buildTx"))
    }

    // MARK: Quotes

    func testQuoteExtraParams() async throws {
        respond(#"{"best":{"quoteId":"q_1","provider":"0x","dstAmount":"1","dstAmountMin":"1","estimatedSeconds":1,"fees":{"ourFeeBps":20},"expiresAt":1,"gasless":{"gasFee":{"amount":"5","token":"0x83"},"approval":true}},"quotes":[],"warnings":[{"code":"X","message":"y"}]}"#)
        let r = try await client.quote(QuoteParams(
            srcChain: "base", srcToken: "USDC", amount: "100", dstChain: "base", dstToken: "WETH",
            sender: "0xa", recipient: "0xb", gasless: true, referrer: "0xref", copyOf: "q_c",
            purpose: .split, splitId: "sp_1", splitShare: 0, note: "hi there"))
        XCTAssertEqual(r.best.gasless?.approval, true)
        XCTAssertEqual(r.best.gasless?.gasFee?.amount, "5")
        XCTAssertEqual(r.warnings?.first?.code, "X")
        XCTAssertEqual(
            last.query,
            "amount=100&channel=api&copyOf=q_c&dstChain=base&dstToken=WETH&gasless=true&note=hi%20there&purpose=split&recipient=0xb&referrer=0xref&sender=0xa&slippageBps=50&splitId=sp_1&splitShare=0&srcChain=base&srcToken=USDC")
    }

    func testQuoteCalls() async throws {
        client = makeClient(.init(baseURL: "https://api.test", apiKey: "k1", integrator: "myapp", integratorFeeBps: 25))
        respond(#"{"best":{"quoteId":"q_1","provider":"relay","srcAmount":"1010000","dstAmount":"1000000","dstAmountMin":"1000000","estimatedSeconds":20,"fees":{"ourFeeBps":20},"expiresAt":1,"calls":{"items":[{"to":"0xpool","data":"0x617ba037","value":"0"}],"executor":"0xexec","executed":true,"simulation":{"ok":true,"gasUsed":180000,"leftover":"0"}}},"quotes":[]}"#)
        let r = try await client.quoteCalls(CallsQuoteParams(
            srcChain: "8453", srcToken: "USDC", dstChain: "42161", dstToken: "USDC", dstAmount: "1000000",
            sender: "0xa", recipient: "0xb", calls: [DestinationCall(to: "0xpool", data: "0x617ba037")],
            action: .aaveV3Supply, referrer: "0xref"))
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/quote")
        assertJSON(last.body, #"{"srcChain":"8453","srcToken":"USDC","dstChain":"42161","dstToken":"USDC","dstAmount":"1000000","sender":"0xa","recipient":"0xb","slippageBps":50,"channel":"api","integrator":"myapp","integratorFeeBps":25,"calls":[{"to":"0xpool","data":"0x617ba037"}],"action":{"type":"aave-v3-supply"},"referrer":"0xref"}"#)
        XCTAssertEqual(r.best.srcAmount, "1010000")
        XCTAssertEqual(r.best.calls?.executor, "0xexec")
        XCTAssertEqual(r.best.calls?.items.first?.to, "0xpool")
        XCTAssertEqual(r.best.calls?.simulation?.gasUsed, "180000")
        XCTAssertEqual(r.best.calls?.simulation?.leftover, "0")
    }

    // MARK: Errors

    func testNoRouteSuggestions() async {
        respond(status: 422, #"{"error":{"code":"NO_ROUTE","message":"No route","requestId":"r1","details":{"errors":[{"provider":"relay","code":"NO_ROUTE","message":"none"},{"provider":1}],"suggestions":[{"kind":"dst_token","message":"Receive USDC instead","symbol":"USDC","srcChain":8453,"srcToken":"0x83","amount":"1000000","dstChain":1,"dstToken":"0xa0","dstAmount":"990000"},{"kind":"via_hub","message":"Go through Arbitrum","symbol":"USDC","srcChain":8453,"srcToken":"0x83","amount":"1000000","dstChain":7565164,"dstToken":"So1","hub":{"chainId":42161,"token":"0xaf","symbol":"USDC","decimals":6},"steps":[{"srcChain":8453,"srcToken":"0x83","amount":"1000000","dstChain":42161,"dstToken":"0xaf","dstAmount":"999000"},{"srcChain":42161,"srcToken":"0xaf","amount":"999000","dstChain":7565164,"dstToken":"So1"}]},{"kind":"via_hub","message":"Missing hub","srcChain":8453,"srcToken":"0x83","amount":"1000000","dstChain":1,"dstToken":"0xa0","steps":[]},{"kind":"src_token","message":"bad amount","srcChain":8453,"srcToken":"0x83","amount":"1.5","dstChain":1,"dstToken":"0xa0"},{"kind":"other","message":"x","srcChain":1,"srcToken":"a","amount":"1","dstChain":1,"dstToken":"b"}]}}}"#)
        let e = await expectLayerHopError { try await self.client.chains() }
        XCTAssertEqual(e?.code, "NO_ROUTE")
        XCTAssertNotNil(e?.details)
        let s = e?.suggestions ?? []
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].kind, "dst_token")
        XCTAssertEqual(s[0].dstAmount, "990000")
        XCTAssertNil(s[0].hub)
        XCTAssertEqual(s[1].kind, "via_hub")
        XCTAssertEqual(s[1].hub?.chainId, 42161)
        XCTAssertEqual(s[1].steps?.count, 2)
        XCTAssertNil(s[1].steps?[1].dstAmount)
        XCTAssertEqual(s[1].leg.dstChain, LayerHop.solanaChainID)
        XCTAssertEqual(e?.providerErrors, [ProviderFailure(provider: "relay", code: "NO_ROUTE", message: "none")])
        XCTAssertNil(e?.minAmount)
    }

    func testAmountTooSmall() async {
        respond(status: 400, #"{"error":{"code":"AMOUNT_TOO_SMALL","message":"Too small","details":{"minAmount":"5000000","minAmountUsd":5,"minAmountApprox":true}}}"#)
        let e = await expectLayerHopError { try await self.client.chains() }
        XCTAssertEqual(e?.minAmount, "5000000")
        XCTAssertEqual(e?.minAmountUsd, 5)
        XCTAssertEqual(e?.minAmountApprox, true)
        XCTAssertEqual(e?.suggestions, [])

        // A non-object `details` is ignored.
        respond(status: 400, #"{"error":{"code":"INVALID_PARAMS","message":"x","details":"nope"}}"#)
        let e2 = await expectLayerHopError { try await self.client.chains() }
        XCTAssertNil(e2?.details)
        XCTAssertEqual(e2, .api(code: "INVALID_PARAMS", message: "x", status: 400, requestId: "req-hdr"))
    }

    // MARK: Tokens and chains

    func testTokens() async throws {
        respond(#"{"tokens":[{"chainId":8453,"address":"0x83","symbol":"USDC","name":"USD Coin","decimals":6,"priceUsd":1,"verified":true,"popular":true}],"nextCursor":"c2"}"#)
        let page = try await client.searchTokens(TokensParams(chain: "base", q: "usd", limit: 10, cursor: "c1"))
        XCTAssertEqual(last.query, "chain=base&cursor=c1&limit=10&q=usd")
        XCTAssertEqual(page.nextCursor, "c2")
        XCTAssertEqual(page.tokens[0].name, "USD Coin")
        XCTAssertEqual(page.tokens[0].verified, true)

        respond(#"{"token":{"chainId":1,"address":"0xabc","symbol":"FOO","name":"Foo","decimals":18,"verified":false}}"#)
        let t = try await client.lookupToken(address: "0xabc")
        XCTAssertEqual(last.rawPath, "/v1/tokens/lookup")
        XCTAssertEqual(last.query, "address=0xabc")
        XCTAssertEqual(t.verified, false)
        _ = try await client.lookupToken(address: "0xabc", chain: "ethereum")
        XCTAssertEqual(last.query, "address=0xabc&chain=ethereum")
    }

    func testTokenRisk() async throws {
        respond(#"{"risk":{"chainId":56,"address":"0xbad","level":"danger","verified":false,"symbol":"USDT","reasons":[{"code":"honeypot","level":"danger","message":"Can't sell"},{"code":"sell_tax","level":"caution","message":"Tax","value":12.5},{"code":"brand_new_code","level":"caution","message":"?"}],"source":"goplus","checkedAt":"2026-10-28T10:00:00Z"}}"#)
        let r = try await client.getTokenRisk(chain: "bsc", address: "0xbad")
        XCTAssertEqual(last.rawPath, "/v1/tokens/bsc/0xbad/risk")
        XCTAssertEqual(r.level, .danger)
        XCTAssertEqual(r.reasons.count, 3)
        XCTAssertEqual(r.reasons[1].value, 12.5)
        XCTAssertEqual(r.reasons[2].code, "brand_new_code")
        XCTAssertEqual(r.source, "goplus")
    }

    func testChainFields() async throws {
        respond(#"{"chains":[{"id":81457,"slug":"blast","name":"Blast","vm":"evm","nativeSymbol":"ETH","nativeDecimals":18,"logoURI":"https://x/l.png","explorerTx":"https://blastscan.io/tx/","explorerAddress":"https://blastscan.io/address/","providers":["relay"],"popular":false,"destinationOnly":true,"onlyRoute":{"srcChainId":1,"srcToken":"0x0000000000000000000000000000000000000000","dstToken":"0x0000000000000000000000000000000000000000"},"routeHealth":{"in":"ok","out":"failing","status":"deposit_only","checkedAt":"t"}},{"id":728126428,"slug":"tron","name":"Tron","vm":"tvm"}]}"#)
        let ch = try await client.chains()
        XCTAssertEqual(ch[0].destinationOnly, true)
        XCTAssertEqual(ch[0].onlyRoute?.srcChainId, 1)
        XCTAssertEqual(ch[0].routeHealth?.in, "ok")
        XCTAssertEqual(ch[0].routeHealth?.out, "failing")
        XCTAssertEqual(ch[0].routeHealth?.status, "deposit_only")
        XCTAssertEqual(ch[0].providers, ["relay"])
        XCTAssertEqual(ch[1].vm, "tvm")
        XCTAssertEqual(ch[1].id, LayerHop.tronChainID)
        XCTAssertNil(ch[1].routeHealth)
    }

    func testPricesAndBalances() async throws {
        respond(status: 500, "{}")
        let none = try await client.prices(ids: [])
        XCTAssertEqual(none, [:])
        XCTAssertEqual(requestCount, 0)

        respond(#"{"prices":{"8453:0x83":0.9998}}"#)
        let p = try await client.prices(ids: ["8453:0x83", "1:0xdead"])
        XCTAssertEqual(p["8453:0x83"], 0.9998)
        XCTAssertEqual(last.query, "ids=8453%3A0x83%2C1%3A0xdead")

        respond(#"{"address":"0xA","vm":"evm","balances":[{"chainId":8453,"address":"0x83","symbol":"USDC","name":"USD Coin","decimals":6,"verified":true,"amount":"2500000","valueUsd":2.5}],"totalUsd":2.5,"errors":[{"chainId":56,"message":"RPC down"}]}"#)
        let b = try await client.balances(address: "0xA", chains: ["base", "bsc"], tokens: ["8453:0x83"], fresh: true)
        XCTAssertEqual(last.rawPath, "/v1/balances")
        XCTAssertEqual(last.query, "address=0xA&chains=base%2Cbsc&fresh=1&tokens=8453%3A0x83")
        XCTAssertEqual(b.balances[0].amount, "2500000")
        XCTAssertEqual(b.totalUsd, 2.5)
        XCTAssertEqual(b.errors[0].chainId, 56)
        _ = try await client.balances(address: "0xA")
        XCTAssertEqual(last.query, "address=0xA")
    }

    // MARK: Splits, tip jars and payouts

    func testSplits() async throws {
        respond(patch(splitJSON, #""createdAt":"t""#, #""editToken":"et_secret","editUrl":"https://layerhop.com/split/sp_1#k=et_secret","createdAt":"t""#))
        let created = try await client.createSplit(CreateSplitParams(
            recipient: "ada.eth", chain: "base", token: "USDC", total: "90000000",
            shares: [SplitShareInput(label: "Ada"), SplitShareInput(label: "Bob")], note: "Dinner"))
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/splits")
        assertJSON(last.body, #"{"recipient":"ada.eth","chain":"base","token":"USDC","total":"90000000","shares":[{"label":"Ada"},{"label":"Bob"}],"note":"Dinner"}"#)
        XCTAssertEqual(created.editToken, "et_secret")
        XCTAssertEqual(created.id, "sp_1")
        XCTAssertEqual(created.split.shares[0].status, "paid")
        XCTAssertEqual(created.recipientName, "ada.eth")

        respond(splitJSON)
        let s = try await client.getSplit(id: "sp_1")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/splits/sp_1")
        XCTAssertEqual(s.token.decimals, 6)
        XCTAssertNil(last.header("x-edit-token"))

        respond(patch(splitJSON, #""note":"Dinner""#, #""note":null"#))
        let u = try await client.updateSplit(id: "sp_1", editToken: "et_secret", UpdateSplitParams(note: "", labels: ["A", "B"], status: "closed"))
        XCTAssertEqual(last.method, "PATCH")
        XCTAssertEqual(last.rawPath, "/v1/splits/sp_1")
        XCTAssertEqual(last.header("x-edit-token"), "et_secret")
        XCTAssertEqual(last.header("x-api-key"), "k1")
        XCTAssertEqual(last.bodyString, #"{"labels":["A","B"],"note":null,"status":"closed"}"#)
        XCTAssertNil(u.note)
    }

    func testTipJar() async throws {
        respond(#"{"address":"0xabc","tippers":3,"tips":5,"messages":[{"text":"gm","at":"t"}]}"#)
        let j = try await client.getTipJar(address: "0xABC")
        XCTAssertEqual(last.rawPath, "/v1/tip-jars/0xABC")
        XCTAssertEqual(j.tippers, 3)
        XCTAssertEqual(j.messages[0].text, "gm")
    }

    func testPayouts() async throws {
        respond(#"{"source":{"chainId":8453,"chain":"base","sender":"0xS","token":{"chainId":8453,"address":"0x83","symbol":"USDC","decimals":6,"usd":1}},"rows":[{"index":0,"line":0,"input":{"recipient":"ada.eth","amount":"25","token":"USDC","chain":"base"},"ok":true,"recipient":{"address":"0xA","name":"ada.eth"},"chainId":8453,"chain":"base","token":{"chainId":8453,"address":"0x83","symbol":"USDC","decimals":6},"amount":"25000000","kind":"transfer"},{"index":1,"line":0,"input":{"recipient":"x","amount":0.5,"token":"SOL","chain":7565164},"ok":false,"error":{"code":"NOT_FOUND","message":"Unknown name"}}],"transfers":[{"chainId":8453,"token":"0x83","rows":[0],"total":"25000000"}],"routes":[],"transferTotal":"25000000","totals":[{"chainId":8453,"token":"0x83","symbol":"USDC","decimals":6,"amount":"25000000","formatted":"25","rows":1}],"valid":1,"invalid":1,"warnings":[]}"#)
        let plan = try await client.planPayouts(PlanPayoutsParams(
            srcChain: "base", srcToken: "USDC", sender: "0xS",
            rows: [PayoutRowInput(recipient: "ada.eth", amount: "25", token: "USDC", chain: "base", label: "Ada")]))
        XCTAssertEqual(last.rawPath, "/v1/payouts/plan")
        assertJSON(last.body, #"{"srcChain":"base","srcToken":"USDC","sender":"0xS","rows":[{"recipient":"ada.eth","amount":"25","token":"USDC","chain":"base","label":"Ada"}]}"#)
        XCTAssertEqual(plan.valid, 1)
        XCTAssertEqual(plan.rows[0].kind, "transfer")
        XCTAssertEqual(plan.rows[1].input.amount, "0.5")
        XCTAssertEqual(plan.rows[1].input.chain, "7565164")
        XCTAssertEqual(plan.rows[1].error?.code, "NOT_FOUND")
        XCTAssertEqual(plan.transfers[0].rows, [0])

        _ = try? await client.planPayouts(PlanPayoutsParams(srcChain: "base", srcToken: "USDC", sender: "0xS", csv: "a,1,USDC,base"))
        XCTAssertEqual(last.bodyString, #"{"csv":"a,1,USDC,base","sender":"0xS","srcChain":"base","srcToken":"USDC"}"#)

        respond(#"{"vm":"evm","chainId":8453,"token":{"chainId":8453,"address":"0x83","symbol":"USDC","decimals":6},"calls":[{"to":"0x83","data":"0xa9059cbb","value":"0"}]}"#)
        let t = try await client.buildPayoutTransfers(BuildPayoutTransfersParams(
            chain: "base", token: "USDC", sender: "0xS", transfers: [PayoutTransfer(recipient: "0xA", amount: "25000000")]))
        XCTAssertEqual(last.rawPath, "/v1/payouts/transfers")
        assertJSON(last.body, #"{"chain":"base","token":"USDC","sender":"0xS","transfers":[{"recipient":"0xA","amount":"25000000"}]}"#)
        XCTAssertEqual(t.calls?.count, 1)
        XCTAssertNil(t.serializedTx)
    }

    // MARK: Recurring orders

    func testRecurringOrders() async throws {
        respond(#"{"object":"recurring_order_build","livemode":false,"provider":"sandbox","chainId":7565164,"wallet":"9Wz","srcToken":"EPj","dstToken":"So1","amount":"300000000","amountPerOrder":"100000000","orders":3,"intervalSeconds":86400,"fees":{"ourFeeBps":0,"integratorFeeBps":0},"requestId":"req_1","tx":{"vm":"svm","serializedTx":"AQAB","submitViaApi":true,"sandbox":true}}"#)
        let b = try await client.createRecurringOrder(CreateRecurringOrderParams(
            wallet: "9Wz", dstToken: "SOL", amount: "300000000", orders: 3, intervalSeconds: 86400))
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/recurring-orders")
        XCTAssertEqual(last.bodyString, #"{"amount":"300000000","dstToken":"SOL","intervalSeconds":86400,"orders":3,"wallet":"9Wz"}"#)
        XCTAssertEqual(b.requestId, "req_1")
        XCTAssertTrue(b.tx.submitViaApi)

        respond(#"{"txHash":"5sig","order":"ordAcc"}"#)
        let s = try await client.submitRecurringOrder(requestId: "req_1", signedTransaction: "AQ==")
        XCTAssertEqual(last.rawPath, "/v1/recurring-orders/submit")
        assertJSON(last.body, #"{"requestId":"req_1","signedTransaction":"AQ=="}"#)
        XCTAssertEqual(s.order, "ordAcc")

        respond(#"{"recurringOrders":[{"id":"ordAcc","object":"recurring_order","provider":"jupiter","chainId":7565164,"status":"active","wallet":"9Wz","srcToken":"EPj","dstToken":"So1","amount":"300000000","amountPerOrder":"100000000","orders":3,"ordersFilled":1,"intervalSeconds":86400,"spentAmount":"100000000","withdrawnAmount":"0","receivedAmount":"600000000","openTxHash":"5sig","closeTxHash":null,"createdAt":null,"fills":[{"txHash":"f1","amount":"100000000","dstAmount":"600000000","feeAmount":"100000","feeToken":null,"filledAt":null}]}],"page":1,"totalPages":1}"#)
        let l = try await client.listRecurringOrders(ListRecurringOrdersParams(wallet: "9Wz", status: "active", page: 2))
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.query, "page=2&status=active&wallet=9Wz")
        XCTAssertEqual(l.recurringOrders[0].fills[0].dstAmount, "600000000")
        XCTAssertNil(l.recurringOrders[0].closeTxHash)

        respond(#"{"requestId":"req_2","tx":{"vm":"svm","serializedTx":"AQAC"}}"#)
        let c = try await client.cancelRecurringOrder(id: "ordAcc", wallet: "9Wz")
        XCTAssertEqual(last.rawPath, "/v1/recurring-orders/ordAcc/cancel")
        XCTAssertEqual(last.bodyString, #"{"wallet":"9Wz"}"#)
        XCTAssertEqual(c.tx.serializedTx, "AQAC")
    }
}
