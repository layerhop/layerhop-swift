// LayerHop is a Swift client for the LayerHop cross-chain swap API.
//
// The client never holds private keys: it returns unsigned transactions that your own wallet
// signs and broadcasts. Amounts are integer strings in base units.

import Foundation

/// SDK-wide constants.
public enum LayerHop {
    /// The SDK version, sent in the User-Agent header.
    public static let version = "0.6.0"
    /// The hosted API origin.
    public static let defaultBaseURL = "https://api.layerhop.com"
    /// LayerHop's internal chain id for Solana.
    public static let solanaChainID: Int64 = 7_565_164
    /// The default User-Agent header value ("layerhop-swift/<version>").
    public static var defaultUserAgent: String { "layerhop-swift/\(version)" }
}

/// A string-backed value that tolerates values this SDK version does not know yet.
public protocol LayerHopStringValue: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral, CustomStringConvertible where RawValue == String
{
    init(rawValue: String)
}

extension LayerHopStringValue {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
    public var description: String { rawValue }
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// A liquidity provider id ("relay", "debridge", "jupiter", ...). "sandbox" serves every request made
/// with an lh_test_ key; "direct" is a plain token transfer used by checkout.
public typealias ProviderID = String

/// The state reported by `GET /v1/orders/{provider}/{id}`.
public struct OrderState: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pending: OrderState = "pending"
    public static let filled: OrderState = "filled"
    public static let refunded: OrderState = "refunded"
    public static let failed: OrderState = "failed"
    public static let unknown: OrderState = "unknown"

    /// Whether the state will not change any more (filled, refunded or failed).
    public var isFinal: Bool { self == .filled || self == .refunded || self == .failed }
}

/// The status of a checkout session. Paid is final; treat processing as not yet paid.
public struct CheckoutStatus: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let open: CheckoutStatus = "open"
    public static let processing: CheckoutStatus = "processing"
    public static let paid: CheckoutStatus = "paid"
    public static let expired: CheckoutStatus = "expired"
    public static let needsReview: CheckoutStatus = "needs_review"
}

/// An invoice's lifecycle state.
public struct InvoiceStatus: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Editable and not visible to the customer.
    public static let draft: InvoiceStatus = "draft"
    /// Sent and payable.
    public static let open: InvoiceStatus = "open"
    /// Paid through checkout.
    public static let paid: InvoiceStatus = "paid"
    /// Cancelled; can no longer be paid.
    public static let void: InvoiceStatus = "void"
}

/// A deposit address's state.
public struct DepositAddressStatus: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let active: DepositAddressStatus = "active"
    public static let disabled: DepositAddressStatus = "disabled"
}

/// A subscription's state.
public struct SubscriptionStatus: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let active: SubscriptionStatus = "active"
    public static let pastDue: SubscriptionStatus = "past_due"
    public static let paused: SubscriptionStatus = "paused"
    public static let canceled: SubscriptionStatus = "canceled"
}

/// The billing period unit of a subscription.
public struct SubscriptionInterval: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let day: SubscriptionInterval = "day"
    public static let week: SubscriptionInterval = "week"
    public static let month: SubscriptionInterval = "month"
    public static let year: SubscriptionInterval = "year"
}

/// A limit order's state. Filled, cancelled, expired and failed are final.
public struct LimitOrderStatus: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let built: LimitOrderStatus = "built"
    public static let open: LimitOrderStatus = "open"
    public static let filled: LimitOrderStatus = "filled"
    public static let cancelled: LimitOrderStatus = "cancelled"
    public static let expired: LimitOrderStatus = "expired"
    public static let failed: LimitOrderStatus = "failed"

    public var isFinal: Bool {
        self == .filled || self == .cancelled || self == .expired || self == .failed
    }
}

/// Outcomes for `simulateLimitOrder` (test mode only).
public struct LimitOrderSimulation: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Fills the rest of the order.
    public static let fill: LimitOrderSimulation = "fill"
    /// Fills half of the rest.
    public static let partialFill: LimitOrderSimulation = "partial_fill"
    /// Expires the order.
    public static let expire: LimitOrderSimulation = "expire"
}

/// A refund's lifecycle state.
public struct RefundStatus: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pending: RefundStatus = "pending"
    public static let submitted: RefundStatus = "submitted"
    public static let completed: RefundStatus = "completed"
    public static let failed: RefundStatus = "failed"
}

/// Where a refund is delivered (`CreateRefundParams.to`).
public struct RefundDestinationKind: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Back in the payer's original chain and token (default).
    public static let original: RefundDestinationKind = "original"
    /// The settlement token to the payer's address on the settlement chain.
    public static let settlement: RefundDestinationKind = "settlement"
}

/// The type of a webhook event. Samples from the dashboard's "Send test" button have type "webhook.test".
public struct WebhookEventType: LayerHopStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let orderSubmitted: WebhookEventType = "order.submitted"
    public static let orderFilled: WebhookEventType = "order.filled"
    public static let orderRefunded: WebhookEventType = "order.refunded"
    public static let orderFailed: WebhookEventType = "order.failed"
    public static let checkoutSessionProcessing: WebhookEventType = "checkout.session.processing"
    public static let checkoutSessionCompleted: WebhookEventType = "checkout.session.completed"
    public static let checkoutSessionPaymentFailed: WebhookEventType = "checkout.session.payment_failed"
    public static let checkoutSessionExpired: WebhookEventType = "checkout.session.expired"
    public static let checkoutSessionRefunded: WebhookEventType = "checkout.session.refunded"
    public static let invoiceSent: WebhookEventType = "invoice.sent"
    public static let invoicePaid: WebhookEventType = "invoice.paid"
    public static let subscriptionCreated: WebhookEventType = "subscription.created"
    public static let subscriptionRenewed: WebhookEventType = "subscription.renewed"
    public static let subscriptionPastDue: WebhookEventType = "subscription.past_due"
    public static let subscriptionCanceled: WebhookEventType = "subscription.canceled"
    public static let limitOrderOpened: WebhookEventType = "limit_order.opened"
    public static let limitOrderFilled: WebhookEventType = "limit_order.filled"
    public static let limitOrderCancelled: WebhookEventType = "limit_order.cancelled"
    public static let limitOrderExpired: WebhookEventType = "limit_order.expired"
    public static let limitOrderFailed: WebhookEventType = "limit_order.failed"
}
