import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension LayerHopClient {
    /// Streams an order's status (`GET /v1/orders/{quoteId}/events`, Server-Sent Events). Yields the
    /// order now and on every change, and ends when the order is final and the server closes the
    /// stream. An API error (such as ORDER_NOT_FOUND), a network error or cancellation ends the
    /// stream with that error. Stopping iteration closes the connection.
    ///
    /// ```swift
    /// for try await order in client.streamOrder(quoteId: quoteId) { print(order.status ?? "") }
    /// ```
    public func streamOrder(quoteId: String) -> AsyncThrowingStream<Order, Error> {
        streamSSE("/orders/\(escapeComponent(quoteId))/events", event: "order")
    }

    /// Streams a checkout session (`GET /v1/checkout/sessions/{id}/events`). Public. Yields the
    /// session now and on every change until it is paid, expired or needs_review.
    public func streamCheckoutSession(id: String) -> AsyncThrowingStream<CheckoutSession, Error> {
        streamSSE("/checkout/sessions/\(escapeComponent(id))/events", event: "session")
    }

    /// Streams your account's webhook events of the API key's mode as they are created, with the
    /// exact payloads your endpoints receive (`GET /v1/webhooks/stream`). Needs an API key. The
    /// server closes the stream after at most 30 minutes; reconnect to continue.
    public func streamWebhookEvents() -> AsyncThrowingStream<WebhookEvent, Error> {
        streamSSE("/webhooks/stream", event: "event") { (ev: inout WebhookEvent, data: Data) in
            ev.raw = data
        }
    }

    func streamSSE<T: Decodable & Sendable>(
        _ path: String, event: String, adjust: (@Sendable (inout T, Data) -> Void)? = nil
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try self.makeRequest("GET", path, accept: "text/event-stream")
                    // Streams are long-lived: only an idle connection (no pings) should time out.
                    req.timeoutInterval = 300
                    var parser = SSEParser()
                    let emit: (SSEParser.Frame) throws -> Void = { frame in
                        guard frame.event == event else { return }
                        let data = Data(frame.data.utf8)
                        do {
                            var v = try JSONDecoder().decode(T.self, from: data)
                            adjust?(&v, data)
                            continuation.yield(v)
                        } catch {
                            throw LayerHopError.decoding("decode \(event) event: \(error)")
                        }
                    }
                    #if canImport(FoundationNetworking)
                    // swift-corelibs-foundation has no URLSession.bytes: read the whole body.
                    let (data, res) = try await self.transport(req)
                    guard (200...299).contains(res.statusCode) else {
                        throw decodeAPIError(
                            status: res.statusCode,
                            headerRequestId: res.value(forHTTPHeaderField: "x-request-id"), body: data)
                    }
                    for frame in parser.feed(data) { try emit(frame) }
                    #else
                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do {
                        (bytes, response) = try await self.session.bytes(for: req)
                    } catch {
                        throw mapTransportError(error)
                    }
                    guard let res = response as? HTTPURLResponse else { throw LayerHopError.invalidResponse }
                    guard (200...299).contains(res.statusCode) else {
                        var body = Data()
                        do {
                            for try await b in bytes {
                                body.append(b)
                                if body.count >= 1 << 20 { break }
                            }
                        } catch {}
                        throw decodeAPIError(
                            status: res.statusCode,
                            headerRequestId: res.value(forHTTPHeaderField: "x-request-id"), body: body)
                    }
                    do {
                        var chunk = [UInt8]()
                        chunk.reserveCapacity(4096)
                        for try await b in bytes {
                            chunk.append(b)
                            if b == 0x0A {
                                for frame in parser.feed(chunk) { try emit(frame) }
                                chunk.removeAll(keepingCapacity: true)
                            }
                        }
                        // A partial trailing frame (no blank line) is dropped, as in the other SDKs.
                        _ = parser.feed(chunk)
                    } catch let e as LayerHopError {
                        throw e
                    } catch {
                        throw mapTransportError(error)
                    }
                    #endif
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? CancellationError() : error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// An incremental Server-Sent Events parser. Feed it bytes in any chunking; it returns the frames
/// completed by a blank line. Comments (":") and unknown fields are ignored; CRLF is accepted.
struct SSEParser {
    struct Frame: Equatable {
        var event: String
        var data: String
    }

    private var buffer = [UInt8]()
    private var name = "message"
    private var data: [String] = []

    mutating func feed<S: Sequence>(_ bytes: S) -> [Frame] where S.Element == UInt8 {
        var frames: [Frame] = []
        for b in bytes {
            if b == 0x0A {
                var lineBytes = buffer
                buffer.removeAll(keepingCapacity: true)
                if lineBytes.last == 0x0D { lineBytes.removeLast() }
                let line = String(decoding: lineBytes, as: UTF8.self)
                if let f = handle(line) { frames.append(f) }
            } else {
                buffer.append(b)
            }
        }
        return frames
    }

    private mutating func handle(_ line: String) -> Frame? {
        if line.isEmpty {
            defer {
                name = "message"
                data = []
            }
            return data.isEmpty ? nil : Frame(event: name, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix("event:") {
            name = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            var v = Substring(line.dropFirst("data:".count))
            if v.hasPrefix(" ") { v = v.dropFirst() }
            data.append(String(v))
        }
        return nil
    }
}
