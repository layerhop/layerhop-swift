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
    /// exact payloads your endpoints receive, plus events resent later (`GET /v1/webhooks/stream`).
    /// Needs an API key. `since` (ISO 8601, at most an hour back) first replays the events you
    /// missed, e.g. after a reconnect. The server closes the stream after at most 30 minutes;
    /// reconnect to continue.
    public func streamWebhookEvents(since: String? = nil) -> AsyncThrowingStream<WebhookEvent, Error> {
        var q: [(String, String)] = []
        q.add("since", since)
        return streamSSE("/webhooks/stream", query: q, event: "event") { (ev: inout WebhookEvent, data: Data) in
            ev.raw = data
        }
    }

    /// Live quotes (`GET /v1/quote/stream`, Server-Sent Events): yields a fresh ranked quote set at
    /// once and then whenever the best route or any amount changes (and before the shown quote
    /// expires). The API re-quotes every `intervalMs` (default 10000, at least 5000); each refresh
    /// counts as one request against your rate limit. Ends after the stream's lifetime (5 minutes);
    /// a failed refresh ends it with `.api` (e.g. NO_ROUTE, RATE_LIMITED, ADDRESS_SANCTIONED).
    /// Stopping iteration closes the connection. Every `quoteId` is a normal quote for `buildTx`.
    ///
    /// ```swift
    /// for try await update in client.streamQuotes(params) { print(update.seq, update.best.dstAmount) }
    /// ```
    public func streamQuotes(_ p: QuoteParams, intervalMs: Int? = nil) -> AsyncThrowingStream<QuoteStreamUpdate, Error> {
        var q = quoteQuery(p)
        q.add("intervalMs", intervalMs)
        return streamSSE("/quote/stream", query: q, event: "quote", control: true)
    }

    /// Live exact-output quotes: as `streamQuotes(_:intervalMs:)` with `dstAmount`.
    public func streamQuotes(_ p: ExactOutputQuoteParams, intervalMs: Int? = nil)
        -> AsyncThrowingStream<QuoteStreamUpdate, Error>
    {
        var q = quoteQuery(p)
        q.add("intervalMs", intervalMs)
        return streamSSE("/quote/stream", query: q, event: "quote", control: true)
    }

    /// Reads a Server-Sent Events stream, yielding the decoded data of `event` frames. With
    /// `control`, an `error` frame (`{status, error: {code, ...}}`) ends the stream with `.api` and
    /// an `end` frame ends it normally.
    func streamSSE<T: Decodable & Sendable>(
        _ path: String, query: [(String, String)] = [], event: String, control: Bool = false,
        adjust: (@Sendable (inout T, Data) -> Void)? = nil
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = try self.makeRequest("GET", path, query: query, accept: "text/event-stream")
                    // Streams are long-lived: only an idle connection (no pings) should time out.
                    req.timeoutInterval = 300
                    var parser = SSEParser()
                    // Returns false once the stream should stop (an `end` frame).
                    let emit: (SSEParser.Frame) throws -> Bool = { frame in
                        if control {
                            if frame.event == "end" { return false }
                            if frame.event == "error" { throw decodeStreamError(Data(frame.data.utf8)) }
                        }
                        guard frame.event == event else { return true }
                        let data = Data(frame.data.utf8)
                        do {
                            var v = try JSONDecoder().decode(T.self, from: data)
                            adjust?(&v, data)
                            continuation.yield(v)
                        } catch {
                            throw LayerHopError.decoding("decode \(event) event: \(error)")
                        }
                        return true
                    }
                    #if canImport(FoundationNetworking)
                    // swift-corelibs-foundation has no URLSession.bytes: read the whole body.
                    let (data, res) = try await self.transport(req)
                    guard (200...299).contains(res.statusCode) else {
                        throw decodeAPIError(
                            status: res.statusCode,
                            headerRequestId: res.value(forHTTPHeaderField: "x-request-id"), body: data)
                    }
                    for frame in parser.feed(data) {
                        if try !emit(frame) { break }
                    }
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
                        reading: for try await b in bytes {
                            chunk.append(b)
                            if b == 0x0A {
                                for frame in parser.feed(chunk) {
                                    if try !emit(frame) { break reading }
                                }
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

/// The `data` of an `error` frame on a stream: `{"status": 404, "error": {"code": ..., ...}}`.
func decodeStreamError(_ data: Data) -> LayerHopError {
    struct Frame: Decodable { let status: Int? }
    let status = (try? JSONDecoder().decode(Frame.self, from: data))?.status ?? 500
    return decodeAPIError(status: status, headerRequestId: nil, body: data)
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
