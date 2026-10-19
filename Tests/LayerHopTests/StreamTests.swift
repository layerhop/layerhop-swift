import Foundation
import XCTest
@testable import LayerHop

let eventJSON = #"{"id":"evt_1","type":"order.filled","livemode":false,"sample":true,"createdAt":"2026-10-18T10:00:00.000Z","data":{"order":{"quoteId":"q_1","status":"filled"}}}"#

let sseHeaders = ["content-type": "text/event-stream"]

final class StreamTests: MockTestCase {
    // Comments, a ready frame, \r\n, a frame split across writes and a multi-line data field.
    let orderChunks = [
        ": connected\r\n\r\nevent: ready\r\ndata: {}\r\n\r\n",
        "event: order\r\ndata: {\"quoteId\":\"q_1\",\"status\":\"sub",
        "mitted\",\"provider\":\"relay\"}\r\n\r\n: ping\r\n\r",
        "\nevent: order\ndata: {\"quoteId\":\"q_1\",\ndata: \"status\":\"filled\",\"dstTxHash\":\"0xdef\"}\n\n",
        "event: other\ndata: {\"ignored\":true}\n\n",
    ]

    func testStreamOrder() async throws {
        respond { _ in MockResponse(chunks: self.orderChunks, headers: sseHeaders) }
        var got: [Order] = []
        for try await o in client.streamOrder(quoteId: "q/1") { got.append(o) }
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0].status, "submitted")
        XCTAssertEqual(got[0].provider, "relay")
        XCTAssertEqual(got[1].status, "filled")
        XCTAssertEqual(got[1].dstTxHash, "0xdef")
        XCTAssertEqual(last.method, "GET")
        XCTAssertEqual(last.rawPath, "/v1/orders/q%2F1/events")
        XCTAssertEqual(last.header("accept"), "text/event-stream")
        XCTAssertEqual(last.header("x-api-key"), "k1")
        XCTAssertEqual(last.header("user-agent"), "layerhop-swift/0.6.0")
    }

    func testStreamCheckoutSession() async throws {
        let paid = patch(sessionJSON, #""status":"processing""#, #""status":"paid""#)
        respond { _ in
            MockResponse(chunks: ["event: ready\ndata: {}\n\n", "event: session\ndata: \(sessionJSON)\n\n", "event: session\ndata: \(paid)\n\n"], headers: sseHeaders)
        }
        var statuses: [CheckoutStatus] = []
        for try await s in client.streamCheckoutSession(id: "cs_1") {
            statuses.append(s.status)
            XCTAssertEqual(s.settlement.decimals, 6)
        }
        XCTAssertEqual(statuses, [.processing, .paid])
        XCTAssertEqual(last.rawPath, "/v1/checkout/sessions/cs_1/events")
    }

    func testStreamWebhookEvents() async throws {
        let second = #"{"id":"evt_2","type":"checkout.session.completed","livemode":false,"createdAt":"c","data":{"session":\#(sessionJSON)}}"#
        respond { _ in
            MockResponse(chunks: [": hi\n\nevent: ready\ndata: {}\n\n", "event: event\ndata: \(eventJSON)\n\n", "event: event\r\ndata: \(second)\r\n\r\n"], headers: sseHeaders)
        }
        var got: [WebhookEvent] = []
        for try await e in client.streamWebhookEvents() { got.append(e) }
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(last.rawPath, "/v1/webhooks/stream")
        XCTAssertEqual(last.header("x-api-key"), "k1")
        let e = got[0]
        XCTAssertEqual(e.id, "evt_1")
        XCTAssertEqual(e.type, .orderFilled)
        XCTAssertFalse(e.livemode)
        XCTAssertEqual(e.sample, true)
        XCTAssertEqual(e.data.order?.status, "filled")
        XCTAssertNil(e.data.session)
        XCTAssertEqual(e.raw.map { String(decoding: $0, as: UTF8.self) }, eventJSON)
        XCTAssertEqual(got[1].data.session?.status, .processing)
    }

    func testStreamBreakEnds() async throws {
        var chunks = ["event: order\ndata: {\"status\":\"pending\"}\n\n"]
        for _ in 0..<50 { chunks.append(": ping\n\n") }
        respond { _ in MockResponse(chunks: chunks, headers: sseHeaders) }
        var n = 0
        for try await o in client.streamOrder(quoteId: "q_1") {
            XCTAssertEqual(o.status, "pending")
            n += 1
            break
        }
        XCTAssertEqual(n, 1)
    }

    func testStreamErrors() async throws {
        respond(status: 404, #"{"error":{"code":"ORDER_NOT_FOUND","message":"No order","requestId":"r1"}}"#)
        do {
            for try await _ in client.streamOrder(quoteId: "q_x") { XCTFail("no value expected") }
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? LayerHopError, .api(code: "ORDER_NOT_FOUND", message: "No order", status: 404, requestId: "r1"))
        }
        XCTAssertEqual(last.header("accept"), "text/event-stream")

        respond(status: 401, #"{"error":{"code":"UNAUTHORIZED","message":"Missing key"}}"#)
        do {
            for try await _ in client.streamWebhookEvents() {}
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as? LayerHopError)?.status, 401)
            XCTAssertEqual((error as? LayerHopError)?.code, "UNAUTHORIZED")
        }

        respond { _ in MockResponse(chunks: ["event: order\ndata: {not json\n\n"], headers: sseHeaders) }
        do {
            for try await _ in client.streamOrder(quoteId: "q_1") {}
            XCTFail("expected error")
        } catch {
            guard case let .decoding(msg)? = error as? LayerHopError else { return XCTFail("\(error)") }
            XCTAssertTrue(msg.contains("decode order event"), msg)
        }
    }

    func testTriggerWebhookEvent() async throws {
        respond(status: 202, #"{"eventId":"evt_1","deliveries":2,"payload":\#(eventJSON)}"#)
        let r = try await client.triggerWebhookEvent(type: .orderFilled)
        XCTAssertEqual(last.method, "POST")
        XCTAssertEqual(last.rawPath, "/v1/webhooks/trigger")
        XCTAssertEqual(last.bodyString, #"{"type":"order.filled"}"#)
        XCTAssertEqual(last.header("x-api-key"), "k1")
        XCTAssertEqual(r.eventId, "evt_1")
        XCTAssertEqual(r.deliveries, 2)
        XCTAssertEqual(r.payload.type, .orderFilled)
        XCTAssertEqual(r.payload.sample, true)

        respond(status: 403, #"{"error":{"code":"FORBIDDEN","message":"Use a test key","requestId":"r3"}}"#)
        let e = await expectLayerHopError { try await self.client.triggerWebhookEvent(type: .orderFilled) }
        XCTAssertEqual(e, .api(code: "FORBIDDEN", message: "Use a test key", status: 403, requestId: "r3"))
    }

    func testSSEParserChunking() {
        var p = SSEParser()
        let all = orderChunks.joined()
        // Byte-at-a-time feeding produces the same frames as one feed.
        var frames: [SSEParser.Frame] = []
        for b in Array(all.utf8) { frames += p.feed([b]) }
        var p2 = SSEParser()
        XCTAssertEqual(frames, p2.feed(Array(all.utf8)))
        XCTAssertEqual(frames.map(\.event), ["ready", "order", "order", "other"])
        XCTAssertEqual(frames[2].data, "{\"quoteId\":\"q_1\",\n\"status\":\"filled\",\"dstTxHash\":\"0xdef\"}")
        // A trailing frame without a blank line is not emitted.
        var p3 = SSEParser()
        XCTAssertEqual(p3.feed(Array("event: order\ndata: {}\n".utf8)), [])
    }
}
