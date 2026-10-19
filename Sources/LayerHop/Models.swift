import Foundation

// MARK: - Registry

/// The body of `GET /v1/health`.
public struct Health: Codable, Sendable, Equatable {
    public let ok: Bool
    public let providers: [ProviderID]?
}

/// One entry of the chain registry.
public struct Chain: Codable, Sendable, Equatable {
    public let id: Int64
    public let slug: String
    public let name: String
    /// "evm" or "svm".
    public let vm: String
    public let nativeSymbol: String?
    public let nativeDecimals: Int?
    public let explorerTx: String?
}

/// One entry of the built-in token list.
public struct Token: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let address: String
    public let symbol: String
    public let decimals: Int
}

// MARK: - Quotes

/// The inputs of `GET /v1/quote`.
public struct QuoteParams: Sendable, Equatable {
    /// A chain id or slug ("base", "solana", "8453").
    public var srcChain: String
    /// A symbol from the token list ("USDC") or an address / mint.
    public var srcToken: String
    /// An integer string in base units of `srcToken`.
    public var amount: String
    public var dstChain: String
    public var dstToken: String
    public var sender: String
    public var recipient: String
    /// Defaults to 50 when nil or 0.
    public var slippageBps: Int?
    /// Also delivers native gas to `recipient` on the destination chain, worth $2 by default (sent as
    /// `gasOnArrival=true`). Ignored for same-chain swaps, non-EVM destinations and native outputs;
    /// providers that can't do it ignore it (check `Quote.gasOnArrival`).
    public var gasOnArrival: Bool
    /// Sets the USD value of that gas (0.5-20) and implies `gasOnArrival` (sent as `gasOnArrivalUsd`).
    public var gasOnArrivalUsd: Double?

    public init(
        srcChain: String, srcToken: String, amount: String,
        dstChain: String, dstToken: String,
        sender: String, recipient: String,
        slippageBps: Int? = nil, gasOnArrival: Bool = false, gasOnArrivalUsd: Double? = nil
    ) {
        self.srcChain = srcChain
        self.srcToken = srcToken
        self.amount = amount
        self.dstChain = dstChain
        self.dstToken = dstToken
        self.sender = sender
        self.recipient = recipient
        self.slippageBps = slippageBps
        self.gasOnArrival = gasOnArrival
        self.gasOnArrivalUsd = gasOnArrivalUsd
    }
}

/// Native gas a route delivers to the recipient on top of `dstAmount`. Its cost is already taken out
/// of `dstAmount`.
public struct GasOnArrival: Codable, Sendable, Equatable {
    /// Base units of the destination chain's native token.
    public let amount: String
    /// The native token address on the destination chain (0x000…000).
    public let token: String
    public let symbol: String
    public let decimals: Int
    /// The USD value at quote time, nil when unknown.
    public let usd: Double?
}

/// The fees applied to a quote.
public struct FeeBreakdown: Codable, Sendable, Equatable {
    public let ourFeeBps: Int
    public let providerFeeUsd: Double?
    public let gasUsd: Double?
    public let integratorFeeBps: Int?
    public let integrator: String?
}

/// One provider's priced route.
public struct Quote: Codable, Sendable, Equatable {
    public let quoteId: String
    public let provider: ProviderID
    public let dstAmount: String
    public let dstAmountMin: String
    public let estimatedSeconds: Int
    public let fees: FeeBreakdown
    /// Unix seconds.
    public let expiresAt: Int64
    /// Set when gas on arrival was requested and this route includes it.
    public let gasOnArrival: GasOnArrival?
}

/// A provider that failed while the request as a whole succeeded.
public struct ProviderFailure: Codable, Sendable, Equatable {
    public let provider: String
    public let code: String
    public let message: String
}

/// The body of `GET /v1/quote`. `best == quotes[0]`.
public struct QuoteResponse: Codable, Sendable, Equatable {
    public let best: Quote
    public let quotes: [Quote]
    public let errors: [ProviderFailure]?
    /// False when the request used an lh_test_ key (sandbox quotes). Nil means live.
    public let livemode: Bool?
}

// MARK: - Transactions

/// An ERC-20 `approve(spender, amount)` that must be mined before the main transaction.
public struct Approval: Codable, Sendable, Equatable {
    public let token: String
    public let spender: String
    public let amount: String
}

/// A plain EVM call: target, hex calldata and native value in wei.
public struct EvmCall: Codable, Sendable, Equatable {
    public let to: String
    public let data: String
    public let value: String
}

/// An unsigned EVM transaction.
public struct EvmTx: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let to: String
    /// Hex calldata.
    public let data: String
    /// Native value in wei (decimal string).
    public let value: String
    /// Send this ERC-20 approval first when set.
    public let approval: Approval?
    /// Further calls to send after the main transaction, in order (e.g. LayerHop's fee transfer on a
    /// same-token checkout payment). Report the main transaction's hash.
    public let extraTxs: [EvmCall]
    /// True in test mode: a placeholder that moves no funds. Never broadcast it.
    public let sandbox: Bool

    enum CodingKeys: String, CodingKey { case chainId, to, data, value, approval, extraTxs, sandbox }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chainId = try c.decode(Int64.self, forKey: .chainId)
        to = try c.decode(String.self, forKey: .to)
        data = try c.decodeIfPresent(String.self, forKey: .data) ?? "0x"
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? "0"
        approval = try c.decodeIfPresent(Approval.self, forKey: .approval)
        extraTxs = try c.decodeIfPresent([EvmCall].self, forKey: .extraTxs) ?? []
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chainId, forKey: .chainId)
        try c.encode(to, forKey: .to)
        try c.encode(data, forKey: .data)
        try c.encode(value, forKey: .value)
        try c.encodeIfPresent(approval, forKey: .approval)
        if !extraTxs.isEmpty { try c.encode(extraTxs, forKey: .extraTxs) }
        if sandbox { try c.encode(true, forKey: .sandbox) }
    }
}

/// An unsigned Solana transaction.
public struct SvmTx: Codable, Sendable, Equatable {
    /// A base64 serialized VersionedTransaction.
    public let serializedTx: String
    /// Sign only, then send through `LayerHopClient.submit` instead of an RPC node.
    public let submitViaApi: Bool
    /// True in test mode: a placeholder that moves no funds. Never broadcast it.
    public let sandbox: Bool

    enum CodingKeys: String, CodingKey { case serializedTx, submitViaApi, sandbox }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serializedTx = try c.decode(String.self, forKey: .serializedTx)
        submitViaApi = try c.decodeIfPresent(Bool.self, forKey: .submitViaApi) ?? false
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(serializedTx, forKey: .serializedTx)
        if submitViaApi { try c.encode(true, forKey: .submitViaApi) }
        if sandbox { try c.encode(true, forKey: .sandbox) }
    }
}

/// The transaction for the user's wallet, discriminated by the JSON `vm` field ("evm" | "svm").
public enum BuiltTx: Codable, Sendable, Equatable {
    case evm(EvmTx)
    case svm(SvmTx)

    public var isEVM: Bool { if case .evm = self { return true } else { return false } }
    public var isSVM: Bool { if case .svm = self { return true } else { return false } }
    public var evm: EvmTx? { if case let .evm(tx) = self { return tx } else { return nil } }
    public var svm: SvmTx? { if case let .svm(tx) = self { return tx } else { return nil } }
    /// "evm" or "svm".
    public var vm: String { isEVM ? "evm" : "svm" }
    /// True in test mode: the transaction is a placeholder that moves no funds. Never broadcast it.
    public var sandbox: Bool {
        switch self {
        case let .evm(tx): return tx.sandbox
        case let .svm(tx): return tx.sandbox
        }
    }

    private enum VMKey: String, CodingKey { case vm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: VMKey.self)
        let vm = try c.decode(String.self, forKey: .vm)
        switch vm {
        case "evm": self = .evm(try EvmTx(from: decoder))
        case "svm": self = .svm(try SvmTx(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .vm, in: c, debugDescription: "unknown tx vm \"\(vm)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: VMKey.self)
        try c.encode(vm, forKey: .vm)
        switch self {
        case let .evm(tx): try tx.encode(to: encoder)
        case let .svm(tx): try tx.encode(to: encoder)
        }
    }
}

/// The body of `POST /v1/orders/{quoteId}/submitted`.
public struct ReportSubmittedResponse: Codable, Sendable, Equatable {
    public let quoteId: String
    public let status: String
}

/// Why a simulation failed.
public struct SimulationError: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let logs: [String]?
}

/// The body of `POST /v1/simulate`.
public struct SimulateResponse: Codable, Sendable, Equatable {
    public let quoteId: String?
    public let provider: ProviderID?
    public let ok: Bool
    public let vm: String
    /// "tx" (the swap itself) or "approval" (only the approval could be simulated).
    public let simulated: String?
    /// EVM gas estimate as a decimal string (the API may send a number or a string).
    public let gasEstimate: String?
    /// Solana compute units as a decimal string (the API may send a number or a string).
    public let computeUnits: String?
    public let needsApproval: Bool
    public let error: SimulationError?
    public let tx: BuiltTx?

    enum CodingKeys: String, CodingKey {
        case quoteId, provider, ok, vm, simulated, gasEstimate, computeUnits, needsApproval, error, tx
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quoteId = try c.decodeIfPresent(String.self, forKey: .quoteId)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        ok = try c.decode(Bool.self, forKey: .ok)
        vm = try c.decode(String.self, forKey: .vm)
        simulated = try c.decodeIfPresent(String.self, forKey: .simulated)
        gasEstimate = try c.decodeNumberString(forKey: .gasEstimate)
        computeUnits = try c.decodeNumberString(forKey: .computeUnits)
        needsApproval = try c.decodeIfPresent(Bool.self, forKey: .needsApproval) ?? false
        error = try c.decodeIfPresent(SimulationError.self, forKey: .error)
        tx = try c.decodeIfPresent(BuiltTx.self, forKey: .tx)
    }
}

extension KeyedDecodingContainer {
    /// Decodes an integer kept as a decimal string from a JSON string, number or null.
    func decodeNumberString(forKey key: Key) throws -> String? {
        if try !contains(key) || decodeNil(forKey: key) { return nil }
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int64.self, forKey: key) { return String(i) }
        if let u = try? decode(UInt64.self, forKey: key) { return String(u) }
        let d = try decode(Double.self, forKey: key)
        return formatNumber(d)
    }
}

/// Formats a Double without a trailing ".0" (like Go's strconv.FormatFloat(f, 'f', -1, 64)).
func formatNumber(_ d: Double) -> String {
    if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
    return String(d)
}

// MARK: - Orders

/// The body of `GET /v1/orders/{provider}/{id}`.
public struct OrderStatus: Codable, Sendable, Equatable {
    public let provider: ProviderID
    public let id: String
    public let state: OrderState
    public let srcTxHash: String?
    public let dstTxHash: String?
}

/// One order (a row of `GET /v1/orders`, a deposit, a limit-order fill, a stream frame). Every field
/// is optional because the listing is lenient.
public struct Order: Codable, Sendable, Equatable {
    public let quoteId: String?
    public let provider: ProviderID?
    public let status: String?
    public let statusDetail: String?
    public let channel: String?
    public let ourFeeBps: Int?
    public let partnerFeeBps: Int?
    public let srcChainId: Int64?
    public let srcToken: String?
    public let dstChainId: Int64?
    public let dstToken: String?
    public let amount: String?
    public let dstAmount: String?
    public let sender: String?
    public let recipient: String?
    public let srcTxHash: String?
    public let dstTxHash: String?
    /// False for test-mode orders. Nil means live.
    public let livemode: Bool?
    /// The checkout session this order pays, if any.
    public let checkoutSessionId: String?
    /// The deposit address this order came from, if any.
    public let depositAddressId: String?
    /// The checkout refund this order executes, if any.
    public let refundId: String?
    /// The limit order this order is a fill of, if any (quoteId starts with "lof_").
    public let limitOrderId: String?
    public let createdAt: String?
    public let updatedAt: String?
}

/// Filters for `GET /v1/orders`. Nil fields are omitted.
public struct ListOrdersParams: Sendable, Equatable {
    /// Matches the sender or the recipient.
    public var address: String?
    public var status: String?
    public var cursor: String?
    public var limit: Int?

    public init(address: String? = nil, status: String? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.address = address
        self.status = status
        self.cursor = cursor
        self.limit = limit
    }
}

/// The body of `GET /v1/orders`.
public struct ListOrdersResponse: Codable, Sendable, Equatable {
    public let orders: [Order]
    public let nextCursor: String?
}

// MARK: - Checkout sessions

/// The body of `POST /v1/checkout/sessions`. Nil optional fields are omitted.
public struct CreateCheckoutParams: Encodable, Sendable, Equatable {
    /// The amount due, an integer string in base units of the settlement token (49 USDC = "49000000").
    public var amount: String
    /// A chain id or slug: ethereum, arbitrum, base, optimism, bsc, polygon or solana.
    public var settleChain: String
    /// "USDC" or "USDT" (or its address) on `settleChain`.
    public var settleToken: String
    /// Your payout address on the settlement chain.
    public var recipient: String
    public var merchantName: String?
    /// Shown to the payer.
    public var description: String?
    /// Your own order id; never shown to the payer.
    public var reference: String?
    /// Up to 20 string values; never shown to the payer.
    public var metadata: [String: String]?
    public var successUrl: String?
    public var cancelUrl: String?
    /// 5-10080; the API default (60) applies when nil.
    public var expiresInMinutes: Int?

    public init(
        amount: String, settleChain: String, settleToken: String, recipient: String,
        merchantName: String? = nil, description: String? = nil, reference: String? = nil,
        metadata: [String: String]? = nil, successUrl: String? = nil, cancelUrl: String? = nil,
        expiresInMinutes: Int? = nil
    ) {
        self.amount = amount
        self.settleChain = settleChain
        self.settleToken = settleToken
        self.recipient = recipient
        self.merchantName = merchantName
        self.description = description
        self.reference = reference
        self.metadata = metadata
        self.successUrl = successUrl
        self.cancelUrl = cancelUrl
        self.expiresInMinutes = expiresInMinutes
    }
}

/// The token a checkout session, product, invoice or subscription is paid out in.
public struct CheckoutSettlement: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let token: String
    public let symbol: String
    public let decimals: Int
}

/// The current (or final) payment attempt of a session.
public struct CheckoutPayment: Codable, Sendable, Equatable {
    public let quoteId: String
    public let payer: String?
    public let srcChainId: Int64?
    public let srcToken: String?
    /// What the payer sent, in base units of `srcToken`.
    public let srcAmount: String?
    public let srcTxHash: String?
    /// The verified delivery transaction once paid.
    public let dstTxHash: String?
    public let paidAt: String?
}

/// A payment request ("checkout.session").
public struct CheckoutSession: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let livemode: Bool
    public let status: CheckoutStatus
    public let statusDetail: String?
    public let amount: String
    public let settlement: CheckoutSettlement
    public let recipient: String
    public let merchantName: String?
    public let description: String?
    /// The hosted checkout page: send the payer here.
    public let url: String
    /// The product the session was started from, if any.
    public let productId: String?
    /// The invoice the session pays, if any.
    public let invoiceId: String?
    /// The total of completed refunds, in settlement-token base units.
    public let refundedAmount: String?
    public let successUrl: String?
    public let cancelUrl: String?
    public let expiresAt: String
    /// Nil until a payment is reported.
    public let payment: CheckoutPayment?
    /// Returned only with the owning account's API key.
    public let reference: String?
    /// Returned only with the owning account's API key.
    public let metadata: [String: String]?
    public let createdAt: String
    public let updatedAt: String
}

/// Filters for `GET /v1/checkout/sessions`. Nil fields are omitted.
public struct ListCheckoutSessionsParams: Sendable, Equatable {
    public var status: CheckoutStatus?
    public var cursor: String?
    /// 1-100 (API default 50).
    public var limit: Int?

    public init(status: CheckoutStatus? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.status = status
        self.cursor = cursor
        self.limit = limit
    }
}

/// The body of `GET /v1/checkout/sessions`.
public struct ListCheckoutSessionsResponse: Codable, Sendable, Equatable {
    public let sessions: [CheckoutSession]
    public let nextCursor: String?
}

/// The body of `POST /v1/checkout/sessions/{id}/quote`.
public struct CheckoutQuoteParams: Encodable, Sendable, Equatable {
    /// The chain the payer pays from (id or slug).
    public var srcChain: String
    /// A token address / mint, curated symbol or native symbol.
    public var srcToken: String
    /// The payer's address on `srcChain`.
    public var sender: String
    /// Omitted when nil (API default 50).
    public var slippageBps: Int?

    public init(srcChain: String, srcToken: String, sender: String, slippageBps: Int? = nil) {
        self.srcChain = srcChain
        self.srcToken = srcToken
        self.sender = sender
        self.slippageBps = slippageBps
    }
}

/// A quote for paying a session. `dstAmountMin` is always >= the amount due.
public struct CheckoutQuote: Codable, Sendable, Equatable {
    public let quoteId: String
    public let provider: ProviderID
    /// What the payer sends, in base units of the chosen token.
    public let srcAmount: String
    public let dstAmount: String
    public let dstAmountMin: String
    public let estimatedSeconds: Int
    public let fees: FeeBreakdown
    /// Unix seconds.
    public let expiresAt: Int64
    public let gasOnArrival: GasOnArrival?
}

/// The body of `POST /v1/checkout/sessions/{id}/quote`. `best == quotes[0]`.
public struct CheckoutQuoteResponse: Codable, Sendable, Equatable {
    public let sessionId: String
    public let livemode: Bool
    public let amountDue: String
    public let best: CheckoutQuote
    public let quotes: [CheckoutQuote]
    public let errors: [ProviderFailure]?
}

// MARK: - Products

/// The body of `POST /v1/checkout/products`. Nil optional fields are omitted.
public struct CreateCheckoutProductParams: Encodable, Sendable, Equatable {
    public var name: String
    public var description: String?
    public var merchantName: String?
    /// The price, an integer string in base units of the settlement token.
    public var amount: String
    /// A chain id or slug: ethereum, arbitrum, base, optimism, bsc, polygon or solana.
    public var settleChain: String
    /// "USDC" or "USDT" (or its address) on `settleChain`.
    public var settleToken: String
    /// Your payout address on the settlement chain.
    public var recipient: String
    public var successUrl: String?
    public var cancelUrl: String?
    /// The lifetime of each session started from the product (5-10080); API default 60.
    public var expiresInMinutes: Int?
    /// https origins allowed to start sessions from a browser; nil or empty = any.
    public var allowedOrigins: [String]?
    /// Defaults to true when nil.
    public var active: Bool?

    public init(
        name: String, amount: String, settleChain: String, settleToken: String, recipient: String,
        description: String? = nil, merchantName: String? = nil, successUrl: String? = nil,
        cancelUrl: String? = nil, expiresInMinutes: Int? = nil, allowedOrigins: [String]? = nil,
        active: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.merchantName = merchantName
        self.amount = amount
        self.settleChain = settleChain
        self.settleToken = settleToken
        self.recipient = recipient
        self.successUrl = successUrl
        self.cancelUrl = cancelUrl
        self.expiresInMinutes = expiresInMinutes
        self.allowedOrigins = allowedOrigins
        self.active = active
    }
}

/// The body of `PATCH /v1/checkout/products/{id}`: only non-nil fields are sent. An empty string
/// clears a nullable field (`description`, `merchantName`, `successUrl`, `cancelUrl`) by sending
/// null; an empty `allowedOrigins` sends `[]` (any origin).
public struct UpdateCheckoutProductParams: Encodable, Sendable, Equatable {
    public var name: String?
    public var description: String?
    public var merchantName: String?
    public var amount: String?
    public var settleChain: String?
    public var settleToken: String?
    public var recipient: String?
    public var successUrl: String?
    public var cancelUrl: String?
    public var expiresInMinutes: Int?
    public var allowedOrigins: [String]?
    public var active: Bool?

    public init(
        name: String? = nil, description: String? = nil, merchantName: String? = nil,
        amount: String? = nil, settleChain: String? = nil, settleToken: String? = nil,
        recipient: String? = nil, successUrl: String? = nil, cancelUrl: String? = nil,
        expiresInMinutes: Int? = nil, allowedOrigins: [String]? = nil, active: Bool? = nil
    ) {
        self.name = name
        self.description = description
        self.merchantName = merchantName
        self.amount = amount
        self.settleChain = settleChain
        self.settleToken = settleToken
        self.recipient = recipient
        self.successUrl = successUrl
        self.cancelUrl = cancelUrl
        self.expiresInMinutes = expiresInMinutes
        self.allowedOrigins = allowedOrigins
        self.active = active
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, merchantName, amount, settleChain, settleToken, recipient
        case successUrl, cancelUrl, expiresInMinutes, allowedOrigins, active
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeNullable(description, forKey: .description)
        try c.encodeNullable(merchantName, forKey: .merchantName)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(settleChain, forKey: .settleChain)
        try c.encodeIfPresent(settleToken, forKey: .settleToken)
        try c.encodeIfPresent(recipient, forKey: .recipient)
        try c.encodeNullable(successUrl, forKey: .successUrl)
        try c.encodeNullable(cancelUrl, forKey: .cancelUrl)
        try c.encodeIfPresent(expiresInMinutes, forKey: .expiresInMinutes)
        try c.encodeIfPresent(allowedOrigins, forKey: .allowedOrigins)
        try c.encodeIfPresent(active, forKey: .active)
    }
}

extension KeyedEncodingContainer {
    /// nil: omitted; "": null (clears the field); otherwise the value.
    mutating func encodeNullable(_ value: String?, forKey key: Key) throws {
        guard let value else { return }
        if value.isEmpty { try encodeNil(forKey: key) } else { try encode(value, forKey: key) }
    }
}

/// A fixed price for payment buttons, layerhop.com/buy/{id} links and store plugins
/// ("checkout.product"). `recipient`, `successUrl`, `cancelUrl`, `expiresInMinutes`,
/// `allowedOrigins`, `createdAt` and `updatedAt` are returned only with the owner's key.
public struct CheckoutProduct: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let livemode: Bool
    public let active: Bool
    public let name: String
    public let description: String?
    public let merchantName: String?
    public let amount: String
    public let settlement: CheckoutSettlement
    /// https://layerhop.com/buy/{id}: starts a session and opens the payment page.
    public let url: String
    public let recipient: String?
    public let successUrl: String?
    public let cancelUrl: String?
    public let expiresInMinutes: Int?
    public let allowedOrigins: [String]?
    public let createdAt: String?
    public let updatedAt: String?
}

/// Filters for `GET /v1/checkout/products`. Nil fields are omitted.
public struct ListCheckoutProductsParams: Sendable, Equatable {
    public var active: Bool?
    public var cursor: String?
    /// 1-100 (API default 50).
    public var limit: Int?

    public init(active: Bool? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.active = active
        self.cursor = cursor
        self.limit = limit
    }
}

/// The body of `GET /v1/checkout/products`.
public struct ListCheckoutProductsResponse: Codable, Sendable, Equatable {
    public let products: [CheckoutProduct]
    public let nextCursor: String?
}

/// The body of `POST /v1/checkout/products/{id}/sessions`: the only things a caller may add to the
/// product's terms.
public struct StartProductCheckoutParams: Encodable, Sendable, Equatable {
    /// Your order id, returned in the session and its webhooks.
    public var reference: String?
    /// Up to 10 string values.
    public var metadata: [String: String]?

    public init(reference: String? = nil, metadata: [String: String]? = nil) {
        self.reference = reference
        self.metadata = metadata
    }
}

// MARK: - Invoices

/// One line of an invoice. `unitAmount` is in base units of the settlement token; the line total is
/// `unitAmount × quantity`.
public struct InvoiceLineItem: Codable, Sendable, Equatable {
    public var description: String
    public var quantity: Int
    public var unitAmount: String

    public init(description: String, quantity: Int, unitAmount: String) {
        self.description = description
        self.quantity = quantity
        self.unitAmount = unitAmount
    }
}

/// The body of `POST /v1/invoices`. Nil optional fields are omitted.
public struct CreateInvoiceParams: Encodable, Sendable, Equatable {
    /// Receives the invoice email (and the receipt once paid).
    public var customerEmail: String?
    public var customerName: String?
    public var merchantName: String?
    public var memo: String?
    /// 1 to 50 lines; the invoice amount is their sum.
    public var lineItems: [InvoiceLineItem]
    /// A chain slug or id ("base", "8453").
    public var settleChain: String
    /// A stablecoin symbol or address on `settleChain` ("USDC").
    public var settleToken: String
    public var recipient: String
    /// An ISO 8601 date ("2026-11-01") or date-time.
    public var dueAt: String?
    /// Finalizes the invoice and emails it right away (status "open").
    public var send: Bool?

    public init(
        lineItems: [InvoiceLineItem], settleChain: String, settleToken: String, recipient: String,
        customerEmail: String? = nil, customerName: String? = nil, merchantName: String? = nil,
        memo: String? = nil, dueAt: String? = nil, send: Bool? = nil
    ) {
        self.customerEmail = customerEmail
        self.customerName = customerName
        self.merchantName = merchantName
        self.memo = memo
        self.lineItems = lineItems
        self.settleChain = settleChain
        self.settleToken = settleToken
        self.recipient = recipient
        self.dueAt = dueAt
        self.send = send
    }
}

/// The body of `PATCH /v1/invoices/{id}` (drafts only): only non-nil fields are sent. An empty string
/// clears a nullable field (`customerEmail`, `customerName`, `merchantName`, `memo`, `dueAt`) by
/// sending null; a non-nil `lineItems` replaces every line.
public struct UpdateInvoiceParams: Encodable, Sendable, Equatable {
    public var customerEmail: String?
    public var customerName: String?
    public var merchantName: String?
    public var memo: String?
    public var lineItems: [InvoiceLineItem]?
    public var settleChain: String?
    public var settleToken: String?
    public var recipient: String?
    public var dueAt: String?

    public init(
        customerEmail: String? = nil, customerName: String? = nil, merchantName: String? = nil,
        memo: String? = nil, lineItems: [InvoiceLineItem]? = nil, settleChain: String? = nil,
        settleToken: String? = nil, recipient: String? = nil, dueAt: String? = nil
    ) {
        self.customerEmail = customerEmail
        self.customerName = customerName
        self.merchantName = merchantName
        self.memo = memo
        self.lineItems = lineItems
        self.settleChain = settleChain
        self.settleToken = settleToken
        self.recipient = recipient
        self.dueAt = dueAt
    }

    private enum CodingKeys: String, CodingKey {
        case customerEmail, customerName, merchantName, memo, lineItems, settleChain, settleToken
        case recipient, dueAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNullable(customerEmail, forKey: .customerEmail)
        try c.encodeNullable(customerName, forKey: .customerName)
        try c.encodeNullable(merchantName, forKey: .merchantName)
        try c.encodeNullable(memo, forKey: .memo)
        try c.encodeIfPresent(lineItems, forKey: .lineItems)
        try c.encodeIfPresent(settleChain, forKey: .settleChain)
        try c.encodeIfPresent(settleToken, forKey: .settleToken)
        try c.encodeIfPresent(recipient, forKey: .recipient)
        try c.encodeNullable(dueAt, forKey: .dueAt)
    }
}

/// A bill sent to a customer by email and paid through checkout ("invoice"). `customerEmail`,
/// `recipient`, `sessionId`, `sentAt`, `receiptSentAt`, `voidedAt` and `updatedAt` are returned only
/// to the owner (nil from `getPublicInvoice`).
public struct Invoice: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let livemode: Bool
    public let number: String
    public let status: InvoiceStatus
    public let merchantName: String?
    public let customerName: String?
    public let memo: String?
    public let lineItems: [InvoiceLineItem]
    public let amount: String
    public let settlement: CheckoutSettlement
    public let dueAt: String?
    public let paidAt: String?
    /// The hosted invoice page (layerhop.com/invoice/{id}).
    public let url: String
    /// The PDF receipt, set once the invoice is paid.
    public let receiptUrl: String?
    public let createdAt: String
    public let customerEmail: String?
    public let recipient: String?
    /// The checkout session that pays (or last tried to pay) the invoice.
    public let sessionId: String?
    /// The subscription this invoice bills a period of, if any.
    public let subscriptionId: String?
    public let sentAt: String?
    public let receiptSentAt: String?
    public let voidedAt: String?
    public let updatedAt: String?
}

/// Filters for `GET /v1/invoices`. Nil fields are omitted.
public struct ListInvoicesParams: Sendable, Equatable {
    public var status: InvoiceStatus?
    public var cursor: String?
    /// 1-100 (server default 20).
    public var limit: Int?

    public init(status: InvoiceStatus? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.status = status
        self.cursor = cursor
        self.limit = limit
    }
}

/// One page of invoices, newest first.
public struct ListInvoicesResponse: Codable, Sendable, Equatable {
    public let invoices: [Invoice]
    public let nextCursor: String?
}

/// The checkout session that pays an invoice: send the payer to `url`.
public struct PayInvoiceResponse: Codable, Sendable, Equatable {
    public let sessionId: String
    public let url: String
}

// MARK: - Deposit addresses

/// The body of `POST /v1/deposit-addresses`. Nil optional fields are omitted.
public struct CreateDepositAddressParams: Encodable, Sendable, Equatable {
    /// The chain id or slug the user sends on ("base", "8453").
    public var srcChain: String
    /// The token the user sends (symbol or address on `srcChain`).
    public var srcToken: String
    public var dstChain: String
    public var dstToken: String
    /// Receives `dstToken` on `dstChain`.
    public var recipient: String
    /// The user's address on `srcChain` for refunds. Never a CEX deposit address.
    public var refundTo: String
    /// Defaults to true when nil (any amount, forever, for this route). False makes a one-time
    /// address for exactly `amount`.
    public var reusable: Bool?
    /// Base units of `srcToken`: required when `reusable` is false; otherwise it sizes the estimate.
    public var amount: String?
    /// Your own tag (1-64 chars), filterable in `listDepositAddresses`.
    public var label: String?
    /// Up to 20 string values.
    public var metadata: [String: String]?
    /// Defaults to the client's integrator when nil.
    public var integrator: String?
    /// Defaults to the client's integratorFeeBps when nil.
    public var integratorFeeBps: Int?

    public init(
        srcChain: String, srcToken: String, dstChain: String, dstToken: String,
        recipient: String, refundTo: String, reusable: Bool? = nil, amount: String? = nil,
        label: String? = nil, metadata: [String: String]? = nil, integrator: String? = nil,
        integratorFeeBps: Int? = nil
    ) {
        self.srcChain = srcChain
        self.srcToken = srcToken
        self.dstChain = dstChain
        self.dstToken = dstToken
        self.recipient = recipient
        self.refundTo = refundTo
        self.reusable = reusable
        self.amount = amount
        self.label = label
        self.metadata = metadata
        self.integrator = integrator
        self.integratorFeeBps = integratorFeeBps
    }
}

/// The fees applied to every deposit. `integrator` is nil without a partner.
public struct DepositAddressFees: Codable, Sendable, Equatable {
    public let ourFeeBps: Int
    public let integratorFeeBps: Int
    public let integrator: String?
}

/// Prices one deposit of `amount` (returned by `createDepositAddress` only).
public struct DepositAddressEstimate: Codable, Sendable, Equatable {
    public let amount: String
    public let dstAmount: String
    public let dstAmountMin: String
    public let estimatedSeconds: Int
}

/// An address the end user sends `token` to on `chainId`; the provider delivers `dstToken` to
/// `recipient` on `dstChainId` ("deposit_address"). LayerHop never holds the funds.
public struct DepositAddress: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let livemode: Bool
    public let status: DepositAddressStatus
    /// "relay" (live) or "sandbox" (test mode).
    public let provider: ProviderID
    /// What your user sends `token` to on `chainId`.
    public let address: String
    public let chainId: Int64
    public let token: String
    public let dstChainId: Int64
    public let dstToken: String
    public let recipient: String
    public let refundTo: String
    public let reusable: Bool
    /// Set on one-time addresses only (base units of `token`).
    public let amount: String?
    public let fees: DepositAddressFees
    public let label: String?
    public let metadata: [String: String]?
    public let depositCount: Int
    public let lastDepositAt: String?
    public let createdAt: String
    /// Set by `createDepositAddress` only.
    public let estimate: DepositAddressEstimate?
    /// The 20 most recent deposit orders, newest first (`getDepositAddress` only).
    public let deposits: [Order]?
}

/// Filters for `GET /v1/deposit-addresses`. Nil fields are omitted.
public struct ListDepositAddressesParams: Sendable, Equatable {
    public var status: DepositAddressStatus?
    public var label: String?
    public var cursor: String?
    /// 1-100.
    public var limit: Int?

    public init(status: DepositAddressStatus? = nil, label: String? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.status = status
        self.label = label
        self.cursor = cursor
        self.limit = limit
    }
}

/// One page of deposit addresses, newest first.
public struct ListDepositAddressesResponse: Codable, Sendable, Equatable {
    public let depositAddresses: [DepositAddress]
    public let nextCursor: String?
}

/// The body of `POST /v1/deposit-addresses/{id}/simulate`: the test deposit order.
public struct SimulateDepositResponse: Codable, Sendable, Equatable {
    public let order: Order
}

// MARK: - Subscriptions

/// The body of `POST /v1/subscriptions`. Nil optional fields are omitted. Set `productId` to bill a
/// product's price, settlement token and payout address, or `amount`, `settleChain`, `settleToken`
/// and `recipient` (plus `description`) instead.
public struct CreateSubscriptionParams: Encodable, Sendable, Equatable {
    /// Receives each period's invoice and the reminders.
    public var customerEmail: String
    public var interval: SubscriptionInterval
    /// Bills every `intervalCount` intervals (1-365; API default 1). 3 + month is quarterly.
    public var intervalCount: Int?
    public var productId: String?
    /// The price per period in base units of the settlement token.
    public var amount: String?
    public var settleChain: String?
    public var settleToken: String?
    public var recipient: String?
    /// The invoice line item ("Pro plan"); required without `productId`.
    public var description: String?
    public var customerName: String?
    public var merchantName: String?
    /// A note on every invoice.
    public var memo: String?
    /// Days after an invoice is issued that it is due (0-60; API default 3).
    public var daysUntilDue: Int?
    /// ISO 8601 date-time of the first period and invoice (default now, at most 366 days ahead).
    public var startAt: String?
    /// Up to 20 string values, returned in the API and webhooks.
    public var metadata: [String: String]?

    public init(
        customerEmail: String, interval: SubscriptionInterval, intervalCount: Int? = nil,
        productId: String? = nil, amount: String? = nil, settleChain: String? = nil,
        settleToken: String? = nil, recipient: String? = nil, description: String? = nil,
        customerName: String? = nil, merchantName: String? = nil, memo: String? = nil,
        daysUntilDue: Int? = nil, startAt: String? = nil, metadata: [String: String]? = nil
    ) {
        self.customerEmail = customerEmail
        self.interval = interval
        self.intervalCount = intervalCount
        self.productId = productId
        self.amount = amount
        self.settleChain = settleChain
        self.settleToken = settleToken
        self.recipient = recipient
        self.description = description
        self.customerName = customerName
        self.merchantName = merchantName
        self.memo = memo
        self.daysUntilDue = daysUntilDue
        self.startAt = startAt
        self.metadata = metadata
    }
}

/// The body of `PATCH /v1/subscriptions/{id}`: only non-nil fields are sent, and changes apply from
/// the next invoice. An empty string clears a nullable field (`customerName`, `merchantName`,
/// `memo`) by sending null; an empty `metadata` sends null. `cancelAtPeriodEnd` true schedules a
/// cancel at the end of the current period; false undoes it.
public struct UpdateSubscriptionParams: Encodable, Sendable, Equatable {
    public var customerEmail: String?
    public var customerName: String?
    public var merchantName: String?
    public var description: String?
    public var memo: String?
    public var amount: String?
    public var daysUntilDue: Int?
    public var metadata: [String: String]?
    public var cancelAtPeriodEnd: Bool?

    public init(
        customerEmail: String? = nil, customerName: String? = nil, merchantName: String? = nil,
        description: String? = nil, memo: String? = nil, amount: String? = nil,
        daysUntilDue: Int? = nil, metadata: [String: String]? = nil, cancelAtPeriodEnd: Bool? = nil
    ) {
        self.customerEmail = customerEmail
        self.customerName = customerName
        self.merchantName = merchantName
        self.description = description
        self.memo = memo
        self.amount = amount
        self.daysUntilDue = daysUntilDue
        self.metadata = metadata
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
    }

    private enum CodingKeys: String, CodingKey {
        case customerEmail, customerName, merchantName, description, memo, amount, daysUntilDue
        case metadata, cancelAtPeriodEnd
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(customerEmail, forKey: .customerEmail)
        try c.encodeNullable(customerName, forKey: .customerName)
        try c.encodeNullable(merchantName, forKey: .merchantName)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeNullable(memo, forKey: .memo)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(daysUntilDue, forKey: .daysUntilDue)
        if let metadata {
            if metadata.isEmpty { try c.encodeNil(forKey: .metadata) } else { try c.encode(metadata, forKey: .metadata) }
        }
        try c.encodeIfPresent(cancelAtPeriodEnd, forKey: .cancelAtPeriodEnd)
    }
}

/// Bills a customer every period: LayerHop issues and emails an invoice per period, paid through
/// checkout with any token ("subscription").
public struct Subscription: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let livemode: Bool
    public let status: SubscriptionStatus
    public let customerEmail: String
    public let customerName: String?
    public let merchantName: String?
    public let description: String
    public let memo: String?
    public let productId: String?
    /// The price per period in base units of the settlement token.
    public let amount: String
    public let settlement: CheckoutSettlement
    public let recipient: String
    public let interval: SubscriptionInterval
    public let intervalCount: Int
    public let daysUntilDue: Int
    /// The start of the period last invoiced (nil before the first invoice).
    public let currentPeriodStart: String?
    public let currentPeriodEnd: String?
    /// When the next invoice is issued (nil when paused or canceled).
    public let nextInvoiceAt: String?
    /// The scheduled cancel (the end of the current period).
    public let cancelAt: String?
    public let cancelAtPeriodEnd: Bool
    public let canceledAt: String?
    /// "requested" (you canceled) or "unpaid" (7 days past due).
    public let cancellationReason: String?
    public let pausedAt: String?
    /// The invoice of the current period.
    public let latestInvoiceId: String?
    public let metadata: [String: String]?
    public let createdAt: String
    public let updatedAt: String
}

/// Filters for `GET /v1/subscriptions`. Nil fields are omitted.
public struct ListSubscriptionsParams: Sendable, Equatable {
    public var status: SubscriptionStatus?
    public var customerEmail: String?
    public var cursor: String?
    /// 1-100.
    public var limit: Int?

    public init(status: SubscriptionStatus? = nil, customerEmail: String? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.status = status
        self.customerEmail = customerEmail
        self.cursor = cursor
        self.limit = limit
    }
}

/// One page of subscriptions, newest first.
public struct ListSubscriptionsResponse: Codable, Sendable, Equatable {
    public let subscriptions: [Subscription]
    public let nextCursor: String?
}

// MARK: - Limit orders

/// The body of `POST /v1/limit-orders`. Nil optional fields are omitted.
public struct CreateLimitOrderParams: Encodable, Sendable, Equatable {
    /// Only "solana" (or "7565164") for now; the API default applies when nil.
    public var chain: String?
    /// The maker wallet (base58): it signs the order and receives the output.
    public var wallet: String
    /// The token to sell: mint, curated symbol ("USDC") or "SOL".
    public var srcToken: String
    /// The token to buy. LayerHop's fee applies when it is SOL, USDC or USDT.
    public var dstToken: String
    /// Base units of `srcToken` to sell (worth at least $5).
    public var amount: String
    /// The minimum base units of `dstToken` for the whole `amount`: the limit price is
    /// `dstAmount / amount`.
    public var dstAmount: String
    /// Unix seconds, at least 60 s ahead. Nil means good-till-cancelled.
    public var expiresAt: Int64?
    /// Defaults to the client's channel when nil.
    public var channel: String?
    /// Up to 20 string values.
    public var metadata: [String: String]?
    /// Defaults to the client's integrator when nil.
    public var integrator: String?
    /// Defaults to the client's integratorFeeBps when nil.
    public var integratorFeeBps: Int?

    public init(
        wallet: String, srcToken: String, dstToken: String, amount: String, dstAmount: String,
        chain: String? = nil, expiresAt: Int64? = nil, channel: String? = nil,
        metadata: [String: String]? = nil, integrator: String? = nil, integratorFeeBps: Int? = nil
    ) {
        self.chain = chain
        self.wallet = wallet
        self.srcToken = srcToken
        self.dstToken = dstToken
        self.amount = amount
        self.dstAmount = dstAmount
        self.expiresAt = expiresAt
        self.channel = channel
        self.metadata = metadata
        self.integrator = integrator
        self.integratorFeeBps = integratorFeeBps
    }
}

/// The fees written into the on-chain order (`ourFeeBps` is 0 when `dstToken` carries no fee).
public struct LimitOrderFees: Codable, Sendable, Equatable {
    public let ourFeeBps: Int
    public let integratorFeeBps: Int
    public let integrator: String?
}

/// A Solana limit order (Jupiter Trigger) ("limit_order"). The order lives on chain; each fill is
/// recorded as an `Order` with `limitOrderId` set.
public struct LimitOrder: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let livemode: Bool
    public let status: LimitOrderStatus
    public let statusDetail: String?
    /// "jupiter" (live) or "sandbox" (test mode).
    public let provider: ProviderID
    /// Always `LayerHop.solanaChainID` for now.
    public let chainId: Int64
    public let wallet: String
    public let srcToken: String
    public let dstToken: String
    /// The input in base units.
    public let amount: String
    /// The minimum output for the whole order.
    public let dstAmount: String
    public let expiresAt: String?
    public let fees: LimitOrderFees
    /// The provider's order id (Jupiter: the order account).
    public let providerOrderId: String?
    public let filledAmount: String
    public let filledDstAmount: String
    public let fillCount: Int
    public let openTxHash: String?
    /// Set once a cancel tx was submitted; the status turns cancelled when confirmed.
    public let cancelTxHash: String?
    public let channel: String?
    public let metadata: [String: String]?
    public let createdAt: String
    public let updatedAt: String
    /// The unsigned transaction for `wallet` to sign (sign only, then `submitLimitOrder`). Set by
    /// `createLimitOrder` only.
    public let tx: BuiltTx?
    /// The order's fills, newest first (`getLimitOrder` only).
    public let fills: [Order]?
}

/// Filters for `GET /v1/limit-orders`. Nil fields are omitted.
public struct ListLimitOrdersParams: Sendable, Equatable {
    /// Lists that wallet's orders; without it, the API key's account.
    public var wallet: String?
    public var status: LimitOrderStatus?
    public var cursor: String?
    /// 1-100.
    public var limit: Int?

    public init(wallet: String? = nil, status: LimitOrderStatus? = nil, cursor: String? = nil, limit: Int? = nil) {
        self.wallet = wallet
        self.status = status
        self.cursor = cursor
        self.limit = limit
    }
}

/// One page of limit orders, newest first.
public struct ListLimitOrdersResponse: Codable, Sendable, Equatable {
    public let limitOrders: [LimitOrder]
    public let nextCursor: String?
}

/// The body of `POST /v1/limit-orders/{id}/submit`.
public struct SubmitLimitOrderResponse: Codable, Sendable, Equatable {
    public let limitOrder: LimitOrder
    /// The landed transaction's signature.
    public let txHash: String
}

/// The body of `POST /v1/limit-orders/{id}/cancel`. `tx` is the unsigned cancel transaction to sign
/// and `submitLimitOrder`, or nil when a never-submitted (built) order was cancelled at once.
public struct CancelLimitOrderResponse: Codable, Sendable, Equatable {
    public let limitOrder: LimitOrder
    public let tx: BuiltTx?
}

// MARK: - Refunds

/// The body of `POST /v1/checkout/sessions/{id}/refunds`. Nil fields are omitted.
public struct CreateRefundParams: Encodable, Sendable, Equatable {
    /// Settlement-token base units; default: everything not yet refunded.
    public var amount: String?
    public var reason: String?
    /// The wallet that signs the refund (default: the session's payout address).
    public var from: String?
    /// `.original` (default) or `.settlement`.
    public var to: RefundDestinationKind?

    public init(amount: String? = nil, reason: String? = nil, from: String? = nil, to: RefundDestinationKind? = nil) {
        self.amount = amount
        self.reason = reason
        self.from = from
        self.to = to
    }
}

/// Where a refund is delivered.
public struct RefundDestination: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let token: String
    public let address: String
}

/// Returns (part of) a paid checkout session to its payer ("refund").
public struct Refund: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let sessionId: String?
    public let livemode: Bool
    public let status: RefundStatus
    public let statusDetail: String?
    public let amount: String
    public let reason: String?
    public let quoteId: String?
    public let to: RefundDestination
    public let txHash: String?
    public let createdAt: String
    public let updatedAt: String?
}

/// The route that executes a refund. Build it with `buildTx(quoteId:)`, sign it from `from`, then
/// `reportSubmitted(quoteId:txHash:)`.
public struct RefundQuote: Codable, Sendable, Equatable {
    public let quoteId: String
    public let provider: ProviderID
    public let srcAmount: String
    public let dstAmount: String
    public let dstAmountMin: String
    public let estimatedSeconds: Int
    public let expiresAt: Int64
    /// The wallet that must sign the refund transaction.
    public let from: String
}

/// The body of `POST /v1/checkout/sessions/{id}/refunds`.
public struct CreateRefundResponse: Codable, Sendable, Equatable {
    public let refund: Refund
    public let quote: RefundQuote
    /// The remaining steps (build, sign, report).
    public let next: String?
}

/// Every refund of a session, newest first.
public struct ListRefundsResponse: Codable, Sendable, Equatable {
    public let refunds: [Refund]
}

// MARK: - Service status

/// One day of a component's uptime history. `uptime` is a percentage, nil without data.
public struct StatusDay: Codable, Sendable, Equatable {
    public let date: String
    public let uptime: Double?
}

/// One monitored component. `status` is "operational", "degraded" or "down".
public struct StatusComponent: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let group: String?
    public let status: String
    public let latencyMs: Int?
    public let uptime90d: Double?
    /// The last 90 days, oldest first.
    public let days: [StatusDay]?
}

/// An incident from the last 14 days. `resolvedAt` is nil while it is ongoing.
public struct StatusIncident: Codable, Sendable, Equatable {
    public let id: String
    public let componentId: String?
    public let component: String?
    public let title: String
    public let startedAt: String
    public let resolvedAt: String?
}

/// The body of `GET /v1/status` (status.layerhop.com). `status` is "operational", "degraded" or
/// "outage".
public struct StatusResponse: Codable, Sendable, Equatable {
    public let status: String
    public let updatedAt: String
    public let components: [StatusComponent]
    public let incidents: [StatusIncident]
    public let url: String?
}

// MARK: - Webhooks

/// The JSON body LayerHop POSTs to your webhook endpoints.
public struct WebhookEvent: Codable, Sendable, Equatable {
    public let id: String
    public let type: WebhookEventType
    public let livemode: Bool
    /// True for samples from the dashboard or `triggerWebhookEvent`.
    public let sample: Bool?
    public let createdAt: String
    public let data: WebhookEventData
    /// The exact JSON payload when known (set by `Webhook.constructEvent` and the event stream), e.g.
    /// to forward it unchanged. Not encoded.
    public var raw: Data? = nil

    enum CodingKeys: String, CodingKey { case id, type, livemode, sample, createdAt, data }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decode(WebhookEventType.self, forKey: .type)
        livemode = try c.decodeIfPresent(Bool.self, forKey: .livemode) ?? false
        sample = try c.decodeIfPresent(Bool.self, forKey: .sample)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        data = try c.decode(WebhookEventData.self, forKey: .data)
    }
}

/// The objects an event is about: `order` for order.* events, `session` for checkout.session.* events
/// (plus `refund` for checkout.session.refunded), `invoice` for invoice.* events (plus the paying
/// `session` for invoice.paid), `subscription` for subscription.* events (plus `invoice` for
/// subscription.renewed and subscription.past_due), `limitOrder` for limit_order.* events (plus the
/// fill's order in `fill` for limit_order.filled).
public struct WebhookEventData: Codable, Sendable, Equatable {
    public let order: Order?
    public let session: CheckoutSession?
    public let refund: Refund?
    public let invoice: Invoice?
    public let subscription: Subscription?
    public let limitOrder: LimitOrder?
    public let fill: Order?
}

/// The body of `POST /v1/webhooks/trigger`.
public struct TriggerWebhookResponse: Codable, Sendable, Equatable {
    public let eventId: String
    /// The number of test endpoints the event was queued for.
    public let deliveries: Int
    public let payload: WebhookEvent
}
