import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every error the client throws (besides `CancellationError` when the calling task is cancelled).
public enum LayerHopError: Error, Sendable, Equatable {
    /// A non-2xx response. `code` is a stable error code such as `QUOTE_EXPIRED` or `NO_ROUTE`
    /// (https://docs.layerhop.com/errors/<code>).
    case api(code: String, message: String, status: Int, requestId: String?)
    /// The request never got a response (offline, DNS, TLS, timeout...).
    case network(URLError)
    /// The response was not the JSON the SDK expected.
    case decoding(String)
    /// The server answered with something that is not an HTTP response.
    case invalidResponse
    /// `watch` gave up before the order reached a final state.
    case watchTimeout

    /// The stable API error code, or nil for non-API errors.
    public var code: String? {
        if case let .api(code, _, _, _) = self { return code }
        return nil
    }

    /// The HTTP status of an API error, or nil.
    public var status: Int? {
        if case let .api(_, _, status, _) = self { return status }
        return nil
    }

    /// The request id of an API error (from the body or the x-request-id header), or nil.
    public var requestId: String? {
        if case let .api(_, _, _, requestId) = self { return requestId }
        return nil
    }

    /// A human-readable message.
    public var message: String {
        switch self {
        case let .api(_, message, _, _): return message
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
        case let .api(code, message, status, requestId):
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
    }
    let error: Body?
}

func decodeAPIError(status: Int, headerRequestId: String?, body: Data) -> LayerHopError {
    var code = "INTERNAL"
    var message = httpStatusText(status)
    var requestId = headerRequestId
    if let env = try? JSONDecoder().decode(APIErrorEnvelope.self, from: body), let e = env.error {
        if let c = e.code, !c.isEmpty { code = c }
        if let m = e.message, !m.isEmpty { message = m }
        if let r = e.requestId, !r.isEmpty { requestId = r }
    }
    return .api(code: code, message: message, status: status, requestId: requestId)
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
