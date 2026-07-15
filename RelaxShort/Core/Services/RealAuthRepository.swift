import Foundation

protocol RealAuthRepositoryProtocol {
    func createAnonymous(deviceID: String, idempotencyKey: UUID) async throws -> AuthSession
    func refresh(_ refreshToken: String) async throws -> AuthSession
    func signInWithGoogle(
        idToken: String,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession
    func signInWithFacebook(
        authenticationToken: String,
        nonce: String,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession
    func signInWithApple(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String,
        displayName: String?,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession
    func logout(_ refreshToken: String) async throws
}

/// 认证接口使用独立请求路径，避免 401 自动刷新与 refresh 接口形成递归。
final class RealAuthRepository: RealAuthRepositoryProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        self.session = session ?? URLSession(
            configuration: APIClient.makeSessionConfiguration()
        )
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func createAnonymous(deviceID: String, idempotencyKey: UUID) async throws -> AuthSession {
        try await requestSession(
            path: "/api/v2/auth/anonymous",
            body: [
                "device_id": deviceID,
                "idempotency_key": idempotencyKey.uuidString.lowercased()
            ]
        )
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        try await requestSession(
            path: "/api/v2/auth/refresh",
            body: ["refresh_token": refreshToken]
        )
    }

    func signInWithGoogle(
        idToken: String,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession {
        try await requestSession(
            path: "/api/v2/auth/oauth/google",
            body: [
                "id_token": idToken,
                "merge_request_id": mergeRequestID.uuidString.lowercased(),
                "device_id": deviceID
            ],
            bearerToken: anonymousAccessToken
        )
    }

    func signInWithFacebook(
        authenticationToken: String,
        nonce: String,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession {
        try await requestSession(
            path: "/api/v2/auth/oauth/facebook",
            body: [
                "authentication_token": authenticationToken,
                "nonce": nonce,
                "merge_request_id": mergeRequestID.uuidString.lowercased(),
                "device_id": deviceID
            ],
            bearerToken: anonymousAccessToken
        )
    }

    func signInWithApple(
        identityToken: String,
        authorizationCode: String,
        rawNonce: String,
        displayName: String?,
        anonymousAccessToken: String,
        deviceID: String,
        mergeRequestID: UUID
    ) async throws -> AuthSession {
        var body: [String: String] = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode,
            "raw_nonce": rawNonce,
            "merge_request_id": mergeRequestID.uuidString.lowercased(),
            "device_id": deviceID
        ]
        if let displayName, !displayName.isEmpty {
            body["display_name"] = displayName
        }
        return try await requestSession(
            path: "/api/v2/auth/oauth/apple",
            body: body,
            bearerToken: anonymousAccessToken
        )
    }

    func logout(_ refreshToken: String) async throws {
        let _: Bool = try await requestData(
            path: "/api/v2/auth/logout",
            body: ["refresh_token": refreshToken]
        )
    }

    private func requestSession(
        path: String,
        body: [String: String],
        bearerToken: String? = nil
    ) async throws -> AuthSession {
        let dto: AuthSessionResponseDTO = try await requestData(
            path: path,
            body: body,
            bearerToken: bearerToken
        )
        return try dto.toDomain()
    }

    private func requestData<T: Decodable>(
        path: String,
        body: [String: String],
        bearerToken: String? = nil
    ) async throws -> T {
        guard let url = URL(string: APIConfig.baseURL + path) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        request.setValue(InstallIdentityProvider.shared.installID(), forHTTPHeaderField: "X-Device-Id")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.from(error)
        }
        if let error = APIClient.errorForHTTPResponse(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            data: data
        ) {
            throw error
        }
        let envelope = try decoder.decode(APIResponseEnvelope<T>.self, from: data)
        if let detail = envelope.error {
            throw APIError(code: detail.code, message: detail.message ?? "请求失败")
        }
        guard let value = envelope.data else { throw NetworkError.invalidResponse }
        return value
    }
}
