import Foundation

struct SupportTicketResponseDTO: Decodable {
    let ticketNumber: String
    let category: String
    let subject: String
    let status: String
    let lastMessage: String?
    let lastMessageAt: String?
    let deviceModel: String?
    let osVersion: String?
    let appVersion: String?
    let networkType: String?
    let diagnosticsConsent: Bool?
    let createdAt: String?
    let resolvedAt: String?
    let messages: [SupportMessageResponseDTO]?
}

struct SupportMessageResponseDTO: Decodable {
    let id: Int64
    let senderType: String
    let senderName: String?
    let message: String
    let createdAt: String?
}

struct CreateSupportTicketRequestDTO: Encodable {
    let category: String
    let subject: String
    let message: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let networkType: String?
    let diagnosticsConsent: Bool
}

struct SendSupportMessageRequestDTO: Encodable {
    let message: String
}
