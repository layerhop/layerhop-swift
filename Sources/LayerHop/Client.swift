import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Talks to the LayerHop REST API. Safe to share across tasks.
///
/// The client never holds private keys: `buildTx` returns an unsigned transaction that your own
/// wallet signs and broadcasts.
public final class LayerHopClient: Sendable {
    /// Client configuration.
    public struct Options: Sendable {
        /// Defaults to https://api.layerhop.com. A trailing slash is removed.
        public var baseURL: String
        /// Sent as the x-api-key header.
        public var apiKey: String?
        /// The fee channel sent with every quote (default "api").
        public var channel: String
        /// Your partner id, sent as `integrator` on every quote.
        public var integrator: String?
        /// Overrides the partner fee; honored only with a partner API key.
        public var integratorFeeBps: Int?
        /// Defaults to "layerhop-swift/<version>".
        public var userAgent: String

        public init(
            baseURL: String = LayerHop.defaultBaseURL,
            apiKey: String? = nil,
            channel: String = "api",
            integrator: String? = nil,
            integratorFeeBps: Int? = nil,
            userAgent: String = LayerHop.defaultUserAgent
        ) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.channel = channel
            self.integrator = integrator
            self.integratorFeeBps = integratorFeeBps
            self.userAgent = userAgent
        }
    }

    /// The effective options (defaults applied).
    public let options: Options
    /// The base URL without a trailing slash.
    public let baseURL: String
    let session: URLSession

    /// Creates a client. `session` defaults to a session with a 30 s request timeout.
    public init(options: Options = Options(), session: URLSession? = nil) {
        var o = options
        var base = o.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        if base.isEmpty { base = LayerHop.defaultBaseURL }
        o.baseURL = base
        if o.channel.isEmpty { o.channel = "api" }
        if o.userAgent.isEmpty { o.userAgent = LayerHop.defaultUserAgent }
        if let k = o.apiKey, k.isEmpty { o.apiKey = nil }
        if let i = o.integrator, i.isEmpty { o.integrator = nil }
        self.options = o
        self.baseURL = base
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    /// Creates a client from individual options.
    public convenience init(
        apiKey: String? = nil,
        baseURL: String = LayerHop.defaultBaseURL,
        channel: String = "api",
        integrator: String? = nil,
        integratorFeeBps: Int? = nil,
        userAgent: String = LayerHop.defaultUserAgent,
        session: URLSession? = nil
    ) {
        self.init(
            options: Options(
                baseURL: baseURL, apiKey: apiKey, channel: channel, integrator: integrator,
                integratorFeeBps: integratorFeeBps, userAgent: userAgent),
            session: session)
    }

    // MARK: - Transport

    struct Empty: Encodable {}

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    func makeRequest(
        _ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil,
        accept: String = "application/json"
    ) throws -> URLRequest {
        var s = baseURL + "/v1" + path
        if !query.isEmpty {
            s += "?" + query.sorted { $0.0 < $1.0 }
                .map { "\(escapeComponent($0.0))=\(escapeComponent($0.1))" }
                .joined(separator: "&")
        }
        guard let url = URL(string: s) else {
            throw LayerHopError.network(URLError(.badURL))
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(accept, forHTTPHeaderField: "accept")
        req.setValue(options.userAgent, forHTTPHeaderField: "user-agent")
        if let key = options.apiKey { req.setValue(key, forHTTPHeaderField: "x-api-key") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        return req
    }

    func send<Out: Decodable>(
        _ method: String, _ path: String, query: [(String, String)] = [], as _: Out.Type = Out.self
    ) async throws -> Out {
        try await perform(method, path, query: query, body: nil)
    }

    func send<In: Encodable, Out: Decodable>(
        _ method: String, _ path: String, query: [(String, String)] = [], body: In,
        as _: Out.Type = Out.self
    ) async throws -> Out {
        let data: Data
        do {
            data = try Self.encoder.encode(body)
        } catch {
            throw LayerHopError.decoding("encode \(method) \(path): \(error)")
        }
        return try await perform(method, path, query: query, body: data)
    }

    private func perform<Out: Decodable>(
        _ method: String, _ path: String, query: [(String, String)], body: Data?
    ) async throws -> Out {
        let req = try makeRequest(method, path, query: query, body: body)
        let (data, res) = try await transport(req)
        guard (200...299).contains(res.statusCode) else {
            throw decodeAPIError(
                status: res.statusCode, headerRequestId: res.value(forHTTPHeaderField: "x-request-id"),
                body: data)
        }
        do {
            return try JSONDecoder().decode(Out.self, from: data)
        } catch {
            throw LayerHopError.decoding("decode \(method) \(path): \(error)")
        }
    }

    /// Runs one request, mapping transport errors and honoring task cancellation.
    func transport(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let box = TaskBox()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                    let task = session.dataTask(with: request) { data, response, error in
                        if let error {
                            cont.resume(throwing: error)
                        } else if let http = response as? HTTPURLResponse {
                            cont.resume(returning: (data ?? Data(), http))
                        } else {
                            cont.resume(throwing: LayerHopError.invalidResponse)
                        }
                    }
                    box.start(task)
                }
            } onCancel: {
                box.cancel()
            }
        } catch {
            throw mapTransportError(error)
        }
    }
}

/// Maps a URLSession error to a LayerHopError (or CancellationError when the task was cancelled).
func mapTransportError(_ error: Error) -> Error {
    if error is LayerHopError || error is CancellationError { return error }
    if let u = error as? URLError {
        if u.code == .cancelled { return CancellationError() }
        return LayerHopError.network(u)
    }
    if Task.isCancelled { return CancellationError() }
    let ns = error as NSError
    return LayerHopError.network(
        URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: ns.localizedDescription]))
}

/// Holds a URLSessionTask so a cancellation handler can reach it, even if it fires first.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func start(_ t: URLSessionTask) {
        lock.lock()
        task = t
        let c = cancelled
        lock.unlock()
        if c { t.cancel() } else { t.resume() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }
}

private let unreserved: CharacterSet = {
    var s = CharacterSet()
    s.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    return s
}()

/// Percent-encodes everything except RFC 3986 unreserved characters.
func escapeComponent(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
}

// MARK: - Endpoints

extension LayerHopClient {
    /// `GET /v1/health`.
    public func health() async throws -> Health {
        try await send("GET", "/health")
    }

    /// Every chain LayerHop can route from or to (`GET /v1/chains`).
    public func chains() async throws -> [Chain] {
        struct R: Decodable { let chains: [Chain] }
        return try await send("GET", "/chains", as: R.self).chains
    }

    /// The built-in tokens of one chain, by id or slug (`GET /v1/tokens`).
    public func tokens(chain: String) async throws -> [Token] {
        struct R: Decodable { let tokens: [Token] }
        return try await send("GET", "/tokens", query: [("chain", chain)], as: R.self).tokens
    }

    /// Asks every provider for a price (`GET /v1/quote`). `best` is the highest output for the user.
    public func quote(_ p: QuoteParams) async throws -> QuoteResponse {
        let slip = (p.slippageBps ?? 0) == 0 ? 50 : p.slippageBps!
        var q: [(String, String)] = [
            ("srcChain", p.srcChain), ("srcToken", p.srcToken), ("amount", p.amount),
            ("dstChain", p.dstChain), ("dstToken", p.dstToken), ("sender", p.sender),
            ("recipient", p.recipient), ("slippageBps", String(slip)), ("channel", options.channel),
        ]
        if let i = options.integrator { q.append(("integrator", i)) }
        if let f = options.integratorFeeBps { q.append(("integratorFeeBps", String(f))) }
        if let usd = p.gasOnArrivalUsd, usd > 0 {
            q.append(("gasOnArrivalUsd", formatNumber(usd)))
        } else if p.gasOnArrival {
            q.append(("gasOnArrival", "true"))
        }
        return try await send("GET", "/quote", query: q)
    }

    /// Returns the unsigned transaction to sign for a quote (`POST /v1/orders`). EVM transactions
    /// may include an `approval` to send first.
    public func buildTx(quoteId: String) async throws -> BuiltTx {
        struct R: Decodable { let tx: BuiltTx }
        return try await send("POST", "/orders", body: ["quoteId": quoteId], as: R.self).tx
    }

    /// Sends a wallet-signed Solana transaction (base64) for `submitViaApi` quotes
    /// (`POST /v1/orders/submit`). Returns the transaction signature.
    public func submit(quoteId: String, signedTransaction: String) async throws -> String {
        struct R: Decodable { let txHash: String }
        let body = ["quoteId": quoteId, "signedTransaction": signedTransaction]
        return try await send("POST", "/orders/submit", body: body, as: R.self).txHash
    }

    /// Tells LayerHop the transaction for a quote was broadcast, so it can be tracked
    /// (`POST /v1/orders/{quoteId}/submitted`). Idempotent.
    public func reportSubmitted(quoteId: String, txHash: String) async throws -> ReportSubmittedResponse {
        try await send("POST", "/orders/\(escapeComponent(quoteId))/submitted", body: ["txHash": txHash])
    }

    /// Builds the transaction for a quote and dry-runs it without recording an order
    /// (`POST /v1/simulate`).
    public func simulate(quoteId: String) async throws -> SimulateResponse {
        try await send("POST", "/simulate", body: ["quoteId": quoteId])
    }

    /// The current state of an order (`GET /v1/orders/{provider}/{id}`). `id` is the provider order
    /// id or the source transaction hash.
    public func status(provider: ProviderID, id: String) async throws -> OrderStatus {
        try await send("GET", "/orders/\(escapeComponent(provider))/\(escapeComponent(id))")
    }

    /// Lists orders by sender or recipient (`GET /v1/orders`).
    public func listOrders(_ p: ListOrdersParams = ListOrdersParams()) async throws -> ListOrdersResponse {
        var q: [(String, String)] = []
        q.add("address", p.address)
        q.add("status", p.status)
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/orders", query: q)
    }

    /// Polls `status` until the order is final (filled / refunded / failed), yielding each state
    /// change. Throws `LayerHopError.watchTimeout` when `timeout` passes first; any request error
    /// ends the stream with that error. Stopping iteration (or cancelling the task) stops polling.
    ///
    /// ```swift
    /// for try await st in client.watch(provider: "relay", id: txHash) { print(st.state) }
    /// ```
    public func watch(
        provider: ProviderID, id: String, interval: TimeInterval = 3, timeout: TimeInterval = 1800
    ) -> AsyncThrowingStream<OrderStatus, Error> {
        let interval = interval > 0 ? interval : 3
        let timeout = timeout > 0 ? timeout : 1800
        return AsyncThrowingStream { continuation in
            let task = Task {
                let deadline = Date().addingTimeInterval(timeout)
                var last: OrderState?
                do {
                    while true {
                        let st = try await self.status(provider: provider, id: id)
                        if st.state != last {
                            last = st.state
                            continuation.yield(st)
                        }
                        if st.state.isFinal {
                            continuation.finish()
                            return
                        }
                        if !(Date().addingTimeInterval(interval) < deadline) {
                            throw LayerHopError.watchTimeout
                        }
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Checkout sessions

    /// Creates a checkout session ("pay with any token") with its hosted URL
    /// (`POST /v1/checkout/sessions`). Needs an API key; an lh_test_ key creates a test-mode session.
    public func createCheckoutSession(_ p: CreateCheckoutParams) async throws -> CheckoutSession {
        try await send("POST", "/checkout/sessions", body: p)
    }

    /// A checkout session (`GET /v1/checkout/sessions/{id}`). Public: without the owner's API key,
    /// `reference` and `metadata` are nil.
    public func getCheckoutSession(id: String) async throws -> CheckoutSession {
        try await send("GET", "/checkout/sessions/\(escapeComponent(id))")
    }

    /// Your sessions of the key's mode, newest first (`GET /v1/checkout/sessions`).
    public func listCheckoutSessions(_ p: ListCheckoutSessionsParams = ListCheckoutSessionsParams()) async throws
        -> ListCheckoutSessionsResponse
    {
        var q: [(String, String)] = []
        q.add("status", p.status?.rawValue)
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/checkout/sessions", query: q)
    }

    /// Cancels an open session so it can no longer be paid (`POST /v1/checkout/sessions/{id}/expire`).
    /// Any other status is a CONFLICT error.
    public func expireCheckoutSession(id: String) async throws -> CheckoutSession {
        try await send("POST", "/checkout/sessions/\(escapeComponent(id))/expire", body: Empty())
    }

    /// Prices paying a session with `srcToken` on `srcChain` from `sender`
    /// (`POST /v1/checkout/sessions/{id}/quote`). Public. Pay the chosen quote with `buildTx` and
    /// `reportSubmitted` as usual.
    public func quoteCheckoutSession(id: String, _ p: CheckoutQuoteParams) async throws -> CheckoutQuoteResponse {
        try await send("POST", "/checkout/sessions/\(escapeComponent(id))/quote", body: p)
    }

    // MARK: Products

    /// Creates a product: a fixed price for payment buttons, layerhop.com/buy/{id} links and store
    /// plugins (`POST /v1/checkout/products`). Needs an API key; its mode decides the product's mode.
    public func createCheckoutProduct(_ p: CreateCheckoutProductParams) async throws -> CheckoutProduct {
        try await send("POST", "/checkout/products", body: p)
    }

    /// A product (`GET /v1/checkout/products/{id}`). Public: name, price and settlement; with the
    /// owner's API key, every field.
    public func getCheckoutProduct(id: String) async throws -> CheckoutProduct {
        try await send("GET", "/checkout/products/\(escapeComponent(id))")
    }

    /// Your products of the key's mode (`GET /v1/checkout/products`).
    public func listCheckoutProducts(_ p: ListCheckoutProductsParams = ListCheckoutProductsParams()) async throws
        -> ListCheckoutProductsResponse
    {
        var q: [(String, String)] = []
        if let a = p.active { q.append(("active", a ? "true" : "false")) }
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/checkout/products", query: q)
    }

    /// Changes only the fields that are set (`PATCH /v1/checkout/products/{id}`). `active: false`
    /// stops new sessions; existing sessions keep their terms.
    public func updateCheckoutProduct(id: String, _ p: UpdateCheckoutProductParams) async throws -> CheckoutProduct {
        try await send("PATCH", "/checkout/products/\(escapeComponent(id))", body: p)
    }

    /// Starts a checkout session on a product's terms (`POST /v1/checkout/products/{id}/sessions`).
    /// Public, no key needed. An inactive product is a CONFLICT error. Send the payer to the
    /// session's `url`.
    public func startProductCheckout(id: String, _ p: StartProductCheckoutParams = StartProductCheckoutParams())
        async throws -> CheckoutSession
    {
        try await send("POST", "/checkout/products/\(escapeComponent(id))/sessions", body: p)
    }

    // MARK: Invoices

    /// Creates an invoice (`POST /v1/invoices`). It starts as a draft unless `send` is true, which
    /// finalizes it and emails it to `customerEmail`. Needs an API key.
    public func createInvoice(_ p: CreateInvoiceParams) async throws -> Invoice {
        try await send("POST", "/invoices", body: p)
    }

    /// One of your invoices (`GET /v1/invoices/{id}`).
    public func getInvoice(id: String) async throws -> Invoice {
        try await send("GET", "/invoices/\(escapeComponent(id))")
    }

    /// Your invoices of the key's mode, newest first (`GET /v1/invoices`).
    public func listInvoices(_ p: ListInvoicesParams = ListInvoicesParams()) async throws -> ListInvoicesResponse {
        var q: [(String, String)] = []
        q.add("status", p.status?.rawValue)
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/invoices", query: q)
    }

    /// Edits a draft invoice; only the fields that are set change (`PATCH /v1/invoices/{id}`). Any
    /// other status is a CONFLICT error.
    public func updateInvoice(id: String, _ p: UpdateInvoiceParams) async throws -> Invoice {
        try await send("PATCH", "/invoices/\(escapeComponent(id))", body: p)
    }

    /// Finalizes a draft (status "open") and emails it; on an open invoice it re-sends the email
    /// (`POST /v1/invoices/{id}/send`). Paid or void is a CONFLICT error.
    public func sendInvoice(id: String) async throws -> Invoice {
        try await send("POST", "/invoices/\(escapeComponent(id))/send", body: Empty())
    }

    /// Cancels a draft or open invoice (`POST /v1/invoices/{id}/void`). Paid or void is a CONFLICT
    /// error.
    public func voidInvoice(id: String) async throws -> Invoice {
        try await send("POST", "/invoices/\(escapeComponent(id))/void", body: Empty())
    }

    /// The customer's view of a sent invoice (`GET /v1/invoices/{id}/public`). Public, no key needed;
    /// owner-only fields are nil. Drafts are NOT_FOUND.
    public func getPublicInvoice(id: String) async throws -> Invoice {
        try await send("GET", "/invoices/\(escapeComponent(id))/public")
    }

    /// Starts (or reuses) the checkout session that pays an open invoice
    /// (`POST /v1/invoices/{id}/pay`). Public. Send the payer to the returned `url`.
    public func payInvoice(id: String) async throws -> PayInvoiceResponse {
        try await send("POST", "/invoices/\(escapeComponent(id))/pay", body: Empty())
    }

    // MARK: Deposit addresses

    /// Creates a deposit address (`POST /v1/deposit-addresses`): your user sends `srcToken` to the
    /// returned `address` on `srcChain`, without connecting a wallet, and the provider delivers
    /// `dstToken` to `recipient`. LayerHop never holds the funds. Needs an API key. `integrator` and
    /// `integratorFeeBps` default to the client's options.
    public func createDepositAddress(_ p: CreateDepositAddressParams) async throws -> DepositAddress {
        var p = p
        if p.integrator == nil || p.integrator == "" { p.integrator = options.integrator }
        if p.integratorFeeBps == nil { p.integratorFeeBps = options.integratorFeeBps }
        return try await send("POST", "/deposit-addresses", body: p)
    }

    /// One of your deposit addresses with its 20 most recent deposits
    /// (`GET /v1/deposit-addresses/{id}`).
    public func getDepositAddress(id: String) async throws -> DepositAddress {
        try await send("GET", "/deposit-addresses/\(escapeComponent(id))")
    }

    /// Your deposit addresses of the key's mode, newest first (`GET /v1/deposit-addresses`).
    public func listDepositAddresses(_ p: ListDepositAddressesParams = ListDepositAddressesParams()) async throws
        -> ListDepositAddressesResponse
    {
        var q: [(String, String)] = []
        q.add("status", p.status?.rawValue)
        q.add("label", p.label)
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/deposit-addresses", query: q)
    }

    /// Checks the address for deposits now (`POST /v1/deposit-addresses/{id}/refresh`). A disabled
    /// address is a CONFLICT error.
    public func refreshDepositAddress(id: String) async throws -> DepositAddress {
        try await send("POST", "/deposit-addresses/\(escapeComponent(id))/refresh", body: Empty())
    }

    /// Stops tracking the address (`POST /v1/deposit-addresses/{id}/disable`).
    public func disableDepositAddress(id: String) async throws -> DepositAddress {
        try await send("POST", "/deposit-addresses/\(escapeComponent(id))/disable", body: Empty())
    }

    /// Records a test deposit of `amount` (base units of the source token) on a test-mode address
    /// (`POST /v1/deposit-addresses/{id}/simulate`). Test keys only.
    public func simulateDeposit(id: String, amount: String) async throws -> SimulateDepositResponse {
        try await send("POST", "/deposit-addresses/\(escapeComponent(id))/simulate", body: ["amount": amount])
    }

    // MARK: Subscriptions

    /// Creates a subscription (`POST /v1/subscriptions`). LayerHop issues and emails an invoice every
    /// period; the customer pays it with any token. Needs an API key.
    public func createSubscription(_ p: CreateSubscriptionParams) async throws -> Subscription {
        try await send("POST", "/subscriptions", body: p)
    }

    /// One of your subscriptions (`GET /v1/subscriptions/{id}`).
    public func getSubscription(id: String) async throws -> Subscription {
        try await send("GET", "/subscriptions/\(escapeComponent(id))")
    }

    /// Your subscriptions of the key's mode, newest first (`GET /v1/subscriptions`).
    public func listSubscriptions(_ p: ListSubscriptionsParams = ListSubscriptionsParams()) async throws
        -> ListSubscriptionsResponse
    {
        var q: [(String, String)] = []
        q.add("status", p.status?.rawValue)
        q.add("customerEmail", p.customerEmail)
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/subscriptions", query: q)
    }

    /// Changes only the fields that are set, from the next invoice on
    /// (`PATCH /v1/subscriptions/{id}`). A canceled subscription is a CONFLICT error.
    public func updateSubscription(id: String, _ p: UpdateSubscriptionParams) async throws -> Subscription {
        try await send("PATCH", "/subscriptions/\(escapeComponent(id))", body: p)
    }

    /// Cancels a subscription (`POST /v1/subscriptions/{id}/cancel`): now when `atPeriodEnd` is false,
    /// or at the end of the current period when true (undo it with `updateSubscription`).
    public func cancelSubscription(id: String, atPeriodEnd: Bool = false) async throws -> Subscription {
        try await send("POST", "/subscriptions/\(escapeComponent(id))/cancel", body: ["atPeriodEnd": atPeriodEnd])
    }

    /// Pauses an active subscription (`POST /v1/subscriptions/{id}/pause`).
    public func pauseSubscription(id: String) async throws -> Subscription {
        try await send("POST", "/subscriptions/\(escapeComponent(id))/pause", body: Empty())
    }

    /// Resumes a paused subscription (`POST /v1/subscriptions/{id}/resume`).
    public func resumeSubscription(id: String) async throws -> Subscription {
        try await send("POST", "/subscriptions/\(escapeComponent(id))/resume", body: Empty())
    }

    /// The invoices issued for a subscription (up to 100), newest first
    /// (`GET /v1/subscriptions/{id}/invoices`).
    public func listSubscriptionInvoices(id: String) async throws -> [Invoice] {
        struct R: Decodable { let invoices: [Invoice] }
        return try await send("GET", "/subscriptions/\(escapeComponent(id))/invoices", as: R.self).invoices
    }

    // MARK: Limit orders

    /// Creates a Solana limit order (beta, Jupiter Trigger) with the unsigned `tx`
    /// (`POST /v1/limit-orders`). Have `wallet` sign it (sign only), then `submitLimitOrder`.
    /// `channel`, `integrator` and `integratorFeeBps` default to the client's options.
    public func createLimitOrder(_ p: CreateLimitOrderParams) async throws -> LimitOrder {
        var p = p
        if p.channel == nil || p.channel == "" { p.channel = options.channel }
        if p.integrator == nil || p.integrator == "" { p.integrator = options.integrator }
        if p.integratorFeeBps == nil { p.integratorFeeBps = options.integratorFeeBps }
        return try await send("POST", "/limit-orders", body: p)
    }

    /// Sends the wallet-signed create or cancel transaction (base64) of a limit order
    /// (`POST /v1/limit-orders/{id}/submit`). Nothing to submit is a CONFLICT error.
    public func submitLimitOrder(id: String, signedTransaction: String) async throws -> SubmitLimitOrderResponse {
        try await send(
            "POST", "/limit-orders/\(escapeComponent(id))/submit", body: ["signedTransaction": signedTransaction])
    }

    /// A limit order with its fills, newest first (`GET /v1/limit-orders/{id}`).
    public func getLimitOrder(id: String) async throws -> LimitOrder {
        try await send("GET", "/limit-orders/\(escapeComponent(id))")
    }

    /// The limit orders of `wallet`, or without it of the API key's account, newest first
    /// (`GET /v1/limit-orders`). `wallet` is required without an API key.
    public func listLimitOrders(_ p: ListLimitOrdersParams = ListLimitOrdersParams()) async throws
        -> ListLimitOrdersResponse
    {
        var q: [(String, String)] = []
        q.add("wallet", p.wallet)
        q.add("status", p.status?.rawValue)
        q.add("cursor", p.cursor)
        q.add("limit", p.limit)
        return try await send("GET", "/limit-orders", query: q)
    }

    /// Cancels a limit order (`POST /v1/limit-orders/{id}/cancel`). For an open order it returns the
    /// cancel `tx` to sign and `submitLimitOrder`; a never-submitted order is cancelled at once
    /// (`tx` nil).
    public func cancelLimitOrder(id: String) async throws -> CancelLimitOrderResponse {
        try await send("POST", "/limit-orders/\(escapeComponent(id))/cancel", body: Empty())
    }

    /// Fills, half-fills or expires an open test-mode order (`POST /v1/limit-orders/{id}/simulate`).
    /// Test keys only.
    public func simulateLimitOrder(id: String, outcome: LimitOrderSimulation) async throws -> LimitOrder {
        try await send("POST", "/limit-orders/\(escapeComponent(id))/simulate", body: ["outcome": outcome.rawValue])
    }

    // MARK: Refunds

    /// Refunds (part of) a paid checkout session (`POST /v1/checkout/sessions/{id}/refunds`).
    /// Non-custodial: the response holds a quote; build it with `buildTx`, sign it from
    /// `quote.from`, then `reportSubmitted`.
    public func createRefund(sessionId: String, _ p: CreateRefundParams = CreateRefundParams()) async throws
        -> CreateRefundResponse
    {
        try await send("POST", "/checkout/sessions/\(escapeComponent(sessionId))/refunds", body: p)
    }

    /// A session's refunds, newest first (`GET /v1/checkout/sessions/{id}/refunds`).
    public func listRefunds(sessionId: String) async throws -> ListRefundsResponse {
        try await send("GET", "/checkout/sessions/\(escapeComponent(sessionId))/refunds")
    }

    // MARK: Status and webhooks

    /// LayerHop's public service status, the same data as status.layerhop.com (`GET /v1/status`).
    /// (`status(provider:id:)`, by contrast, tracks one order.)
    public func serviceStatus() async throws -> StatusResponse {
        try await send("GET", "/status")
    }

    /// Creates a sample event of `type` in test mode (`POST /v1/webhooks/trigger`). Test keys only:
    /// a live key gets a FORBIDDEN error.
    public func triggerWebhookEvent(type: WebhookEventType) async throws -> TriggerWebhookResponse {
        try await send("POST", "/webhooks/trigger", body: ["type": type.rawValue])
    }
}

extension Array where Element == (String, String) {
    mutating func add(_ key: String, _ value: String?) {
        if let value, !value.isEmpty { append((key, value)) }
    }

    mutating func add(_ key: String, _ value: Int?) {
        if let value, value > 0 { append((key, String(value))) }
    }
}
