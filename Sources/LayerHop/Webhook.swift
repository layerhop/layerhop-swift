import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Why a webhook signature was rejected.
public enum WebhookSignatureError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The header has no numeric `t=` or no hex `v1=` value.
    case malformedHeader
    /// The timestamp is further than the tolerance from now (replay protection).
    case timestampOutsideTolerance
    /// No `v1` signature matches the body and secret.
    case signatureMismatch

    public var description: String {
        switch self {
        case .malformedHeader: return "layerhop: malformed LayerHop-Signature header"
        case .timestampOutsideTolerance: return "layerhop: webhook timestamp outside tolerance"
        case .signatureMismatch: return "layerhop: webhook signature mismatch"
        }
    }
}

/// Webhook signature helpers.
///
/// LayerHop signs every delivery with `LayerHop-Signature: t=<unix>,v1=<hex>`, where the signature
/// is `hex(HMAC-SHA256(secret, "<t>.<rawBody>"))`. Several `v1` values may be present during secret
/// rotation; any match is accepted.
public enum Webhook {
    /// The header carrying the signature.
    public static let signatureHeader = "LayerHop-Signature"
    /// The header carrying the event type.
    public static let eventHeader = "LayerHop-Event"
    /// The header carrying the delivery id.
    public static let deliveryHeader = "LayerHop-Delivery"
    /// The maximum age of a signature timestamp, in seconds.
    public static let defaultTolerance: TimeInterval = 300

    /// Checks a `LayerHop-Signature` header against the raw request body. Pass the body exactly as
    /// received, before any JSON parsing. `tolerance <= 0` means `defaultTolerance`.
    /// - Throws: `WebhookSignatureError`.
    public static func verifySignature(
        secret: String, body: Data, header: String?, tolerance: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) throws {
        let tolerance = tolerance > 0 ? tolerance : defaultTolerance
        var ts: String?
        var sigs: [[UInt8]] = []
        for part in (header ?? "").split(separator: ",", omittingEmptySubsequences: false) {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let k = trimmed[..<eq]
            let v = String(trimmed[trimmed.index(after: eq)...])
            switch k {
            case "t": ts = v
            case "v1": if let b = hexDecode(v) { sigs.append(b) }
            default: break
            }
        }
        guard let ts, let t = Int64(ts), !sigs.isEmpty else {
            throw WebhookSignatureError.malformedHeader
        }
        let age = abs(now.timeIntervalSince1970 - Double(t))
        if age > tolerance { throw WebhookSignatureError.timestampOutsideTolerance }
        let want = hmacSHA256(key: Array(secret.utf8), message: Array((ts + ".").utf8) + Array(body))
        for s in sigs where constantTimeEqual(s, want) { return }
        throw WebhookSignatureError.signatureMismatch
    }

    /// String-body overload of `verifySignature(secret:body:header:tolerance:now:)` (UTF-8).
    public static func verifySignature(
        secret: String, body: String, header: String?, tolerance: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) throws {
        try verifySignature(secret: secret, body: Data(body.utf8), header: header, tolerance: tolerance, now: now)
    }

    /// Returns whether the signature is valid, without saying why not.
    public static func isValidSignature(
        secret: String, body: Data, header: String?, tolerance: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) -> Bool {
        (try? verifySignature(secret: secret, body: body, header: header, tolerance: tolerance, now: now)) != nil
    }

    /// Verifies the signature, then decodes the event (with `raw` set to the body).
    /// - Throws: `WebhookSignatureError`, or `LayerHopError.decoding` for a body that is not an event.
    public static func constructEvent(
        secret: String, body: Data, header: String?, tolerance: TimeInterval = defaultTolerance,
        now: Date = Date()
    ) throws -> WebhookEvent {
        try verifySignature(secret: secret, body: body, header: header, tolerance: tolerance, now: now)
        do {
            var ev = try JSONDecoder().decode(WebhookEvent.self, from: body)
            ev.raw = body
            return ev
        } catch {
            throw LayerHopError.decoding("decode webhook event: \(error)")
        }
    }

    /// Builds a `LayerHop-Signature` header value. Useful for testing your webhook handler.
    public static func sign(secret: String, body: Data, timestamp: Date = Date()) -> String {
        let ts = String(Int64(timestamp.timeIntervalSince1970.rounded(.down)))
        return "t=\(ts),v1=\(computeSignature(secret: secret, timestamp: ts, body: body))"
    }

    /// String-body overload of `sign(secret:body:timestamp:)` (UTF-8).
    public static func sign(secret: String, body: String, timestamp: Date = Date()) -> String {
        sign(secret: secret, body: Data(body.utf8), timestamp: timestamp)
    }

    /// `hex(HMAC-SHA256(secret, "<timestamp>.<body>"))`.
    public static func computeSignature(secret: String, timestamp: String, body: Data) -> String {
        hexEncode(hmacSHA256(key: Array(secret.utf8), message: Array((timestamp + ".").utf8) + Array(body)))
    }
}

// MARK: - Crypto helpers

func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
    #if canImport(CryptoKit)
    let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
    return Array(mac)
    #else
    return PureHMACSHA256.mac(key: key, message: message)
    #endif
}

func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
}

func hexEncode(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count * 2)
    for b in bytes {
        out.append(digits[Int(b >> 4)])
        out.append(digits[Int(b & 0x0F)])
    }
    return String(decoding: out, as: UTF8.self)
}

/// Decodes an even-length hex string (either case); nil when invalid.
func hexDecode(_ s: String) -> [UInt8]? {
    let chars = Array(s.utf8)
    guard chars.count % 2 == 0 else { return nil }
    func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x61...0x66: return c - 0x61 + 10
        case 0x41...0x46: return c - 0x41 + 10
        default: return nil
        }
    }
    var out = [UInt8]()
    out.reserveCapacity(chars.count / 2)
    var i = 0
    while i < chars.count {
        guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
        out.append(hi << 4 | lo)
        i += 2
    }
    return out
}
