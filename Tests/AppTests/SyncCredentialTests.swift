import XCTest
import Security
@testable import FlodoOpen

final class SyncCredentialTests: XCTestCase {
    func testPollingReusesCredentialAndNeverRequestsInteraction() throws {
        var calls: [Bool] = []
        let session = SyncCredentialSession { endpoint, interactive in
            calls.append(interactive)
            return "token-for-\(endpoint)"
        }
        for _ in 0..<10 { XCTAssertEqual(try session.token(endpoint: "server-a"), "token-for-server-a") }
        XCTAssertEqual(calls, [false])
        XCTAssertEqual(try session.token(endpoint: "server-b"), "token-for-server-b")
        XCTAssertEqual(calls, [false, false])
    }
    func testDeniedCredentialDoesNotRetryUntilExplicitConnect() throws {
        var calls: [Bool] = []
        let session = SyncCredentialSession { _, interactive in
            calls.append(interactive)
            if !interactive { throw SyncCredentialError(status: errSecInteractionNotAllowed) }
            return "authorized-token"
        }
        for _ in 0..<10 { XCTAssertThrowsError(try session.token(endpoint: "server")) }
        XCTAssertEqual(calls, [false])
        try session.authorize(endpoint: "server")
        XCTAssertEqual(try session.token(endpoint: "server"), "authorized-token")
        XCTAssertEqual(calls, [false, true])
    }
    func testCancelledConnectDoesNotCauseBackgroundPrompts() {
        var calls: [Bool] = []
        let session = SyncCredentialSession { _, interactive in
            calls.append(interactive)
            throw SyncCredentialError(status: errSecUserCanceled)
        }
        XCTAssertThrowsError(try session.authorize(endpoint: "server"))
        XCTAssertThrowsError(try session.token(endpoint: "server"))
        XCTAssertEqual(calls, [true])
        session.remember("replacement", endpoint: "server")
        XCTAssertEqual(try session.token(endpoint: "server"), "replacement")
    }
}
