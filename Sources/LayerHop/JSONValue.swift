import Foundation

/// Any JSON value, kept as the API sent it: error `details`, EIP-712 typed data to sign unchanged,
/// a Tron transaction's `raw_data`. Integers that fit in Int64 stay exact.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? c.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .int(i): try c.encode(i)
        case let .double(d): try c.encode(d)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    /// The member `key` of an object, or nil.
    public subscript(key: String) -> JSONValue? {
        if case let .object(o) = self { return o[key] }
        return nil
    }

    /// The element at `index` of an array, or nil.
    public subscript(index: Int) -> JSONValue? {
        if case let .array(a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var stringValue: String? { if case let .string(s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case let .bool(b) = self { return b } else { return nil } }
    /// The value of an integer, or nil (also for a fractional number).
    public var intValue: Int64? {
        switch self {
        case let .int(i): return i
        case let .double(d): return d.rounded() == d && abs(d) < 9e15 ? Int64(d) : nil
        default: return nil
        }
    }
    /// The value of any number, or nil.
    public var doubleValue: Double? {
        switch self {
        case let .int(i): return Double(i)
        case let .double(d): return d
        default: return nil
        }
    }
    public var arrayValue: [JSONValue]? { if case let .array(a) = self { return a } else { return nil } }
    public var objectValue: [String: JSONValue]? { if case let .object(o) = self { return o } else { return nil } }
    public var isNull: Bool { self == .null }

    /// The value as compact JSON text (keys sorted), e.g. to pass typed data to a wallet.
    public func jsonString() throws -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try e.encode(self), as: UTF8.self)
    }
}
