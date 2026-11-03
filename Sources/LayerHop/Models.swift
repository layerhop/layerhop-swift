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
    /// "evm", "svm" or "tvm" (Tron).
    public let vm: String
    public let nativeSymbol: String?
    public let nativeDecimals: Int?
    public let logoURI: String?
    public let explorerTx: String?
    public let explorerAddress: String?
    /// Providers that can route from or to this chain.
    public let providers: [ProviderID]?
    /// Shown first in chain pickers.
    public let popular: Bool?
    /// True for chains you can deliver to but not send from (e.g. Hyperliquid, Blast). Hide them from
    /// source pickers.
    public let destinationOnly: Bool?
    /// Set when every provider serves one fixed route into this chain; quotes from any other source
    /// fail with `UNSUPPORTED_CHAIN`.
    public let onlyRoute: OnlyRoute?
    /// LayerHop's periodic probe of routes into and out of this chain.
    public let routeHealth: ChainRouteHealth?
}

/// The one route into a chain (`Chain.onlyRoute`).
public struct OnlyRoute: Codable, Sendable, Equatable {
    public let srcChainId: Int64
    /// Source token address (EVM native = 0x000…000).
    public let srcToken: String
    /// Destination token address on this chain.
    public let dstToken: String
}

/// The result of LayerHop's read-only probe quotes for a chain. `in` / `out` are "ok", "failing" or
/// "unknown"; `status` is "ok", "deposit_only", "withdraw_only", "unavailable" or "unknown".
public struct ChainRouteHealth: Codable, Sendable, Equatable {
    public let `in`: String
    public let out: String
    public let status: String
    public let checkedAt: String?
}

/// A token (`GET /v1/tokens`, `lookupToken`). Fields beyond `chainId`, `address`, `symbol` and
/// `decimals` are optional so older responses still decode.
public struct Token: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let address: String
    public let symbol: String
    public let name: String?
    public let decimals: Int
    public let logoURI: String?
    /// USD price when known.
    public let priceUsd: Double?
    /// On a provider list or LayerHop's curated list; false for tokens read on chain only.
    public let verified: Bool?
    /// Stables, wrapped native and majors on that chain.
    public let popular: Bool?
}

/// Filters for `searchTokens`. Nil fields are omitted.
public struct TokensParams: Sendable, Equatable {
    /// A chain id or slug.
    public var chain: String
    /// Symbol, name or exact address / mint.
    public var q: String?
    /// 1-200 (API default 50).
    public var limit: Int?
    /// `nextCursor` of the previous page.
    public var cursor: String?

    public init(chain: String, q: String? = nil, limit: Int? = nil, cursor: String? = nil) {
        self.chain = chain
        self.q = q
        self.limit = limit
        self.cursor = cursor
    }
}

/// The body of `GET /v1/tokens`.
public struct TokensResponse: Codable, Sendable, Equatable {
    public let tokens: [Token]
    /// Pass as `cursor` for the next page; nil on the last page.
    public let nextCursor: String?
}

/// One reason in a token safety report. `code` is e.g. "honeypot", "sell_tax", "fake_symbol" (kept as
/// a string so new codes decode); `level` is "caution" or "danger".
public struct TokenRiskReason: Codable, Sendable, Equatable {
    public let code: String
    public let level: String
    /// One plain sentence for the user.
    public let message: String
    /// Tax / fee in percent, or a holder count.
    public let value: Double?
}

/// A token's safety report (`getTokenRisk`).
public struct TokenRisk: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let address: String
    public let level: TokenRiskLevel
    /// A major LayerHop lists itself; never checked upstream.
    public let verified: Bool
    public let symbol: String?
    public let reasons: [TokenRiskReason]
    /// "list", "goplus" or "none".
    public let source: String
    public let checkedAt: String
}

/// One wallet balance (`balances`): a token plus its amount.
public struct Balance: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let address: String
    public let symbol: String
    public let name: String?
    public let decimals: Int
    public let logoURI: String?
    public let priceUsd: Double?
    public let verified: Bool?
    public let popular: Bool?
    /// Base units.
    public let amount: String
    /// `amount` × `priceUsd`, when the price is known.
    public let valueUsd: Double?
}

/// A chain (or requested token) `balances` could not read.
public struct BalanceError: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let message: String
}

/// The body of `GET /v1/balances`.
public struct BalancesResponse: Codable, Sendable, Equatable {
    public let address: String
    public let vm: String
    /// Highest USD value first.
    public let balances: [Balance]
    public let totalUsd: Double
    public let errors: [BalanceError]
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
    /// A gasless swap (sent as `gasless=true`): the wallet signs EIP-712 typed data instead of sending
    /// a transaction and the provider's relayer takes the network fee from `srcToken`. ERC-20 input,
    /// same EVM chain only. Then `buildGasless` → sign → `submitGasless` → `gaslessStatus`.
    public var gasless: Bool
    /// The wallet that referred this user, for referral attribution. Never changes the fee or price.
    public var referrer: String?
    /// Copy a trade: the trade card's quote id or the wallet whose trade the user copies
    /// (attribution only).
    public var copyOf: String?
    /// What the payment is for (tip, split, payout, ...). Recorded on the order only.
    public var purpose: QuotePurpose?
    /// Pays one share of a split (`createSplit`), with `splitShare`.
    public var splitId: String?
    /// The share's index from 0.
    public var splitShare: Int?
    /// A message to the recipient on a tip or split payment (plain text, at most 140 characters).
    public var note: String?

    public init(
        srcChain: String, srcToken: String, amount: String,
        dstChain: String, dstToken: String,
        sender: String, recipient: String,
        slippageBps: Int? = nil, gasOnArrival: Bool = false, gasOnArrivalUsd: Double? = nil,
        gasless: Bool = false, referrer: String? = nil, copyOf: String? = nil,
        purpose: QuotePurpose? = nil, splitId: String? = nil, splitShare: Int? = nil, note: String? = nil
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
        self.gasless = gasless
        self.referrer = referrer
        self.copyOf = copyOf
        self.purpose = purpose
        self.splitId = splitId
        self.splitShare = splitShare
        self.note = note
    }
}

/// One contract call on the destination chain (`value` in wei, native outputs only).
public struct DestinationCall: Codable, Sendable, Equatable {
    public var to: String
    /// Hex calldata.
    public var data: String
    public var value: String?

    public init(to: String, data: String, value: String? = nil) {
        self.to = to
        self.data = data
        self.value = value
    }
}

/// A preset that builds the destination calls server-side.
public struct DestinationAction: Codable, Sendable, Equatable {
    public var type: String

    public init(type: String) { self.type = type }

    /// Approves the chain's Aave v3 Pool and supplies `dstAmount` of `dstToken` for `recipient`.
    public static let aaveV3Supply = DestinationAction(type: "aave-v3-supply")
}

/// The inputs of `quoteCalls` (`POST /v1/quote`): an exact-output quote whose output is used by
/// contract calls on the destination chain, run by the provider's executor (`msg.sender` is the
/// executor, not the user). Send `calls` or `action`.
public struct CallsQuoteParams: Sendable, Equatable {
    public var srcChain: String
    public var srcToken: String
    public var dstChain: String
    public var dstToken: String
    /// The exact amount of `dstToken` the calls receive (base units). The quote reports `srcAmount`.
    public var dstAmount: String
    public var sender: String
    public var recipient: String
    /// Defaults to 50 when nil or 0.
    public var slippageBps: Int?
    public var calls: [DestinationCall]?
    public var action: DestinationAction?
    public var referrer: String?
    public var copyOf: String?

    public init(
        srcChain: String, srcToken: String, dstChain: String, dstToken: String, dstAmount: String,
        sender: String, recipient: String, slippageBps: Int? = nil, calls: [DestinationCall]? = nil,
        action: DestinationAction? = nil, referrer: String? = nil, copyOf: String? = nil
    ) {
        self.srcChain = srcChain
        self.srcToken = srcToken
        self.dstChain = dstChain
        self.dstToken = dstToken
        self.dstAmount = dstAmount
        self.sender = sender
        self.recipient = recipient
        self.slippageBps = slippageBps
        self.calls = calls
        self.action = action
        self.referrer = referrer
        self.copyOf = copyOf
    }
}

/// The pre-quote simulation of destination calls.
public struct DestinationCallsSimulation: Codable, Sendable, Equatable {
    public let ok: Bool
    /// Gas the calls used together (decimal string).
    public let gasUsed: String
    /// Output left in the executor after the calls (decimal string); above 0 is lost to you.
    public let leftover: String?

    enum CodingKeys: String, CodingKey { case ok, gasUsed, leftover }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        gasUsed = try c.decodeNumberString(forKey: .gasUsed) ?? "0"
        leftover = try c.decodeNumberString(forKey: .leftover)
    }
}

/// The destination calls a quote's provider committed to run, and their simulation.
public struct DestinationCallsPlan: Codable, Sendable, Equatable {
    public let items: [EvmCall]
    /// The contract that receives the output and makes the calls (their `msg.sender`).
    public let executor: String
    public let executed: Bool
    public let simulation: DestinationCallsSimulation?
}

/// A fee taken from the input token (gasless quotes).
public struct GaslessFee: Codable, Sendable, Equatable {
    /// Base units of `token`.
    public let amount: String
    public let token: String
}

/// Gasless details of a quote. `dstAmount` already accounts for the gas fee.
public struct GaslessQuoteInfo: Codable, Sendable, Equatable {
    /// The network fee the provider's relayer takes from the input token.
    public let gasFee: GaslessFee?
    /// True when the wallet signs a gasless approval (permit) before the trade: two signatures.
    public let approval: Bool
}

/// A quote warning: the request was served, but not exactly as asked. Ignore codes you don't know.
public struct QuoteWarning: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
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
    /// What the sender pays (base units of the source token), on destination-call quotes.
    public let srcAmount: String?
    /// The destination calls the provider will run (`quoteCalls` only).
    public let calls: DestinationCallsPlan?
    /// Set on gasless quotes: build them with `buildGasless`, not `buildTx`.
    public let gasless: GaslessQuoteInfo?
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
    /// Set when the request was served, but not exactly as asked (e.g. GAS_ON_ARRIVAL_UNAVAILABLE).
    public let warnings: [QuoteWarning]?
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

/// One Tron smart-contract call (`TriggerSmartContract`). Addresses are base58 T-addresses; amounts
/// are sun (1 TRX = 1,000,000 sun).
public struct TronCall: Codable, Sendable, Equatable {
    /// The contract called (T-address).
    public let to: String
    /// ABI calldata, 0x hex.
    public let data: String
    /// TRX sent with the call, in sun.
    public let value: String
    /// `fee_limit` in sun: the most TRX the network may burn for this call's energy.
    public let feeLimit: String
}

/// An unsigned Tron transaction exactly as the node builds it (TronWeb's transaction object). Sign it
/// unchanged and broadcast it before `raw_data.expiration`. `jsonString()` gives the object with the
/// node's own keys (`txID`, `raw_data_hex`, `raw_data`, `visible`) to hand to TronWeb / TronLink.
public struct TronUnsignedTx: Codable, Sendable, Equatable {
    /// The transaction hash once broadcast: bare 64-hex, no 0x.
    public let txID: String
    /// The protobuf-encoded raw transaction (what gets signed).
    public let rawDataHex: String
    /// The decoded `raw_data` (contract, ref block, expiration, fee_limit), kept as raw JSON.
    public let rawData: JSONValue
    public let visible: Bool?

    enum CodingKeys: String, CodingKey {
        case txID
        case rawDataHex = "raw_data_hex"
        case rawData = "raw_data"
        case visible
    }

    /// The transaction as compact JSON with the node's keys.
    public func jsonString() throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(self), as: UTF8.self)
    }
}

/// A TRC-20 approval to send (as its own transaction) before the main Tron call.
public struct TronApproval: Codable, Sendable, Equatable {
    /// The TRC-20 token (T-address).
    public let token: String
    /// The spender (T-address).
    public let spender: String
    /// The allowance granted, base units.
    public let amount: String
    public let call: TronCall
    /// The prebuilt unsigned approval transaction.
    public let unsigned: TronUnsignedTx?
}

/// Tron transaction(s) for a quote (`vm` "tvm"). The SDK never signs: send `approval` first when set,
/// then the main transaction. Sign each `unsigned` unchanged with a Tron wallet (TronWeb / TronLink)
/// and broadcast it before `raw_data.expiration`, or rebuild it from its `call` with your own node.
/// Then `reportSubmitted` with the main transaction's `txID` (bare 64-hex).
public struct TronTx: Codable, Sendable, Equatable {
    /// `LayerHop.tronChainID`.
    public let chainId: Int64
    /// The owner (signer) of every call, T-address.
    public let from: String
    public let call: TronCall
    /// The prebuilt unsigned main transaction (absent in test mode).
    public let unsigned: TronUnsignedTx?
    /// Send this approval first when set.
    public let approval: TronApproval?
    /// True in test mode: a placeholder that moves no funds. Never broadcast it.
    public let sandbox: Bool

    enum CodingKeys: String, CodingKey { case chainId, from, call, unsigned, approval, sandbox }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chainId = try c.decode(Int64.self, forKey: .chainId)
        from = try c.decode(String.self, forKey: .from)
        call = try c.decode(TronCall.self, forKey: .call)
        unsigned = try c.decodeIfPresent(TronUnsignedTx.self, forKey: .unsigned)
        approval = try c.decodeIfPresent(TronApproval.self, forKey: .approval)
        sandbox = try c.decodeIfPresent(Bool.self, forKey: .sandbox) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(chainId, forKey: .chainId)
        try c.encode(from, forKey: .from)
        try c.encode(call, forKey: .call)
        try c.encodeIfPresent(unsigned, forKey: .unsigned)
        try c.encodeIfPresent(approval, forKey: .approval)
        if sandbox { try c.encode(true, forKey: .sandbox) }
    }
}

/// The transaction for the user's wallet, discriminated by the JSON `vm` field ("evm" | "svm" |
/// "tvm").
public enum BuiltTx: Codable, Sendable, Equatable {
    case evm(EvmTx)
    case svm(SvmTx)
    /// Tron (see `TronTx`).
    case tvm(TronTx)

    public var isEVM: Bool { if case .evm = self { return true } else { return false } }
    public var isSVM: Bool { if case .svm = self { return true } else { return false } }
    public var isTVM: Bool { if case .tvm = self { return true } else { return false } }
    public var evm: EvmTx? { if case let .evm(tx) = self { return tx } else { return nil } }
    public var svm: SvmTx? { if case let .svm(tx) = self { return tx } else { return nil } }
    public var tvm: TronTx? { if case let .tvm(tx) = self { return tx } else { return nil } }
    /// "evm", "svm" or "tvm".
    public var vm: String {
        switch self {
        case .evm: return "evm"
        case .svm: return "svm"
        case .tvm: return "tvm"
        }
    }
    /// True in test mode: the transaction is a placeholder that moves no funds. Never broadcast it.
    public var sandbox: Bool {
        switch self {
        case let .evm(tx): return tx.sandbox
        case let .svm(tx): return tx.sandbox
        case let .tvm(tx): return tx.sandbox
        }
    }

    private enum VMKey: String, CodingKey { case vm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: VMKey.self)
        let vm = try c.decode(String.self, forKey: .vm)
        switch vm {
        case "evm": self = .evm(try EvmTx(from: decoder))
        case "svm": self = .svm(try SvmTx(from: decoder))
        case "tvm": self = .tvm(try TronTx(from: decoder))
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
        case let .tvm(tx): try tx.encode(to: encoder)
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
    /// Tron: the energy the simulated call used.
    public let energyUsed: Int64?
    public let needsApproval: Bool
    public let error: SimulationError?
    public let tx: BuiltTx?

    enum CodingKeys: String, CodingKey {
        case quoteId, provider, ok, vm, simulated, gasEstimate, computeUnits, energyUsed, needsApproval, error, tx
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
        energyUsed = try c.decodeNumberString(forKey: .energyUsed).flatMap { Int64($0) }
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

// MARK: - Gasless

/// EIP-712 typed data exactly as the provider returned it. Sign it unchanged
/// (`eth_signTypedData_v4`); `jsonString()` gives the JSON text a wallet takes.
public struct Eip712TypedData: Codable, Sendable, Equatable {
    public let types: JSONValue
    public let domain: JSONValue
    public let message: JSONValue
    public let primaryType: String

    /// The typed data as compact JSON text (`{"domain":…,"message":…,"primaryType":…,"types":…}`).
    public func jsonString() throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(self), as: UTF8.self)
    }
}

/// One thing the wallet signs for a gasless quote.
public struct GaslessSignable: Codable, Sendable, Equatable {
    /// The provider's kind, e.g. "permit" (approvals) or "settler_metatransaction" (trade).
    public let type: String
    public let eip712: Eip712TypedData
}

/// What the wallet signs for a gasless quote (`buildGasless`): `approval` (when set) and `trade`, on
/// `chainId`. The SDK never signs.
public struct GaslessSignRequest: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let approval: GaslessSignable?
    public let trade: GaslessSignable
    /// The network fee the relayer takes from the input token.
    public let gasFee: GaslessFee?
}

/// The state of a submitted gasless order.
public struct GaslessOrderStatus: Codable, Sendable, Equatable {
    public let quoteId: String
    public let provider: ProviderID
    /// The provider's order id (0x: the trade's EIP-712 hash).
    public let orderId: String
    public let state: OrderState
    /// The relayer's transaction, once mined.
    public let srcTxHash: String?
    /// The provider's failure reason when failed.
    public let reason: String?
}

// MARK: - Splits, tip jars and payouts

/// One person's share in `CreateSplitParams.shares`: a label and, for custom shares, an amount in base
/// units (all or none; they must add up to `total`).
public struct SplitShareInput: Codable, Sendable, Equatable {
    public var label: String?
    public var amount: String?

    public init(label: String? = nil, amount: String? = nil) {
        self.label = label
        self.amount = amount
    }
}

/// The body of `POST /v1/splits`. Send `participants` (equal shares) or `shares`.
public struct CreateSplitParams: Encodable, Sendable, Equatable {
    /// Address, ENS name or .sol name of whoever is owed.
    public var recipient: String
    /// The chain slug or id they receive on.
    public var chain: String
    /// A listed token symbol or address on that chain.
    public var token: String
    /// Base units of `token`.
    public var total: String
    /// Equal shares for this many people (2-50).
    public var participants: Int?
    public var shares: [SplitShareInput]?
    /// Plain text, kept to 140 characters.
    public var note: String?

    public init(
        recipient: String, chain: String, token: String, total: String, participants: Int? = nil,
        shares: [SplitShareInput]? = nil, note: String? = nil
    ) {
        self.recipient = recipient
        self.chain = chain
        self.token = token
        self.total = total
        self.participants = participants
        self.shares = shares
        self.note = note
    }
}

/// The body of `PATCH /v1/splits/{id}`: only non-nil fields are sent. An empty `note` clears it
/// (sends null).
public struct UpdateSplitParams: Encodable, Sendable, Equatable {
    public var note: String?
    /// One label per share.
    public var labels: [String]?
    /// "open" or "closed" (closed stops payments).
    public var status: String?

    public init(note: String? = nil, labels: [String]? = nil, status: String? = nil) {
        self.note = note
        self.labels = labels
        self.status = status
    }

    private enum CodingKeys: String, CodingKey { case note, labels, status }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNullable(note, forKey: .note)
        try c.encodeIfPresent(labels, forKey: .labels)
        try c.encodeIfPresent(status, forKey: .status)
    }
}

/// The token of a split.
public struct SplitToken: Codable, Sendable, Equatable {
    public let address: String
    public let symbol: String
    public let decimals: Int
}

/// One share of a split.
public struct SplitShare: Codable, Sendable, Equatable {
    /// The share's number from 0 (`QuoteParams.splitShare`).
    public let index: Int
    public let label: String
    /// Base units of the split's token.
    public let amount: String
    /// Base units delivered by filled orders for this share.
    public let received: String
    /// "unpaid", "partial" or "paid".
    public let status: String
    public let payments: Int
    public let pending: Int
}

/// A split bill. Each participant pays a share with
/// `quote(QuoteParams(..., purpose: .split, splitId: id, splitShare: index))`.
public struct Split: Codable, Sendable, Equatable {
    public let id: String
    /// The split's page.
    public let url: String
    /// "open" or "closed".
    public let status: String
    public let note: String?
    public let recipient: String
    /// The ENS / .sol name given at creation.
    public let recipientName: String?
    public let chainId: Int64
    public let chain: String
    public let token: SplitToken
    public let total: String
    public let collected: String
    public let paidCount: Int
    public let shares: [SplitShare]
    public let createdAt: String
    public let updatedAt: String
}

/// The body of `POST /v1/splits`: the split plus its edit secret, shown only once. The split's fields
/// are readable directly (`created.id`).
@dynamicMemberLookup
public struct SplitCreated: Codable, Sendable, Equatable {
    public let split: Split
    /// The edit secret for `updateSplit`. LayerHop stores only its hash.
    public let editToken: String
    /// The split's page with the secret in the URL fragment.
    public let editUrl: String

    public subscript<T>(dynamicMember keyPath: KeyPath<Split, T>) -> T { split[keyPath: keyPath] }

    enum CodingKeys: String, CodingKey { case editToken, editUrl }

    public init(from decoder: Decoder) throws {
        split = try Split(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        editToken = try c.decode(String.self, forKey: .editToken)
        editUrl = try c.decode(String.self, forKey: .editUrl)
    }

    public func encode(to encoder: Encoder) throws {
        try split.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(editToken, forKey: .editToken)
        try c.encode(editUrl, forKey: .editUrl)
    }
}

/// A tip message.
public struct TipMessage: Codable, Sendable, Equatable {
    public let text: String
    public let at: String
}

/// The body of `GET /v1/tip-jars/{address}`: tip counters and the latest 10 messages.
public struct TipJar: Codable, Sendable, Equatable {
    public let address: String
    /// Distinct wallets with a filled tip.
    public let tippers: Int
    public let tips: Int
    public let messages: [TipMessage]
}

/// One payout row. `amount` is in HUMAN units of `token` ("25", "0.5").
public struct PayoutRowInput: Codable, Sendable, Equatable {
    /// Address, ENS name or .sol name.
    public var recipient: String
    public var amount: String
    /// Symbol or address.
    public var token: String
    /// Chain slug or id.
    public var chain: String
    public var label: String?

    public init(recipient: String, amount: String, token: String, chain: String, label: String? = nil) {
        self.recipient = recipient
        self.amount = amount
        self.token = token
        self.chain = chain
        self.label = label
    }

    enum CodingKeys: String, CodingKey { case recipient, amount, token, chain, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipient = try c.decode(String.self, forKey: .recipient)
        amount = try c.decodeNumberString(forKey: .amount) ?? ""
        token = try c.decode(String.self, forKey: .token)
        chain = try c.decodeNumberString(forKey: .chain) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }
}

/// The body of `POST /v1/payouts/plan`. Send `rows` (up to 100) or `csv`.
public struct PlanPayoutsParams: Encodable, Sendable, Equatable {
    /// The chain the payer pays from.
    public var srcChain: String
    /// The (listed) token the payer pays with.
    public var srcToken: String
    /// The payer's address on `srcChain`.
    public var sender: String
    public var rows: [PayoutRowInput]?
    /// `recipient,amount,token,chain[,label]` lines, header optional.
    public var csv: String?

    public init(srcChain: String, srcToken: String, sender: String, rows: [PayoutRowInput]? = nil, csv: String? = nil) {
        self.srcChain = srcChain
        self.srcToken = srcToken
        self.sender = sender
        self.rows = rows
        self.csv = csv
    }
}

/// A token as splits and payouts describe it.
public struct PayoutToken: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let address: String
    public let symbol: String
    public let decimals: Int
    /// USD price when known.
    public let usd: Double?
}

/// Why a payout row is invalid.
public struct PayoutRowError: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
}

/// A resolved payout recipient.
public struct PayoutRecipient: Codable, Sendable, Equatable {
    public let address: String
    public let name: String?
}

/// One checked row of a payout plan.
public struct PayoutPlanRow: Codable, Sendable, Equatable {
    /// Row number from 0 (header excluded).
    public let index: Int
    /// 1-based CSV line (0 for JSON rows).
    public let line: Int
    public let input: PayoutRowInput
    public let ok: Bool
    public let error: PayoutRowError?
    public let recipient: PayoutRecipient?
    public let chainId: Int64?
    public let chain: String?
    public let token: PayoutToken?
    /// Base units of `token`.
    public let amount: String?
    /// "transfer" or "route".
    public let kind: String?
}

/// Where a payout plan pays from.
public struct PayoutSource: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let chain: String
    public let sender: String
    public let token: PayoutToken
}

/// A transfer batch: build it with `buildPayoutTransfers` (no LayerHop fee).
public struct PayoutTransferBatch: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let token: String
    /// Row indices in input order.
    public let rows: [Int]
    /// Base units of the payer's token.
    public let total: String
}

/// Routed rows of one destination chain: quote each with `purpose: .payout` (normal swap fee).
public struct PayoutRouteGroup: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let rows: [Int]
}

/// What one destination token adds up to.
public struct PayoutTotal: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let token: String
    public let symbol: String
    public let decimals: Int
    public let amount: String
    public let formatted: String
    public let rows: Int
}

/// The body of `POST /v1/payouts/plan`: every row checked, valid rows grouped into transfer batches
/// and routes.
public struct PayoutPlan: Codable, Sendable, Equatable {
    public let source: PayoutSource
    public let rows: [PayoutPlanRow]
    public let transfers: [PayoutTransferBatch]
    public let routes: [PayoutRouteGroup]
    public let transferTotal: String
    public let totals: [PayoutTotal]
    public let valid: Int
    public let invalid: Int
    public let warnings: [String]
}

/// One transfer of a batch: an address (resolve names with `planPayouts` first) and base units.
public struct PayoutTransfer: Codable, Sendable, Equatable {
    public var recipient: String
    public var amount: String

    public init(recipient: String, amount: String) {
        self.recipient = recipient
        self.amount = amount
    }
}

/// The body of `POST /v1/payouts/transfers`.
public struct BuildPayoutTransfersParams: Encodable, Sendable, Equatable {
    public var chain: String
    public var token: String
    public var sender: String
    /// At most 20 on EVM chains and 8 on Solana.
    public var transfers: [PayoutTransfer]

    public init(chain: String, token: String, sender: String, transfers: [PayoutTransfer]) {
        self.chain = chain
        self.token = token
        self.sender = sender
        self.transfers = transfers
    }
}

/// One transfer batch for the payer's wallet to sign: EVM `calls` (one per transfer, in order) or a
/// Solana `serializedTx` (base64, unsigned). Nothing is signed.
public struct PayoutTransfers: Codable, Sendable, Equatable {
    /// "evm" or "svm".
    public let vm: String
    public let chainId: Int64
    public let token: PayoutToken
    public let calls: [EvmCall]?
    public let serializedTx: String?
}

// MARK: - Recurring orders

/// The body of `POST /v1/recurring-orders`. Nil optional fields are omitted.
public struct CreateRecurringOrderParams: Encodable, Sendable, Equatable {
    /// The Solana wallet (base58) that funds, signs and owns the order.
    public var wallet: String
    /// The token bought on each order: mint or symbol.
    public var dstToken: String
    /// The whole budget in base units of `srcToken`, deposited when the order opens.
    public var amount: String
    /// The number of buys (at least 2; each worth at least $50).
    public var orders: Int
    /// Seconds between buys (86400 = daily, 604800 = weekly).
    public var intervalSeconds: Int
    /// The token spent: mint or symbol (API default USDC).
    public var srcToken: String?
    /// Only "solana" (the API default).
    public var chain: String?

    public init(
        wallet: String, dstToken: String, amount: String, orders: Int, intervalSeconds: Int,
        srcToken: String? = nil, chain: String? = nil
    ) {
        self.wallet = wallet
        self.dstToken = dstToken
        self.amount = amount
        self.orders = orders
        self.intervalSeconds = intervalSeconds
        self.srcToken = srcToken
        self.chain = chain
    }
}

/// The fees of a recurring order: always 0.
public struct RecurringOrderFees: Codable, Sendable, Equatable {
    public let ourFeeBps: Int
    public let integratorFeeBps: Int
}

/// The body of `POST /v1/recurring-orders`: the unsigned `tx` for `wallet` to sign (sign only), and
/// the `requestId` to `submitRecurringOrder` it with.
public struct RecurringOrderBuild: Codable, Sendable, Equatable {
    public let object: String
    public let livemode: Bool
    /// "jupiter" (live) or "sandbox" (test mode).
    public let provider: ProviderID
    public let chainId: Int64
    public let wallet: String
    public let srcToken: String
    public let dstToken: String
    public let amount: String
    public let amountPerOrder: String
    public let orders: Int
    public let intervalSeconds: Int
    public let fees: RecurringOrderFees
    public let requestId: String
    public let tx: SvmTx
}

/// One buy of a recurring order.
public struct RecurringOrderFill: Codable, Sendable, Equatable {
    public let txHash: String
    public let amount: String
    public let dstAmount: String
    public let feeAmount: String
    public let feeToken: String?
    public let filledAt: String?
}

/// A Solana recurring order (Jupiter Recurring), read live from Jupiter. Base units throughout.
public struct RecurringOrder: Codable, Sendable, Equatable {
    /// The order account.
    public let id: String
    public let object: String
    public let provider: ProviderID
    public let chainId: Int64
    /// "active", "completed" or "cancelled".
    public let status: String
    public let wallet: String
    public let srcToken: String
    public let dstToken: String
    public let amount: String
    public let amountPerOrder: String
    public let orders: Int
    public let ordersFilled: Int
    public let intervalSeconds: Int
    public let spentAmount: String
    public let withdrawnAmount: String
    public let receivedAmount: String
    public let openTxHash: String?
    public let closeTxHash: String?
    public let createdAt: String?
    /// Up to 50 most recent buys.
    public let fills: [RecurringOrderFill]
}

/// Filters for `GET /v1/recurring-orders`.
public struct ListRecurringOrdersParams: Sendable, Equatable {
    public var wallet: String
    /// "active" or "history".
    public var status: String?
    public var page: Int?

    public init(wallet: String, status: String? = nil, page: Int? = nil) {
        self.wallet = wallet
        self.status = status
        self.page = page
    }
}

/// The body of `GET /v1/recurring-orders`.
public struct ListRecurringOrdersResponse: Codable, Sendable, Equatable {
    public let recurringOrders: [RecurringOrder]
    public let page: Int
    public let totalPages: Int
}

/// The body of `POST /v1/recurring-orders/submit`.
public struct SubmitRecurringOrderResponse: Codable, Sendable, Equatable {
    public let txHash: String
    /// The order account (create), or nil.
    public let order: String?
}

/// The body of `POST /v1/recurring-orders/{id}/cancel`: the cancel tx to sign and submit with
/// `requestId`.
public struct CancelRecurringOrderResponse: Codable, Sendable, Equatable {
    public let requestId: String
    public let tx: SvmTx
}
