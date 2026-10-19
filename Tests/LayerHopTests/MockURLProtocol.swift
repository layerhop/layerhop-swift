import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import LayerHop

/// One request the mock saw.
struct Recorded {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data

    /// The percent-encoded path, e.g. "/v1/orders/debridge/a%2Fb%20c".
    var rawPath: String { URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "" }
    /// The raw query string ("" when none).
    var query: String { URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? "" }
    var bodyString: String { String(decoding: body, as: UTF8.self) }
    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
    func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name.lowercased() }?.value
    }
}

/// A canned response.
struct MockResponse {
    var status: Int = 200
    var headers: [String: String] = ["content-type": "application/json", "x-request-id": "req-hdr"]
    /// Body chunks, delivered one after another.
    var chunks: [Data]
    /// Fail the request with this URLError instead of answering.
    var error: URLError? = nil

    init(status: Int = 200, _ body: String, headers: [String: String]? = nil) {
        self.status = status
        self.chunks = [Data(body.utf8)]
        if let headers { self.headers = headers }
    }

    init(status: Int = 200, chunks: [String], headers: [String: String]) {
        self.status = status
        self.chunks = chunks.map { Data($0.utf8) }
        self.headers = headers
    }

    init(error: URLError) {
        self.chunks = []
        self.error = error
    }
}

final class MockState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: ((Recorded) -> MockResponse)?
    private var _requests: [Recorded] = []

    func set(_ h: @escaping (Recorded) -> MockResponse) {
        lock.lock()
        handler = h
        _requests = []
        lock.unlock()
    }

    func respond(to r: Recorded) -> MockResponse {
        lock.lock()
        _requests.append(r)
        let h = handler
        lock.unlock()
        return h?(r) ?? MockResponse(status: 500, "{}")
    }

    var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }
}

final class MockURLProtocol: URLProtocol {
    static let state = MockState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
            stream.close()
        }
        let rec = Recorded(
            method: request.httpMethod ?? "GET", url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:], body: body)
        let resp = Self.state.respond(to: rec)
        if let err = resp.error {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let http = HTTPURLResponse(url: request.url!, statusCode: resp.status, httpVersion: "HTTP/1.1", headerFields: resp.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        for chunk in resp.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Base class: a client wired to the mock with base URL https://api.test/ and API key k1.
class MockTestCase: XCTestCase {
    var client: LayerHopClient!

    override func setUp() {
        super.setUp()
        client = makeClient()
        MockURLProtocol.state.set { _ in MockResponse(status: 500, "{}") }
    }

    func makeClient(_ options: LayerHopClient.Options = .init(baseURL: "https://api.test/", apiKey: "k1")) -> LayerHopClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return LayerHopClient(options: options, session: URLSession(configuration: config))
    }

    /// Every request answers with `body`.
    func respond(status: Int = 200, _ body: String) {
        MockURLProtocol.state.set { _ in MockResponse(status: status, body) }
    }

    func respond(_ handler: @escaping (Recorded) -> MockResponse) {
        MockURLProtocol.state.set(handler)
    }

    var last: Recorded {
        guard let r = MockURLProtocol.state.requests.last else {
            XCTFail("no request recorded")
            return Recorded(method: "", url: URL(string: "https://none")!, headers: [:], body: Data())
        }
        return r
    }

    var requestCount: Int { MockURLProtocol.state.requests.count }

    /// Asserts that `body` throws a LayerHopError and returns it.
    func expectLayerHopError<T>(_ body: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async -> LayerHopError? {
        do {
            _ = try await body()
            XCTFail("expected an error", file: file, line: line)
            return nil
        } catch let e as LayerHopError {
            return e
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
            return nil
        }
    }
}
