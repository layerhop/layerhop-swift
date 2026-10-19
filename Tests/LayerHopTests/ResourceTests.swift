import Foundation
import XCTest
@testable import LayerHop

let sessionJSON = #"{"id":"cs_01k7t9m2c4x8q6r0v3b5n7p9d","object":"checkout.session","livemode":true,"status":"processing","statusDetail":null,"amount":"49000000","settlement":{"chainId":8453,"token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","symbol":"USDC","decimals":6},"recipient":"0x2222222222222222222222222222222222222222","merchantName":"Acme","description":"Pro plan, 1 month","url":"https://layerhop.com/pay/cs_01k7t9m2c4x8q6r0v3b5n7p9d","successUrl":"https://shop.example.com/thanks","cancelUrl":null,"expiresAt":"2026-10-18T11:00:00.000Z","payment":{"quoteId":"q_9","payer":"0x1111111111111111111111111111111111111111","srcChainId":42161,"srcToken":"0x0000000000000000000000000000000000000000","srcAmount":"15623001000000000","srcTxHash":"0xabc","dstTxHash":null,"paidAt":null},"reference":"order_1042","metadata":{"plan":"pro"},"createdAt":"2026-10-18T10:00:00.000Z","updatedAt":"2026-10-18T10:02:00.000Z"}"#

let checkoutQuoteJSON = #"{"sessionId":"cs_01k7t9m2c4x8q6r0v3b5n7p9d","livemode":false,"amountDue":"49000000","best":{"quoteId":"q_1","provider":"sandbox","srcAmount":"15623001000000000","dstAmount":"49100000","dstAmountMin":"49000000","estimatedSeconds":8,"fees":{"ourFeeBps":20},"expiresAt":1760000030},"quotes":[{"quoteId":"q_1","provider":"sandbox","srcAmount":"15623001000000000","dstAmount":"49100000","dstAmountMin":"49000000","estimatedSeconds":8,"fees":{"ourFeeBps":20},"expiresAt":1760000030}],"errors":[{"provider":"lifi","code":"PROVIDER_TIMEOUT","message":"Timed out"}]}"#

let productJSON = #"{"id":"prod_01m57hq2c4x8q6r0v3b5n7p9d","object":"checkout.product","livemode":true,"active":true,"name":"Pro plan","description":"1 month","merchantName":null,"amount":"49000000","settlement":{"chainId":8453,"token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","symbol":"USDC","decimals":6},"url":"https://layerhop.com/buy/prod_01m57hq2c4x8q6r0v3b5n7p9d","recipient":"0x2222222222222222222222222222222222222222","successUrl":"https://shop.example.com/thanks","cancelUrl":null,"expiresInMinutes":60,"allowedOrigins":["https://shop.example.com"],"createdAt":"2026-10-18T10:00:00.000Z","updatedAt":"2026-10-18T10:00:00.000Z"}"#

let invoiceJSON = #"{"id":"inv_01m57hq2c4x8q6r0v3b5n7p9d","object":"invoice","livemode":true,"number":"INV-0001","status":"open","merchantName":"Acme","customerName":"Jane","memo":null,"lineItems":[{"description":"Design work","quantity":2,"unitAmount":"100000000"},{"description":"Hosting","quantity":1,"unitAmount":"25000000"}],"amount":"225000000","settlement":{"chainId":8453,"token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","symbol":"USDC","decimals":6},"dueAt":"2026-11-01T23:59:59.000Z","paidAt":null,"url":"https://layerhop.com/invoice/inv_01m57hq2c4x8q6r0v3b5n7p9d","receiptUrl":null,"createdAt":"2026-10-18T10:00:00.000Z","customerEmail":"jane@example.com","recipient":"0x2222222222222222222222222222222222222222","sessionId":null,"sentAt":"2026-10-18T10:00:00.000Z","receiptSentAt":null,"voidedAt":null,"updatedAt":"2026-10-18T10:00:00.000Z"}"#

let refundJSON = #"{"id":"re_01m57hq2c4x8q6r0v3b5n7p9d","object":"refund","sessionId":"cs_1","livemode":true,"status":"pending","statusDetail":null,"amount":"10000000","reason":"Damaged","quoteId":"q_r1","to":{"chainId":42161,"token":"0x0000000000000000000000000000000000000000","address":"0x1111111111111111111111111111111111111111"},"txHash":null,"createdAt":"2026-10-18T12:00:00.000Z","updatedAt":"2026-10-18T12:00:00.000Z"}"#

let depositAddressJSON = #"{"id":"da_01m5f3k2c4x8q6r0v3b5n7p9d","object":"deposit_address","livemode":false,"status":"active","provider":"sandbox","address":"0x4c3f1a0b9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4a","chainId":8453,"token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","dstChainId":42161,"dstToken":"0xaf88d065e77c8cC2239327C5EDb3A432268e5831","recipient":"0x2222222222222222222222222222222222222222","refundTo":"0x1111111111111111111111111111111111111111","reusable":true,"amount":null,"fees":{"ourFeeBps":20,"integratorFeeBps":0,"integrator":null},"label":"user_42","metadata":{"userId":"42"},"depositCount":0,"lastDepositAt":null,"createdAt":"2026-10-19T10:00:00.000Z"}"#

let depositOrderJSON = #"{"quoteId":"dep_5f0c1e2d","provider":"sandbox","status":"submitted","statusDetail":null,"channel":"api","ourFeeBps":20,"partnerFeeBps":0,"sender":"0x1111111111111111111111111111111111111111","recipient":"0x2222222222222222222222222222222222222222","srcChainId":8453,"srcToken":"0x83","dstChainId":42161,"dstToken":"0xaf","amount":"25000000","dstAmount":"24930000","srcTxHash":"0xabc","dstTxHash":null,"livemode":false,"checkoutSessionId":null,"refundId":null,"depositAddressId":"da_01m5f3k2c4x8q6r0v3b5n7p9d","keyId":"key_1","partnerId":null,"partnerFeeEstimate":"0","createdAt":"t","updatedAt":"t"}"#

let subscriptionJSON = #"{"id":"sub_01k7v0c2c4x8q6r0v3b5n7p9d","object":"subscription","livemode":true,"status":"active","customerEmail":"ada@example.com","customerName":"Ada Lovelace","merchantName":"Studio Nine","description":"Pro plan","memo":null,"productId":null,"amount":"49000000","settlement":{"chainId":8453,"token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","symbol":"USDC","decimals":6},"recipient":"0x2222222222222222222222222222222222222222","interval":"month","intervalCount":1,"daysUntilDue":3,"currentPeriodStart":"2026-10-18T10:00:00.000Z","currentPeriodEnd":"2026-11-18T10:00:00.000Z","nextInvoiceAt":"2026-11-18T10:00:00.000Z","cancelAt":null,"cancelAtPeriodEnd":false,"canceledAt":null,"cancellationReason":null,"pausedAt":null,"latestInvoiceId":"inv_01k7v0c2c4x8q6r0v3b5n7p9d","metadata":{"plan":"pro"},"createdAt":"2026-10-18T10:00:00.000Z","updatedAt":"2026-10-18T10:00:00.000Z"}"#

let limitOrderJSON = #"{"id":"lo_01m5h2k2c4x8q6r0v3b5n7p9d","object":"limit_order","livemode":false,"status":"built","statusDetail":null,"provider":"sandbox","chainId":7565164,"wallet":"9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM","srcToken":"EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v","dstToken":"So11111111111111111111111111111111111111112","amount":"100000000","dstAmount":"600000000","expiresAt":null,"fees":{"ourFeeBps":20,"integratorFeeBps":0,"integrator":null},"providerOrderId":"7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU","filledAmount":"0","filledDstAmount":"0","fillCount":0,"openTxHash":null,"cancelTxHash":null,"channel":"api","metadata":{"userId":"42"},"createdAt":"2026-10-19T10:00:00.000Z","updatedAt":"2026-10-19T10:00:00.000Z"}"#

let sandboxSvmTxJSON = #"{"vm":"svm","serializedTx":"AQAB","submitViaApi":true,"sandbox":true}"#

let fillOrderJSON = #"{"quoteId":"lof_5f0c1e2d","provider":"sandbox","status":"filled","statusDetail":null,"channel":"api","ourFeeBps":20,"partnerFeeBps":0,"sender":"9Wz","recipient":"9Wz","srcChainId":7565164,"srcToken":"EPj","dstChainId":7565164,"dstToken":"So1","amount":"50000000","dstAmount":"300000000","srcTxHash":"5sig","dstTxHash":"5sig","livemode":false,"checkoutSessionId":null,"refundId":null,"depositAddressId":null,"limitOrderId":"lo_01m5h2k2c4x8q6r0v3b5n7p9d","createdAt":"t","updatedAt":"t"}"#

/// Replaces `"key":<old>` with `"key":<new>` in a JSON fixture (first occurrence).
func patch(_ json: String, _ old: String, _ new: String) -> String {
    guard let r = json.range(of: old) else { return json }
    return json.replacingCharacters(in: r, with: new)
}

/// Asserts two JSON documents are equal regardless of key order.
func assertJSON(_ data: Data, _ want: String, file: StaticString = #filePath, line: UInt = #line) {
    let got = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    let exp = try? JSONSerialization.jsonObject(with: Data(want.utf8), options: [.fragmentsAllowed])
    XCTAssertNotNil(exp, "bad expected JSON", file: file, line: line)
    XCTAssertEqual(
        got.map { NSDictionary(dictionary: $0 as? [String: Any] ?? [:]) },
        exp.map { NSDictionary(dictionary: $0 as? [String: Any] ?? [:]) },
        "body \(String(decoding: data, as: UTF8.self))", file: file, line: line)
}

// MARK: - Checkout sessions and refunds

final class CheckoutTests: MockTestCase {
    func testCreateCheckoutSession() async throws {
        respond(sessionJSON)
        let s = try await client.createCheckoutSession(CreateCheckoutParams(
            amount: "49000000", settleChain: "base", settleToken: "USDC", recipient: "0x2222",
            description: "Pro plan, 1 month", reference: "order_1042", metadata: ["plan": "pro"],
            successUrl: "https://shop.example.com/thanks", expiresInMinutes: 30))
        XCTAssertEqual(s.id, "cs_01k7t9m2c4x8q6r0v3b5n7p9d")
        XCTAssertEqual(s.status, .processing)
        XCTAssertEqual(s.settlement.decimals, 6)
        XCTAssertEqual(s.payment?.srcChainId, 42161)
        XCTAssertNil(s.payment?.dstTxHash)
        XCTAssertNil(s.cancelUrl)
        XCTAssertNil(s.statusDetail)
        XCTAssertEqual(s.metadata, ["plan": "pro"])
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions")
        assertJSON(last.body, #"{"amount":"49000000","settleChain":"base","settleToken":"USDC","recipient":"0x2222","description":"Pro plan, 1 month","reference":"order_1042","metadata":{"plan":"pro"},"successUrl":"https://shop.example.com/thanks","expiresInMinutes":30}"#)
        // Slashes are not escaped.
        XCTAssertTrue(last.bodyString.contains("https://shop.example.com/thanks"))

        _ = try await client.createCheckoutSession(CreateCheckoutParams(amount: "1", settleChain: "8453", settleToken: "USDC", recipient: "0x2"))
        XCTAssertEqual(last.bodyString, #"{"amount":"1","recipient":"0x2","settleChain":"8453","settleToken":"USDC"}"#)
    }

    func testGetListExpire() async throws {
        respond(sessionJSON)
        _ = try await client.getCheckoutSession(id: "cs_1")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_1")
        XCTAssertTrue(last.body.isEmpty)

        _ = try await client.expireCheckoutSession(id: "a/b")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/a%2Fb/expire")
        XCTAssertEqual(last.bodyString, "{}")

        respond(#"{"sessions":[\#(sessionJSON)],"nextCursor":"c2"}"#)
        let r = try await client.listCheckoutSessions(ListCheckoutSessionsParams(status: .paid, cursor: "c1", limit: 10))
        XCTAssertEqual(r.sessions.count, 1)
        XCTAssertEqual(r.nextCursor, "c2")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions")
        XCTAssertEqual(last.query, "cursor=c1&limit=10&status=paid")

        respond(#"{"sessions":[],"nextCursor":null}"#)
        let r2 = try await client.listCheckoutSessions()
        XCTAssertEqual(last.query, "")
        XCTAssertNil(r2.nextCursor)
    }

    func testQuoteCheckoutSession() async throws {
        respond(checkoutQuoteJSON)
        let q = try await client.quoteCheckoutSession(
            id: "cs_01k7t9m2c4x8q6r0v3b5n7p9d", CheckoutQuoteParams(srcChain: "arbitrum", srcToken: "ETH", sender: "0x11"))
        XCTAssertEqual(q.amountDue, "49000000")
        XCTAssertEqual(q.best.srcAmount, "15623001000000000")
        XCTAssertEqual(q.best.dstAmountMin, "49000000")
        XCTAssertEqual(q.quotes.count, 1)
        XCTAssertFalse(q.livemode)
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_01k7t9m2c4x8q6r0v3b5n7p9d/quote")
        assertJSON(last.body, #"{"srcChain":"arbitrum","srcToken":"ETH","sender":"0x11"}"#)

        _ = try await client.quoteCheckoutSession(id: "cs_1", CheckoutQuoteParams(srcChain: "base", srcToken: "USDC", sender: "0x1", slippageBps: 75))
        XCTAssertEqual(last.json["slippageBps"] as? Int, 75)
    }

    func testRefunds() async throws {
        respond(#"{"refund":\#(refundJSON),"quote":{"quoteId":"q_r1","provider":"relay","srcAmount":"10000000","dstAmount":"3100000000000000","dstAmountMin":"3000000000000000","estimatedSeconds":12,"expiresAt":1760000030,"from":"0x2222222222222222222222222222222222222222"},"next":"Build, sign, report"}"#)
        let r = try await client.createRefund(sessionId: "cs_1", CreateRefundParams(amount: "10000000", reason: "Damaged", to: .original))
        XCTAssertEqual(r.refund.status, .pending)
        XCTAssertEqual(r.refund.to.chainId, 42161)
        XCTAssertNil(r.refund.txHash)
        XCTAssertEqual(r.quote.quoteId, "q_r1")
        XCTAssertEqual(r.quote.from, "0x2222222222222222222222222222222222222222")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_1/refunds")
        assertJSON(last.body, #"{"amount":"10000000","reason":"Damaged","to":"original"}"#)

        _ = try await client.createRefund(sessionId: "cs_1")
        XCTAssertEqual(last.bodyString, "{}")

        respond(#"{"refunds":[\#(refundJSON)]}"#)
        let l = try await client.listRefunds(sessionId: "cs_1")
        XCTAssertEqual(l.refunds.count, 1)
        XCTAssertEqual(l.refunds[0].reason, "Damaged")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_1/refunds")
    }
}

// MARK: - Products

final class ProductTests: MockTestCase {
    func testCreateProduct() async throws {
        respond(productJSON)
        let p = try await client.createCheckoutProduct(CreateCheckoutProductParams(
            name: "Pro plan", amount: "49000000", settleChain: "base", settleToken: "USDC", recipient: "0x2222",
            description: "1 month", successUrl: "https://shop.example.com/thanks", expiresInMinutes: 60,
            allowedOrigins: ["https://shop.example.com"]))
        XCTAssertTrue(p.active)
        XCTAssertNil(p.merchantName)
        XCTAssertEqual(p.allowedOrigins, ["https://shop.example.com"])
        XCTAssertEqual(p.expiresInMinutes, 60)
        XCTAssertEqual(last.rawPath, "/v1/checkout/products")
        assertJSON(last.body, #"{"name":"Pro plan","description":"1 month","amount":"49000000","settleChain":"base","settleToken":"USDC","recipient":"0x2222","successUrl":"https://shop.example.com/thanks","expiresInMinutes":60,"allowedOrigins":["https://shop.example.com"]}"#)

        _ = try await client.createCheckoutProduct(CreateCheckoutProductParams(
            name: "Tip", amount: "1", settleChain: "8453", settleToken: "USDC", recipient: "0x2", active: false))
        assertJSON(last.body, #"{"name":"Tip","amount":"1","settleChain":"8453","settleToken":"USDC","recipient":"0x2","active":false}"#)
    }

    func testGetAndPublicProduct() async throws {
        respond(#"{"id":"prod_1","object":"checkout.product","livemode":true,"active":true,"name":"Pro","amount":"1","settlement":{"chainId":8453,"token":"0x83","symbol":"USDC","decimals":6},"url":"https://layerhop.com/buy/prod_1"}"#)
        let p = try await client.getCheckoutProduct(id: "prod_1")
        XCTAssertNil(p.recipient)
        XCTAssertNil(p.createdAt)
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/checkout/products/prod_1")
        XCTAssertTrue(last.body.isEmpty)
    }

    func testListProducts() async throws {
        respond(#"{"products":[\#(productJSON)],"nextCursor":"c2"}"#)
        let r = try await client.listCheckoutProducts(ListCheckoutProductsParams(active: true, cursor: "c1", limit: 10))
        XCTAssertEqual(r.products.count, 1)
        XCTAssertEqual(last.query, "active=true&cursor=c1&limit=10")
        _ = try await client.listCheckoutProducts(ListCheckoutProductsParams(active: false))
        XCTAssertEqual(last.query, "active=false")
        _ = try await client.listCheckoutProducts()
        XCTAssertEqual(last.query, "")
    }

    func testUpdateProduct() async throws {
        respond(productJSON)
        _ = try await client.updateCheckoutProduct(id: "prod_1", UpdateCheckoutProductParams(active: false))
        XCTAssertEqual(last.method, "PATCH")
        XCTAssertEqual(last.rawPath, "/v1/checkout/products/prod_1")
        XCTAssertEqual(last.bodyString, #"{"active":false}"#)
        XCTAssertEqual(last.header("content-type"), "application/json")

        _ = try await client.updateCheckoutProduct(id: "prod_1", UpdateCheckoutProductParams(
            name: "Pro", description: "", amount: "50000000", settleChain: "42161", cancelUrl: "",
            expiresInMinutes: 30, allowedOrigins: []))
        XCTAssertEqual(last.bodyString, #"{"allowedOrigins":[],"amount":"50000000","cancelUrl":null,"description":null,"expiresInMinutes":30,"name":"Pro","settleChain":"42161"}"#)

        _ = try await client.updateCheckoutProduct(id: "prod_1", UpdateCheckoutProductParams())
        XCTAssertEqual(last.bodyString, "{}")
    }

    func testStartProductCheckout() async throws {
        respond(sessionJSON)
        _ = try await client.startProductCheckout(id: "prod_1", StartProductCheckoutParams(reference: "order_1042", metadata: ["plan": "pro"]))
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/checkout/products/prod_1/sessions")
        assertJSON(last.body, #"{"reference":"order_1042","metadata":{"plan":"pro"}}"#)
        let s = try await client.startProductCheckout(id: "prod_1")
        XCTAssertEqual(last.bodyString, "{}")
        XCTAssertNil(s.productId)
    }
}

// MARK: - Invoices

final class InvoiceTests: MockTestCase {
    let lines = [
        InvoiceLineItem(description: "Design work", quantity: 2, unitAmount: "100000000"),
        InvoiceLineItem(description: "Hosting", quantity: 1, unitAmount: "25000000"),
    ]

    func testCreateInvoice() async throws {
        respond(invoiceJSON)
        let inv = try await client.createInvoice(CreateInvoiceParams(
            lineItems: lines, settleChain: "base", settleToken: "USDC", recipient: "0x2222",
            customerEmail: "jane@example.com", customerName: "Jane", merchantName: "Acme", dueAt: "2026-11-01", send: true))
        XCTAssertEqual(inv.number, "INV-0001")
        XCTAssertEqual(inv.status, .open)
        XCTAssertEqual(inv.lineItems, lines)
        XCTAssertNil(inv.memo)
        XCTAssertNil(inv.sessionId)
        XCTAssertEqual(last.rawPath, "/v1/invoices")
        assertJSON(last.body, #"{"customerEmail":"jane@example.com","customerName":"Jane","merchantName":"Acme","lineItems":[{"description":"Design work","quantity":2,"unitAmount":"100000000"},{"description":"Hosting","quantity":1,"unitAmount":"25000000"}],"settleChain":"base","settleToken":"USDC","recipient":"0x2222","dueAt":"2026-11-01","send":true}"#)

        _ = try await client.createInvoice(CreateInvoiceParams(
            lineItems: [InvoiceLineItem(description: "x", quantity: 1, unitAmount: "1")], settleChain: "8453", settleToken: "USDC", recipient: "0x2"))
        assertJSON(last.body, #"{"lineItems":[{"description":"x","quantity":1,"unitAmount":"1"}],"settleChain":"8453","settleToken":"USDC","recipient":"0x2"}"#)
    }

    func testGetListUpdate() async throws {
        respond(invoiceJSON)
        _ = try await client.getInvoice(id: "inv_1")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/invoices/inv_1")

        respond(#"{"invoices":[\#(invoiceJSON)],"nextCursor":"c2"}"#)
        let r = try await client.listInvoices(ListInvoicesParams(status: .paid, cursor: "c1", limit: 10))
        XCTAssertEqual(r.invoices.count, 1)
        XCTAssertEqual(last.query, "cursor=c1&limit=10&status=paid")
        _ = try await client.listInvoices()
        XCTAssertEqual(last.query, "")

        respond(invoiceJSON)
        _ = try await client.updateInvoice(id: "inv_1", UpdateInvoiceParams(
            customerName: "", memo: "Thanks!", lineItems: [InvoiceLineItem(description: "Audit", quantity: 1, unitAmount: "5")],
            settleChain: "arbitrum", dueAt: ""))
        XCTAssertEqual(last.method, "PATCH")
        XCTAssertEqual(last.rawPath, "/v1/invoices/inv_1")
        XCTAssertEqual(last.bodyString, #"{"customerName":null,"dueAt":null,"lineItems":[{"description":"Audit","quantity":1,"unitAmount":"5"}],"memo":"Thanks!","settleChain":"arbitrum"}"#)
        _ = try await client.updateInvoice(id: "inv_1", UpdateInvoiceParams())
        XCTAssertEqual(last.bodyString, "{}")
    }

    func testSendVoidPublicPay() async throws {
        respond(invoiceJSON)
        _ = try await client.sendInvoice(id: "inv_1")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/invoices/inv_1/send")
        XCTAssertEqual(last.bodyString, "{}")

        respond(patch(invoiceJSON, #""status":"open""#, #""status":"void""#))
        let v = try await client.voidInvoice(id: "inv_1")
        XCTAssertEqual(v.status, .void)
        XCTAssertEqual(last.rawPath, "/v1/invoices/inv_1/void")

        respond(#"{"id":"inv_1","object":"invoice","livemode":true,"number":"INV-0001","status":"open","lineItems":[],"amount":"1","settlement":{"chainId":8453,"token":"0x83","symbol":"USDC","decimals":6},"url":"u","createdAt":"t"}"#)
        let pub = try await client.getPublicInvoice(id: "inv_1")
        XCTAssertNil(pub.customerEmail)
        XCTAssertNil(pub.recipient)
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/invoices/inv_1/public")

        respond(#"{"sessionId":"cs_test_1","url":"https://layerhop.com/pay/cs_test_1"}"#)
        let pay = try await client.payInvoice(id: "inv_1")
        XCTAssertEqual(pay.sessionId, "cs_test_1")
        XCTAssertEqual(pay.url, "https://layerhop.com/pay/cs_test_1")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/invoices/inv_1/pay")
        XCTAssertEqual(last.bodyString, "{}")
    }
}

// MARK: - Deposit addresses

final class DepositAddressTests: MockTestCase {
    func testCreateDepositAddress() async throws {
        let created = patch(depositAddressJSON, #""createdAt":"2026-10-19T10:00:00.000Z"}"#,
            #""createdAt":"2026-10-19T10:00:00.000Z","estimate":{"amount":"100000000","dstAmount":"99700000","dstAmountMin":"99200000","estimatedSeconds":10}}"#)
        respond(created)
        let d = try await client.createDepositAddress(CreateDepositAddressParams(
            srcChain: "base", srcToken: "USDC", dstChain: "42161", dstToken: "USDC", recipient: "0x2222",
            refundTo: "0x1111", reusable: true, amount: "100000000", label: "user_42", metadata: ["userId": "42"],
            integrator: "acme", integratorFeeBps: 10))
        XCTAssertEqual(d.status, .active)
        XCTAssertEqual(d.chainId, 8453)
        XCTAssertNil(d.amount)
        XCTAssertNil(d.fees.integrator)
        XCTAssertEqual(d.estimate?.dstAmount, "99700000")
        XCTAssertNil(d.deposits)
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/deposit-addresses")
        assertJSON(last.body, #"{"srcChain":"base","srcToken":"USDC","dstChain":"42161","dstToken":"USDC","recipient":"0x2222","refundTo":"0x1111","reusable":true,"amount":"100000000","label":"user_42","metadata":{"userId":"42"},"integrator":"acme","integratorFeeBps":10}"#)

        _ = try await client.createDepositAddress(CreateDepositAddressParams(
            srcChain: "8453", srcToken: "USDC", dstChain: "arbitrum", dstToken: "USDC", recipient: "0x2", refundTo: "0x1"))
        assertJSON(last.body, #"{"srcChain":"8453","srcToken":"USDC","dstChain":"arbitrum","dstToken":"USDC","recipient":"0x2","refundTo":"0x1"}"#)

        // Integrator defaults come from the client options.
        client = makeClient(.init(baseURL: "https://api.test", apiKey: "k1", integrator: "acme", integratorFeeBps: 5))
        _ = try await client.createDepositAddress(CreateDepositAddressParams(
            srcChain: "base", srcToken: "USDC", dstChain: "arbitrum", dstToken: "USDC", recipient: "0x2", refundTo: "0x1",
            reusable: false, amount: "5000000"))
        assertJSON(last.body, #"{"srcChain":"base","srcToken":"USDC","dstChain":"arbitrum","dstToken":"USDC","recipient":"0x2","refundTo":"0x1","reusable":false,"amount":"5000000","integrator":"acme","integratorFeeBps":5}"#)
    }

    func testGetListRefreshDisableSimulate() async throws {
        respond(patch(depositAddressJSON, #""depositCount":0"#, #""depositCount":1,"deposits":[\#(depositOrderJSON)]"#))
        let d = try await client.getDepositAddress(id: "da_1")
        XCTAssertEqual(d.depositCount, 1)
        XCTAssertEqual(d.deposits?.first?.depositAddressId, "da_01m5f3k2c4x8q6r0v3b5n7p9d")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/deposit-addresses/da_1")

        respond(#"{"depositAddresses":[\#(depositAddressJSON)],"nextCursor":"c2"}"#)
        let l = try await client.listDepositAddresses(ListDepositAddressesParams(status: .active, label: "user_42", cursor: "c1", limit: 10))
        XCTAssertEqual(l.depositAddresses.count, 1)
        XCTAssertEqual(last.query, "cursor=c1&label=user_42&limit=10&status=active")
        respond(#"{"depositAddresses":[]}"#)
        _ = try await client.listDepositAddresses()
        XCTAssertEqual(last.query, "")

        respond(depositAddressJSON)
        _ = try await client.refreshDepositAddress(id: "da_1")
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/deposit-addresses/da_1/refresh")
        XCTAssertEqual(last.bodyString, "{}")

        respond(patch(depositAddressJSON, #""status":"active""#, #""status":"disabled""#))
        let dis = try await client.disableDepositAddress(id: "da_1")
        XCTAssertEqual(dis.status, .disabled)
        XCTAssertEqual(last.rawPath, "/v1/deposit-addresses/da_1/disable")
        XCTAssertEqual(last.bodyString, "{}")

        respond(#"{"order":\#(depositOrderJSON)}"#)
        let sim = try await client.simulateDeposit(id: "da_1", amount: "25000000")
        XCTAssertEqual(sim.order.quoteId, "dep_5f0c1e2d")
        XCTAssertEqual(sim.order.livemode, false)
        XCTAssertNil(sim.order.dstTxHash)
        XCTAssertEqual(last.rawPath, "/v1/deposit-addresses/da_1/simulate")
        XCTAssertEqual(last.bodyString, #"{"amount":"25000000"}"#)
    }
}

// MARK: - Subscriptions

final class SubscriptionTests: MockTestCase {
    func testCreateSubscription() async throws {
        respond(subscriptionJSON)
        let s = try await client.createSubscription(CreateSubscriptionParams(
            customerEmail: "ada@example.com", interval: .month, intervalCount: 1, amount: "49000000",
            settleChain: "base", settleToken: "USDC", recipient: "0x2222", description: "Pro plan",
            customerName: "Ada Lovelace", daysUntilDue: 0, metadata: ["plan": "pro"]))
        XCTAssertEqual(s.status, .active)
        XCTAssertEqual(s.interval, .month)
        XCTAssertNil(s.memo)
        XCTAssertNil(s.productId)
        XCTAssertFalse(s.cancelAtPeriodEnd)
        XCTAssertEqual(last.rawPath, "/v1/subscriptions")
        assertJSON(last.body, #"{"customerEmail":"ada@example.com","interval":"month","intervalCount":1,"amount":"49000000","settleChain":"base","settleToken":"USDC","recipient":"0x2222","description":"Pro plan","customerName":"Ada Lovelace","daysUntilDue":0,"metadata":{"plan":"pro"}}"#)

        _ = try await client.createSubscription(CreateSubscriptionParams(
            customerEmail: "a@b.co", interval: .year, productId: "prod_1", startAt: "2026-11-01T00:00:00Z"))
        assertJSON(last.body, #"{"customerEmail":"a@b.co","interval":"year","productId":"prod_1","startAt":"2026-11-01T00:00:00Z"}"#)
    }

    func testGetListUpdate() async throws {
        respond(subscriptionJSON)
        _ = try await client.getSubscription(id: "sub_1")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/subscriptions/sub_1")

        respond(#"{"subscriptions":[\#(subscriptionJSON)],"nextCursor":"c2"}"#)
        let l = try await client.listSubscriptions(ListSubscriptionsParams(status: .pastDue, customerEmail: "ada@example.com", cursor: "c1", limit: 10))
        XCTAssertEqual(l.subscriptions.count, 1)
        XCTAssertEqual(last.query, "cursor=c1&customerEmail=ada%40example.com&limit=10&status=past_due")
        _ = try await client.listSubscriptions()
        XCTAssertEqual(last.query, "")

        respond(subscriptionJSON)
        _ = try await client.updateSubscription(id: "sub_1", UpdateSubscriptionParams(
            merchantName: "", amount: "59000000", daysUntilDue: 5, metadata: [:], cancelAtPeriodEnd: false))
        XCTAssertEqual(last.method, "PATCH")
        XCTAssertEqual(last.rawPath, "/v1/subscriptions/sub_1")
        XCTAssertEqual(last.bodyString, #"{"amount":"59000000","cancelAtPeriodEnd":false,"daysUntilDue":5,"merchantName":null,"metadata":null}"#)
        _ = try await client.updateSubscription(id: "sub_1", UpdateSubscriptionParams())
        XCTAssertEqual(last.bodyString, "{}")
    }

    func testCancelPauseResumeInvoices() async throws {
        respond(patch(subscriptionJSON, #""cancelAtPeriodEnd":false"#, #""cancelAtPeriodEnd":true"#))
        let s = try await client.cancelSubscription(id: "sub_1", atPeriodEnd: true)
        XCTAssertTrue(s.cancelAtPeriodEnd)
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/subscriptions/sub_1/cancel")
        XCTAssertEqual(last.bodyString, #"{"atPeriodEnd":true}"#)

        respond(patch(patch(subscriptionJSON, #""status":"active""#, #""status":"canceled""#), #""cancellationReason":null"#, #""cancellationReason":"requested""#))
        let c = try await client.cancelSubscription(id: "sub_1")
        XCTAssertEqual(c.status, .canceled)
        XCTAssertEqual(c.cancellationReason, "requested")
        XCTAssertEqual(last.bodyString, #"{"atPeriodEnd":false}"#)

        respond(patch(subscriptionJSON, #""status":"active""#, #""status":"paused""#))
        let p = try await client.pauseSubscription(id: "sub_1")
        XCTAssertEqual(p.status, .paused)
        XCTAssertEqual(last.rawPath, "/v1/subscriptions/sub_1/pause")
        XCTAssertEqual(last.bodyString, "{}")

        respond(subscriptionJSON)
        _ = try await client.resumeSubscription(id: "sub_1")
        XCTAssertEqual(last.rawPath, "/v1/subscriptions/sub_1/resume")
        XCTAssertEqual(last.bodyString, "{}")

        respond(#"{"invoices":[\#(patch(invoiceJSON, #""sessionId":null"#, #""sessionId":null,"subscriptionId":"sub_1""#))]}"#)
        let inv = try await client.listSubscriptionInvoices(id: "sub_1")
        XCTAssertEqual(inv.count, 1)
        XCTAssertEqual(inv[0].subscriptionId, "sub_1")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/subscriptions/sub_1/invoices")
    }
}

// MARK: - Limit orders

final class LimitOrderTests: MockTestCase {
    func testCreateLimitOrder() async throws {
        let created = patch(limitOrderJSON, #""updatedAt":"2026-10-19T10:00:00.000Z"}"#, #""updatedAt":"2026-10-19T10:00:00.000Z","tx":\#(sandboxSvmTxJSON)}"#)
        respond(created)
        let o = try await client.createLimitOrder(CreateLimitOrderParams(
            wallet: "9Wz", srcToken: "USDC", dstToken: "SOL", amount: "100000000", dstAmount: "600000000",
            chain: "solana", expiresAt: 1_760_003_600, metadata: ["userId": "42"], integrator: "acme", integratorFeeBps: 10))
        XCTAssertEqual(o.status, .built)
        XCTAssertEqual(o.chainId, LayerHop.solanaChainID)
        XCTAssertNil(o.expiresAt)
        XCTAssertNil(o.fills)
        let tx = try XCTUnwrap(o.tx?.svm)
        XCTAssertEqual(tx.serializedTx, "AQAB")
        XCTAssertTrue(tx.submitViaApi)
        XCTAssertTrue(tx.sandbox)
        XCTAssertEqual(last.rawPath, "/v1/limit-orders")
        assertJSON(last.body, #"{"chain":"solana","wallet":"9Wz","srcToken":"USDC","dstToken":"SOL","amount":"100000000","dstAmount":"600000000","expiresAt":1760003600,"channel":"api","metadata":{"userId":"42"},"integrator":"acme","integratorFeeBps":10}"#)

        client = makeClient(.init(baseURL: "https://api.test", channel: "widget", integrator: "acme", integratorFeeBps: 5))
        _ = try await client.createLimitOrder(CreateLimitOrderParams(wallet: "9Wz", srcToken: "USDC", dstToken: "SOL", amount: "1", dstAmount: "2"))
        assertJSON(last.body, #"{"wallet":"9Wz","srcToken":"USDC","dstToken":"SOL","amount":"1","dstAmount":"2","channel":"widget","integrator":"acme","integratorFeeBps":5}"#)
    }

    func testSubmitGetList() async throws {
        let open = patch(limitOrderJSON, #""status":"built""#, #""status":"open""#)
        respond(#"{"limitOrder":\#(open),"txHash":"5sig"}"#)
        let s = try await client.submitLimitOrder(id: "lo_1", signedTransaction: "c2lnbmVk")
        XCTAssertEqual(s.txHash, "5sig")
        XCTAssertEqual(s.limitOrder.status, .open)
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/limit-orders/lo_1/submit")
        XCTAssertEqual(last.bodyString, #"{"signedTransaction":"c2lnbmVk"}"#)

        respond(patch(open, #""fillCount":0"#, #""fillCount":1,"fills":[\#(fillOrderJSON)]"#))
        let g = try await client.getLimitOrder(id: "lo_1")
        XCTAssertEqual(g.fills?.first?.limitOrderId, "lo_01m5h2k2c4x8q6r0v3b5n7p9d")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/limit-orders/lo_1")

        respond(#"{"limitOrders":[\#(limitOrderJSON)],"nextCursor":"c2"}"#)
        let l = try await client.listLimitOrders(ListLimitOrdersParams(wallet: "9Wz", status: .open, cursor: "c1", limit: 10))
        XCTAssertEqual(l.limitOrders.count, 1)
        XCTAssertEqual(last.query, "cursor=c1&limit=10&status=open&wallet=9Wz")
        respond(#"{"limitOrders":[]}"#)
        _ = try await client.listLimitOrders()
        XCTAssertEqual(last.query, "")
    }

    func testCancelAndSimulate() async throws {
        let open = patch(limitOrderJSON, #""status":"built""#, #""status":"open""#)
        respond(#"{"limitOrder":\#(open),"tx":{"vm":"svm","serializedTx":"AQAC","submitViaApi":true}}"#)
        let r = try await client.cancelLimitOrder(id: "lo_1")
        XCTAssertEqual(r.tx?.svm?.serializedTx, "AQAC")
        XCTAssertEqual(r.limitOrder.status, .open)
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/limit-orders/lo_1/cancel")
        XCTAssertEqual(last.bodyString, "{}")

        respond(#"{"limitOrder":\#(patch(limitOrderJSON, #""status":"built""#, #""status":"cancelled""#)),"tx":null}"#)
        let r2 = try await client.cancelLimitOrder(id: "lo_1")
        XCTAssertNil(r2.tx)
        XCTAssertEqual(r2.limitOrder.status, .cancelled)

        respond(open)
        let o = try await client.simulateLimitOrder(id: "lo_1", outcome: .partialFill)
        XCTAssertEqual(o.status, .open)
        XCTAssertEqual(last.rawPath, "/v1/limit-orders/lo_1/simulate")
        XCTAssertEqual(last.bodyString, #"{"outcome":"partial_fill"}"#)
    }
}
