# layerhop-swift

[![license](https://img.shields.io/badge/license-MIT-7ddec8?labelColor=090d15)](https://opensource.org/license/mit) [![docs](https://img.shields.io/badge/docs-docs.layerhop.com-7ddec8?labelColor=090d15)](https://docs.layerhop.com/sdks/swift)

Swift client for the [LayerHop](https://layerhop.com) API, which gives you best-price cross-chain and same-chain swaps through one non-custodial API. It mirrors the TypeScript `@layerhop/sdk` and the Go, Python and Rust SDKs.

- A Swift Package with **zero dependencies** (Foundation, plus CryptoKit where available). iOS 15+, macOS 12+, tvOS 15+, watchOS 8+; builds on Linux too.
- `async`/`await` everywhere, `Codable` + `Sendable` models, a `Sendable` client.
- Amounts are always **integer strings in base units** (`"100000000"` = 100 USDC). They are never floats.
- **The SDK never holds private keys and never signs.** It fetches quotes and returns unsigned transactions. Your own wallet signs and broadcasts them.

## Install

Xcode: **File → Add Package Dependencies…** and enter `https://github.com/layerhop/layerhop-swift`.

`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/layerhop/layerhop-swift", from: "0.6.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "LayerHop", package: "layerhop-swift")]),
]
```

## Quickstart

```swift
import LayerHop

let lh = LayerHopClient(apiKey: ProcessInfo.processInfo.environment["LAYERHOP_API_KEY"])

// 1. Quote: 100 USDC on Base -> SOL on Solana
let q = try await lh.quote(QuoteParams(
    srcChain: "base", srcToken: "USDC", amount: "100000000",
    dstChain: "solana", dstToken: "SOL",
    sender: "0xYourEvmAddress", recipient: "YourSolanaAddress"))
print("best: \(q.best.provider) -> \(q.best.dstAmount) lamports")

// 2. Build the unsigned transaction
let tx = try await lh.buildTx(quoteId: q.best.quoteId)

// 3. Sign + broadcast with YOUR wallet
let txHash: String
switch tx {
case .evm(let evm):
    // send evm.approval first when set, then {to, data, value} on evm.chainId, then evm.extraTxs in order
    txHash = try await wallet.sendEvm(evm)
case .svm(let svm):
    let signed = try await wallet.signSolana(base64: svm.serializedTx)
    txHash = svm.submitViaApi
        ? try await lh.submit(quoteId: q.best.quoteId, signedTransaction: signed) // sign only; LayerHop broadcasts
        : try await wallet.broadcastSolana(signed)
}

// 4. Report the broadcast so LayerHop tracks it
_ = try await lh.reportSubmitted(quoteId: q.best.quoteId, txHash: txHash)

// 5. Watch until filled / refunded / failed (polls every 3 s, gives up after 30 min)
for try await st in lh.watch(provider: q.best.provider, id: txHash) {
    print(st.state)
}
```

Gas on arrival: `QuoteParams(..., gasOnArrival: true)` (sent as `gasOnArrival=true`, about $2 of native gas) or `gasOnArrivalUsd: 5` (sent as `gasOnArrivalUsd=5`). Check `q.best.gasOnArrival`.

## Options

```swift
let lh = LayerHopClient(options: .init(
    baseURL: "https://api.layerhop.com", // default
    apiKey: "lh_live_...",               // sent as x-api-key
    channel: "api",                      // default
    integrator: "myapp",                 // your partner id, sent on every quote
    integratorFeeBps: 25,                // honored only with a partner key
    userAgent: "layerhop-swift/0.6.0"    // default
), session: myURLSession)                // optional custom URLSession
```

## Resources

| Area | Methods |
|---|---|
| Registry | `health()`, `chains()`, `tokens(chain:)`, `serviceStatus()` |
| Swaps | `quote(_:)`, `buildTx(quoteId:)`, `simulate(quoteId:)`, `submit(quoteId:signedTransaction:)`, `reportSubmitted(quoteId:txHash:)` |
| Orders | `status(provider:id:)`, `watch(provider:id:interval:timeout:)`, `listOrders(_:)`, `streamOrder(quoteId:)` |
| Checkout | `createCheckoutSession`, `getCheckoutSession(id:)`, `listCheckoutSessions`, `expireCheckoutSession(id:)`, `quoteCheckoutSession(id:_:)`, `streamCheckoutSession(id:)` |
| Products | `createCheckoutProduct`, `getCheckoutProduct(id:)`, `listCheckoutProducts`, `updateCheckoutProduct(id:_:)`, `startProductCheckout(id:_:)` |
| Refunds | `createRefund(sessionId:_:)`, `listRefunds(sessionId:)` |
| Invoices | `createInvoice`, `getInvoice(id:)`, `listInvoices`, `updateInvoice(id:_:)`, `sendInvoice(id:)`, `voidInvoice(id:)`, `getPublicInvoice(id:)`, `payInvoice(id:)` |
| Deposit addresses | `createDepositAddress`, `getDepositAddress(id:)`, `listDepositAddresses`, `refreshDepositAddress(id:)`, `disableDepositAddress(id:)`, `simulateDeposit(id:amount:)` |
| Subscriptions | `createSubscription`, `getSubscription(id:)`, `listSubscriptions`, `updateSubscription(id:_:)`, `cancelSubscription(id:atPeriodEnd:)`, `pauseSubscription(id:)`, `resumeSubscription(id:)`, `listSubscriptionInvoices(id:)` |
| Limit orders (Solana) | `createLimitOrder`, `submitLimitOrder(id:signedTransaction:)`, `getLimitOrder(id:)`, `listLimitOrders`, `cancelLimitOrder(id:)`, `simulateLimitOrder(id:outcome:)` |
| Webhooks | `streamWebhookEvents()`, `triggerWebhookEvent(type:)`, `Webhook.verifySignature`, `Webhook.constructEvent`, `Webhook.sign` |

### Checkout

```swift
let s = try await lh.createCheckoutSession(CreateCheckoutParams(
    amount: "49000000", settleChain: "base", settleToken: "USDC",
    recipient: "0xYourPayoutAddress", reference: "order_1042"))
// send the customer to s.url; fulfil on the checkout.session.completed webhook
```

### Invoices

```swift
let inv = try await lh.createInvoice(CreateInvoiceParams(
    lineItems: [InvoiceLineItem(description: "Design work", quantity: 2, unitAmount: "100000000")],
    settleChain: "base", settleToken: "USDC", recipient: "0xYourPayoutAddress",
    customerEmail: "jane@example.com", send: true))
```

### Deposit addresses

```swift
let d = try await lh.createDepositAddress(CreateDepositAddressParams(
    srcChain: "base", srcToken: "USDC", dstChain: "arbitrum", dstToken: "USDC",
    recipient: "0xUserOnArbitrum", refundTo: "0xUserOnBase"))
print("send USDC on Base to \(d.address)")
```

### Subscriptions

```swift
let sub = try await lh.createSubscription(CreateSubscriptionParams(
    customerEmail: "ada@example.com", interval: .month, productId: "prod_..."))
```

### Limit orders

```swift
let lo = try await lh.createLimitOrder(CreateLimitOrderParams(
    wallet: "YourSolanaAddress", srcToken: "USDC", dstToken: "SOL",
    amount: "100000000", dstAmount: "600000000"))
// sign lo.tx (sign only), then:
_ = try await lh.submitLimitOrder(id: lo.id, signedTransaction: signedBase64)
```

Update params (`UpdateCheckoutProductParams`, `UpdateInvoiceParams`, `UpdateSubscriptionParams`) send only non-nil fields; an empty string clears a nullable field (sent as `null`).

## Errors

Every failure throws `LayerHopError` (or `CancellationError` when the task is cancelled):

```swift
do {
    _ = try await lh.buildTx(quoteId: quoteId)
} catch let e as LayerHopError {
    switch e {
    case .api(let code, let message, let status, let requestId):
        print(code, message, status, requestId ?? "", e.docsURL!) // e.g. QUOTE_EXPIRED: re-quote
    case .network(let urlError): print(urlError)
    case .decoding(let detail): print(detail)
    case .invalidResponse, .watchTimeout: print(e)
    }
}
```

`e.code`, `e.message`, `e.status` and `e.requestId` are also available as properties. Codes are listed at https://docs.layerhop.com/errors.

## Verify webhooks

LayerHop signs every delivery with `LayerHop-Signature: t=<unix>,v1=<hex HMAC-SHA256(secret, "<t>.<rawBody>")>`. Pass the raw body exactly as received:

```swift
do {
    let event = try Webhook.constructEvent(
        secret: webhookSecret, body: rawBody, header: request.value(forHTTPHeaderField: "LayerHop-Signature"))
    switch event.type {
    case .orderFilled: print(event.data.order?.dstTxHash ?? "")
    case .checkoutSessionCompleted: print(event.data.session?.reference ?? "")
    default: break
    }
} catch let e as WebhookSignatureError {
    // .malformedHeader, .timestampOutsideTolerance (default 300 s) or .signatureMismatch: respond 401
}
```

`Webhook.verifySignature(secret:body:header:tolerance:now:)` throws the same errors, `Webhook.isValidSignature` returns a `Bool`, and `Webhook.sign(secret:body:timestamp:)` builds a header to test your handler. Several `v1` values (secret rotation) are accepted, and the comparison is constant-time. HMAC uses CryptoKit, or a bundled pure-Swift SHA-256 on Linux.

## Test mode

Use an `lh_test_` key: requests are served by the `sandbox` provider, responses carry `livemode: false`, and built transactions have `sandbox == true` (never broadcast them).

## Development

```bash
swift build
swift test
```

The tests use a `URLProtocol` mock, so they need no network.

## License

MIT
