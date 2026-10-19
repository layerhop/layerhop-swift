import Foundation
import XCTest
import LayerHop

/// The README quickstart, end to end against the mock (wallet steps faked). Uses only the public API.
final class ExampleTests: MockTestCase {
    func testQuickstartFlow() async throws {
        respond { r in
            switch (r.method, r.url.path) {
            case ("GET", "/v1/quote"): return MockResponse(quoteJSON)
            case ("POST", "/v1/orders"):
                return MockResponse(#"{"tx":{"vm":"svm","serializedTx":"AQID","submitViaApi":true}}"#)
            case ("POST", "/v1/orders/submit"): return MockResponse(#"{"txHash":"5sig"}"#)
            case ("POST", "/v1/orders/q_1/submitted"): return MockResponse(#"{"quoteId":"q_1","status":"submitted"}"#)
            case ("GET", "/v1/orders/relay/5sig"): return MockResponse(#"{"provider":"relay","id":"5sig","state":"filled"}"#)
            default: return MockResponse(status: 404, #"{"error":{"code":"NOT_FOUND","message":"x"}}"#)
            }
        }
        let lh = client!
        let q = try await lh.quote(QuoteParams(
            srcChain: "base", srcToken: "USDC", amount: "100000000",
            dstChain: "solana", dstToken: "SOL",
            sender: "0xYourEvmAddress", recipient: "YourSolanaAddress"))
        let tx = try await lh.buildTx(quoteId: q.best.quoteId)
        let txHash: String
        switch tx {
        case .evm(let evm):
            txHash = evm.to
        case .svm(let svm):
            let signed = svm.serializedTx // a wallet would sign here
            txHash = svm.submitViaApi
                ? try await lh.submit(quoteId: q.best.quoteId, signedTransaction: signed)
                : "broadcast-by-wallet"
        }
        XCTAssertEqual(txHash, "5sig")
        _ = try await lh.reportSubmitted(quoteId: q.best.quoteId, txHash: txHash)
        var states: [OrderState] = []
        for try await st in lh.watch(provider: q.best.provider, id: txHash) { states.append(st.state) }
        XCTAssertEqual(states, [.filled])

        do {
            _ = try await lh.getInvoice(id: "nope")
            XCTFail("expected error")
        } catch let e as LayerHopError where e.code == "NOT_FOUND" {
            XCTAssertEqual(e.status, 404)
        }
    }
}
