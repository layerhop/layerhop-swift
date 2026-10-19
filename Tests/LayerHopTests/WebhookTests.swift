import Foundation
import XCTest
@testable import LayerHop

final class WebhookTests: XCTestCase {
    let secret = "whsec_test"
    let body = Data(#"{"id":"evt_1","type":"order.filled","data":{}}"#.utf8)
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func check(
        _ name: String, secret: String? = nil, body: Data? = nil, header: String, now: Date? = nil,
        tolerance: TimeInterval = 0, want: WebhookSignatureError?, line: UInt = #line
    ) {
        do {
            try Webhook.verifySignature(
                secret: secret ?? self.secret, body: body ?? self.body, header: header, tolerance: tolerance,
                now: now ?? self.now)
            XCTAssertNil(want, "\(name): got success want \(String(describing: want))", line: line)
        } catch let e as WebhookSignatureError {
            XCTAssertEqual(e, want, "\(name)", line: line)
        } catch {
            XCTFail("\(name): unexpected \(error)", line: line)
        }
    }

    // Same cases as the Go SDK's TestVerifyWebhookSignature.
    func testVerifyWebhookSignature() {
        let hdr = Webhook.sign(secret: secret, body: body, timestamp: now)
        XCTAssertEqual(hdr.count, "t=1760000000,v1=".count + 64, hdr)
        let sig = String(hdr.dropFirst(16))
        let sigTail = String(hdr.dropFirst(18))

        check("valid", header: hdr, want: nil)
        check("valid within tolerance", header: hdr, now: now.addingTimeInterval(299), want: nil)
        check("valid with rotated extra v1", header: "t=1760000000,v1=00\(sigTail),v1=\(sig)", want: nil)
        check("spaces tolerated", header: "t=1760000000, v1=\(sig)", want: nil)
        check("too old", header: hdr, now: now.addingTimeInterval(301), want: .timestampOutsideTolerance)
        check("from the future", header: hdr, now: now.addingTimeInterval(-301), want: .timestampOutsideTolerance)
        check("wrong secret", secret: "other", header: hdr, want: .signatureMismatch)
        check("tampered body", body: Data(#"{"id":"evt_2"}"#.utf8), header: hdr, want: .signatureMismatch)
        check("missing t", header: "v1=\(sig)", want: .malformedHeader)
        check("missing v1", header: "t=1760000000", want: .malformedHeader)
        check("garbage", header: "nonsense", want: .malformedHeader)
        check("custom tolerance", header: hdr, now: now.addingTimeInterval(11), tolerance: 10, want: .timestampOutsideTolerance)
    }

    // echo -n '1700000000.{"a":1}' | openssl dgst -sha256 -hmac secret
    func testKnownVector() {
        let want = "t=1700000000,v1=49f24e537407743fa4a0242bb63b94b9a47ee99cbbe071ccd8a22550ae411686"
        XCTAssertEqual(Webhook.sign(secret: "secret", body: #"{"a":1}"#, timestamp: Date(timeIntervalSince1970: 1_700_000_000)), want)
        XCTAssertNoThrow(try Webhook.verifySignature(
            secret: "secret", body: #"{"a":1}"#, header: want, now: Date(timeIntervalSince1970: 1_700_000_000)))
        // Upper-case hex is accepted.
        XCTAssertNoThrow(try Webhook.verifySignature(
            secret: "secret", body: #"{"a":1}"#, header: want.uppercased().replacingOccurrences(of: "T=", with: "t=").replacingOccurrences(of: "V1=", with: "v1="),
            now: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    // Same cases as the Python SDK's test_webhooks.py.
    func testPythonVectors() throws {
        let body = #"{"id": "evt_1", "type": "order.filled", "createdAt": "2026-10-17T00:00:00Z", "data": {"order": {}}}"#
        let t: TimeInterval = 1_760_000_000
        let sig = Webhook.computeSignature(secret: secret, timestamp: "1760000000", body: Data(body.utf8))
        let h = "t=1760000000,v1=\(sig)"
        func valid(_ header: String?, body b: String? = nil, secret s: String? = nil, at: TimeInterval? = nil, tolerance: TimeInterval = 300) -> Bool {
            Webhook.isValidSignature(secret: s ?? secret, body: Data((b ?? body).utf8), header: header, tolerance: tolerance, now: Date(timeIntervalSince1970: at ?? t))
        }
        XCTAssertTrue(valid(h))
        XCTAssertTrue(valid(h, at: t + 299))
        XCTAssertFalse(valid(h, body: body + " "))
        XCTAssertFalse(valid(h, secret: "other"))
        XCTAssertFalse(valid(nil))
        XCTAssertFalse(valid(""))
        XCTAssertFalse(valid("t=1760000000"))
        XCTAssertFalse(valid("v1=\(sig)"))
        XCTAssertFalse(valid("t=abc,v1=\(sig)"))
        XCTAssertFalse(valid(h, at: t + 301))
        XCTAssertFalse(valid(h, at: t - 301))
        XCTAssertTrue(valid(h, at: t + 600, tolerance: 600))
        XCTAssertTrue(valid("t=1760000000, v1=deadbeef, v1=\(sig)"))

        let ev = try Webhook.constructEvent(secret: secret, body: Data(body.utf8), header: h, now: Date(timeIntervalSince1970: t))
        XCTAssertEqual(ev.type, .orderFilled)
        XCTAssertNotNil(ev.data.order)
        XCTAssertEqual(ev.raw, Data(body.utf8))
        XCTAssertThrowsError(try Webhook.constructEvent(
            secret: secret, body: Data(body.utf8), header: "t=1760000000,v1=00", now: Date(timeIntervalSince1970: t))
        ) { XCTAssertEqual($0 as? WebhookSignatureError, .signatureMismatch) }
    }

    func testPureSwiftSHA256MatchesKnownDigests() {
        XCTAssertEqual(hexEncode(PureSHA256.hash([])), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(hexEncode(PureSHA256.hash(Array("abc".utf8))), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            hexEncode(PureSHA256.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        // RFC 4231 test case 2.
        XCTAssertEqual(
            hexEncode(PureHMACSHA256.mac(key: Array("Jefe".utf8), message: Array("what do ya want for nothing?".utf8))),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        // RFC 4231 test case 6: a key longer than the block size.
        XCTAssertEqual(
            hexEncode(PureHMACSHA256.mac(key: [UInt8](repeating: 0xaa, count: 131), message: Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8))),
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
        // The webhook known vector, through the pure implementation, and agreement with the platform one.
        XCTAssertEqual(
            hexEncode(PureHMACSHA256.mac(key: Array("secret".utf8), message: Array(#"1700000000.{"a":1}"#.utf8))),
            "49f24e537407743fa4a0242bb63b94b9a47ee99cbbe071ccd8a22550ae411686")
        for n in [0, 1, 55, 56, 63, 64, 65, 200] {
            let msg = (0..<n).map { UInt8(truncatingIfNeeded: $0 &* 31) }
            XCTAssertEqual(PureHMACSHA256.mac(key: Array("k".utf8), message: msg), hmacSHA256(key: Array("k".utf8), message: msg), "n=\(n)")
        }
    }

    func testHexHelpers() {
        XCTAssertEqual(hexDecode("00ff10Ab"), [0x00, 0xff, 0x10, 0xab])
        XCTAssertNil(hexDecode("abc"))
        XCTAssertNil(hexDecode("zz"))
        XCTAssertTrue(constantTimeEqual([1, 2], [1, 2]))
        XCTAssertFalse(constantTimeEqual([1, 2], [1, 3]))
        XCTAssertFalse(constantTimeEqual([1], [1, 2]))
    }
}
