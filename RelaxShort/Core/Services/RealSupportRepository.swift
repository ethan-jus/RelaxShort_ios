import Foundation

final class RealSupportRepository: SupportRepositoryProtocol {
    private let client = APIClient.shared

    func fetchTickets() async throws -> [SupportTicket] {
        let dtos: [SupportTicketResponseDTO] = try await client.requestData(
            .supportTickets
        )
        return dtos.map(Self.mapTicket)
    }

    func fetchTicket(number: String) async throws -> SupportTicket {
        let dto: SupportTicketResponseDTO = try await client.requestData(
            .supportTicket(number: number)
        )
        return Self.mapTicket(dto)
    }

    func createTicket(_ ticket: CreateSupportTicket) async throws -> SupportTicket {
        let request = CreateSupportTicketRequestDTO(
            category: ticket.category.rawValue,
            subject: ticket.subject,
            message: ticket.message,
            deviceModel: ticket.deviceModel,
            osVersion: ticket.osVersion,
            appVersion: ticket.appVersion,
            networkType: ticket.networkType,
            diagnosticsConsent: ticket.diagnosticsConsent
        )
        let dto: SupportTicketResponseDTO = try await client.requestData(
            .createSupportTicket(request)
        )
        return Self.mapTicket(dto)
    }

    func sendMessage(ticketNumber: String, message: String) async throws -> SupportTicket {
        let dto: SupportTicketResponseDTO = try await client.requestData(
            .sendSupportMessage(
                ticketNumber: ticketNumber,
                request: SendSupportMessageRequestDTO(message: message)
            )
        )
        return Self.mapTicket(dto)
    }

    func resolveTicket(number: String) async throws -> SupportTicket {
        let dto: SupportTicketResponseDTO = try await client.requestData(
            .resolveSupportTicket(number: number)
        )
        return Self.mapTicket(dto)
    }

    private static func mapTicket(_ dto: SupportTicketResponseDTO) -> SupportTicket {
        SupportTicket(
            ticketNumber: dto.ticketNumber,
            category: SupportCategory(rawValue: dto.category) ?? .other,
            subject: dto.subject,
            status: SupportTicketStatus(rawValue: dto.status) ?? .waitingSupport,
            lastMessage: dto.lastMessage,
            lastMessageAt: dto.lastMessageAt.flatMap(BackendDateParser.parse),
            deviceModel: dto.deviceModel,
            osVersion: dto.osVersion,
            appVersion: dto.appVersion,
            networkType: dto.networkType,
            diagnosticsConsent: dto.diagnosticsConsent ?? false,
            createdAt: dto.createdAt.flatMap(BackendDateParser.parse),
            resolvedAt: dto.resolvedAt.flatMap(BackendDateParser.parse),
            messages: (dto.messages ?? []).map {
                SupportMessage(
                    id: $0.id,
                    senderType: $0.senderType,
                    senderName: $0.senderName,
                    message: $0.message,
                    createdAt: $0.createdAt.flatMap(BackendDateParser.parse)
                )
            }
        )
    }
}
