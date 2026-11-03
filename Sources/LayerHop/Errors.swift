import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every error the client throws (besides `CancellationError` when the calling task is cancelled).
public enum LayerHopError: Error, Sendable, Equatable {
    /// A non-2xx response. `code` is a stable error code such as `QUOTE_EXPIRED` or `NO_ROUTE`
    /// (https://docs.layerhop.com/errors/<code>). `details` is the raw `error.details` object when
    /// the API sent one (read it with `suggestions`, `minAmount`, `providerErrors`).
    case api(code: String, message: String, status: Int, requestId: String?, details: JSONValue? = nil)
    /// The request never got a response (offline, DNS, TLS, timeout...).
    case network(URLError)
    /// The response was not the JSON the SDK expected (also: `buildTx` on a gasless quote, or
    /// `buildGasless` on a quote that is not gasless).
    case decoding(String)
    /// The server answered with something that is not an HTTP response.
    case invalidResponse
    /// `watch` gave up before the order reached a final state.
    case watchTimeout

    /// The stable API error code, or nil for non-API errors.
    public var code: String? {
        if case let .api(code, _, _, _, _) = self { return code }
        return nil
    }

    /// The HTTP status of an API error, or nil.
    public var status: Int? {
        if case let .api(_, _, status, _, _) = self { return status }
        return nil
    }

    /// The request id of an API error (from the body or the x-request-id header), or nil.
    public var requestId: String? {
        if case let .api(_, _, _, requestId, _) = self { return requestId }
        return nil
    }

    /// The raw `error.details` object of an API error, or nil when the API sent none.
    public var details: JSONValue? {
        if case let .api(_, _, _, _, details) = self { return details }
        return nil
    }

    /// Alternatives that quoted, from `details.suggestions` (on `NO_ROUTE`, and on
    /// `UNSUPPORTED_CHAIN` into a one-route chain such as Blast). Malformed entries are dropped; at
    /// most 4. Empty when there are none.
    public var suggestions: [RouteSuggestion] { parseRouteSuggestions(details) }

    /// `AMOUNT_TOO_SMALL`: the route's minimum in base units of `srcToken`, when LayerHop could tell.
    public var minAmount: String? { details?["minAmount"]?.stringValue }

    /// `AMOUNT_TOO_SMALL`: the route's minimum in USD, when known.
    public var minAmountUsd: Double? { details?["minAmountUsd"]?.doubleValue }

    /// `AMOUNT_TOO_SMALL`: true when the minimum was found by probing $10 / $25 / $50 (the true
    /// minimum is at most `minAmount`).
    public var minAmountApprox: Bool? { details?["minAmountApprox"]?.boolValue }

    /// The per-provider errors in `details.errors` (e.g. on `NO_ROUTE`). Malformed entries are
    /// skipped.
    public var providerErrors: [ProviderFailure] {
        guard let list = details?["errors"]?.arrayValue else { return [] }
        return list.compactMap { e in
            guard let p = e["provider"]?.stringValue, let c = e["code"]?.stringValue,
                let m = e["message"]?.stringValue
            else { return nil }
            return ProviderFailure(provider: p, code: c, message: m)
        }
    }

    /// A human-readable message.
    public var message: String {
        switch self {
        case let .api(_, message, _, _, _): return message
        case let .network(err): return "network error: \(err.localizedDescription) (URLError \(err.code.rawValue))"
        case let .decoding(msg): return msg
        case .invalidResponse: return "the server did not return an HTTP response"
        case .watchTimeout: return "watch timed out before the order was final"
        }
    }

    /// The error catalog page for an API error code, or nil.
    public var docsURL: URL? {
        guard let code else { return nil }
        return URL(string: "https://docs.layerhop.com/errors/\(code)")
    }
}

extension LayerHopError: CustomStringConvertible, LocalizedError {
    public var description: String {
        switch self {
        case let .api(code, message, status, requestId, _):
            var s = "layerhop: \(code) (\(status)): \(message)"
            if let requestId, !requestId.isEmpty { s += " [requestId \(requestId)]" }
            return s
        default:
            return "layerhop: \(message)"
        }
    }

    public var errorDescription: String? { description }
}

private struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String?
        let message: String?
        let requestId: String?
        let details: JSONValue?
    }
    let error: Body?
}

func decodeAPIError(status: Int, headerRequestId: String?, body: Data) -> LayerHopError {
    var code = "INTERNAL"
    var message = httpStatusText(status)
    var requestId = headerRequestId
    var details: JSONValue?
    if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: body), let e = env.error {
        if let c = e.code, !c.isEmpty { code = c }
        if let m = e.message, !m.isEmpty { message = m }
        if let r = e.requestId, !r.isEmpty { requestId = r }
        if let d = e.details, d.objectValue != nil { details = d }
    }
    return .api(code: code, message: message, status: status, requestId: requestId, details: details)
}

// MARK: - Route suggestions

/// One quotable leg: the fields a quote request takes (chain ids, token addresses, base units).
public struct RouteLeg: Codable, Sendable, Equatable {
    public let srcChain: Int64
    public let srcToken: String
    /// Base units of `srcToken`.
    public let amount: String
    public let dstChain: Int64
    public let dstToken: String
    /// Estimated output of this leg in base units of `dstToken` (quote again before signing).
    public let dstAmount: String?
}

/// The chain and token between the two steps of a `via_hub` suggestion.
public struct RouteHub: Codable, Sendable, Equatable {
    public let chainId: Int64
    public let token: String
    public let symbol: String
    public let decimals: Int
}

/// An alternative that quoted when the requested route did not (`LayerHopError.suggestions`).
/// `kind` is "dst_token" (a different destination token), "src_token" (pay with a different token)
/// or "via_hub" (two signed steps through `hub`; `steps` holds both legs). The leg fields describe
/// the whole trip; amounts are estimates, so quote again before signing.
public struct RouteSuggestion: Codable, Sendable, Equatable {
    public let kind: String
    /// Short human text, e.g. "Receive USDC on Ethereum instead".
    public let message: String
    /// The token that changed, for labels.
    public let symbol: String?
    public let srcChain: Int64
    public let srcToken: String
    public let amount: String
    public let dstChain: Int64
    public let dstToken: String
    public let dstAmount: String?
    /// `via_hub` only.
    public let hub: RouteHub?
    /// `via_hub` only: the two legs in order.
    public let steps: [RouteLeg]?

    /// The suggestion as one leg (the whole trip).
    public var leg: RouteLeg {
        RouteLeg(
            srcChain: srcChain, srcToken: srcToken, amount: amount, dstChain: dstChain, dstToken: dstToken,
            dstAmount: dstAmount)
    }
}

/// At most this many suggestions are read from an error.
let maxRouteSuggestions = 4

private func parseLeg(_ v: JSONValue) -> RouteLeg? {
    guard let sc = v["srcChain"]?.intValue, let dc = v["dstChain"]?.intValue,
        let st = v["srcToken"]?.stringValue, let dt = v["dstToken"]?.stringValue,
        let amount = v["amount"]?.stringValue, isDigits(amount), amount != "0"
    else { return nil }
    var dstAmount: String?
    if let d = v["dstAmount"], !d.isNull {
        guard let s = d.stringValue, isDigits(s) else { return nil }
        dstAmount = s
    }
    return RouteLeg(srcChain: sc, srcToken: st, amount: amount, dstChain: dc, dstToken: dt, dstAmount: dstAmount)
}

private func isDigits(_ s: String) -> Bool {
    !s.isEmpty && s.utf8.count <= 78 && s.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
}

/// Reads `details.suggestions` leniently: entries with a wrong shape are skipped, at most 4 kept.
public func parseRouteSuggestions(_ details: JSONValue?) -> [RouteSuggestion] {
    guard let raw = details?["suggestions"]?.arrayValue else { return [] }
    var out: [RouteSuggestion] = []
    for s in raw {
        guard let leg = parseLeg(s), let kind = s["kind"]?.stringValue,
            kind == "dst_token" || kind == "src_token" || kind == "via_hub",
            let message = s["message"]?.stringValue
        else { continue }
        var hub: RouteHub?
        var steps: [RouteLeg]?
        if kind == "via_hub" {
            guard let st = s["steps"]?.arrayValue, st.count == 2 else { continue }
            let legs = st.compactMap(parseLeg)
            guard legs.count == 2, let h = s["hub"], let hc = h["chainId"]?.intValue,
                let ht = h["token"]?.stringValue, let hs = h["symbol"]?.stringValue,
                let hd = h["decimals"]?.intValue
            else { continue }
            hub = RouteHub(chainId: hc, token: ht, symbol: hs, decimals: Int(hd))
            steps = legs
        }
        out.append(RouteSuggestion(
            kind: kind, message: message, symbol: s["symbol"]?.stringValue,
            srcChain: leg.srcChain, srcToken: leg.srcToken, amount: leg.amount,
            dstChain: leg.dstChain, dstToken: leg.dstToken, dstAmount: leg.dstAmount,
            hub: hub, steps: steps))
        if out.count >= maxRouteSuggestions { break }
    }
    return out
}


func httpStatusText(_ status: Int) -> String {
    switch status {
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 402: return "Payment Required"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 408: return "Request Timeout"
    case 409: return "Conflict"
    case 410: return "Gone"
    case 413: return "Request Entity Too Large"
    case 415: return "Unsupported Media Type"
    case 422: return "Unprocessable Entity"
    case 429: return "Too Many Requests"
    case 500: return "Internal Server Error"
    case 501: return "Not Implemented"
    case 502: return "Bad Gateway"
    case 503: return "Service Unavailable"
    case 504: return "Gateway Timeout"
    default: return "HTTP \(status)"
    }
}
