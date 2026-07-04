import Foundation
import Testing
@testable import RelaxShort

@Suite(.serialized)
struct AuthKeychainStoreTests {
    @Test
    func storesReadsAndDeletesRefreshToken() throws {
        let store = AuthKeychainStore(service: "com.relaxshort.tests.\(UUID().uuidString)")
        defer { try? store.deleteRefreshToken() }

        try store.saveRefreshToken("refresh-secret")
        #expect(try store.readRefreshToken() == "refresh-secret")

        try store.deleteRefreshToken()
        #expect(try store.readRefreshToken() == nil)
    }
}
