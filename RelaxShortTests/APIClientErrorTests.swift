import Foundation
import Testing
@testable import RelaxShort

struct APIClientErrorTests {
    @Test
    func nonSuccessEnvelopePreservesBusinessCodeAndMessage() throws {
        let data = Data("""
        {"data":null,"error":{"code":"EPISODE_LOCKED","message":"该剧集需要登录"}}
        """.utf8)

        let error = try #require(APIClient.errorForHTTPResponse(statusCode: 403, data: data))
        let apiError = try #require(error as? APIError)

        #expect(apiError.code == "EPISODE_LOCKED")
        #expect(apiError.message == "该剧集需要登录")
    }
}
