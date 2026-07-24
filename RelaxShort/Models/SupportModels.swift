import Foundation

enum SupportCategory: String, CaseIterable, Identifiable {
    case playbackDownload = "playback_download"
    case paymentCoins = "payment_coins"
    case accountLogin = "account_login"
    case contentSubtitle = "content_subtitle"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playbackDownload: return "support.category.playback".localized
        case .paymentCoins: return "support.category.payment".localized
        case .accountLogin: return "support.category.account".localized
        case .contentSubtitle: return "support.category.content".localized
        case .other: return "support.category.other".localized
        }
    }

    var subtitle: String {
        switch self {
        case .playbackDownload: return "support.category.playback.subtitle".localized
        case .paymentCoins: return "support.category.payment.subtitle".localized
        case .accountLogin: return "support.category.account.subtitle".localized
        case .contentSubtitle: return "support.category.content.subtitle".localized
        case .other: return "support.category.other.subtitle".localized
        }
    }

    var icon: String {
        switch self {
        case .playbackDownload: return "play.rectangle"
        case .paymentCoins: return "creditcard"
        case .accountLogin: return "person"
        case .contentSubtitle: return "text.bubble"
        case .other: return "ellipsis.bubble"
        }
    }
}

enum SupportTicketStatus: String {
    case waitingSupport = "waiting_support"
    case replied
    case waitingUser = "waiting_user"
    case resolved

    var title: String {
        switch self {
        case .waitingSupport: return "support.status.waiting_support".localized
        case .replied: return "support.status.replied".localized
        case .waitingUser: return "support.status.waiting_user".localized
        case .resolved: return "support.status.resolved".localized
        }
    }
}

struct SupportMessage: Identifiable {
    let id: Int64
    let senderType: String
    let senderName: String?
    let message: String
    let createdAt: Date?

    var isCurrentUser: Bool { senderType == "user" }
}

struct SupportTicket: Identifiable, Hashable {
    let ticketNumber: String
    let category: SupportCategory
    let subject: String
    let status: SupportTicketStatus
    let lastMessage: String?
    let lastMessageAt: Date?
    let deviceModel: String?
    let osVersion: String?
    let appVersion: String?
    let networkType: String?
    let diagnosticsConsent: Bool
    let createdAt: Date?
    let resolvedAt: Date?
    let messages: [SupportMessage]

    var id: String { ticketNumber }

    static func == (lhs: SupportTicket, rhs: SupportTicket) -> Bool {
        lhs.ticketNumber == rhs.ticketNumber
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ticketNumber)
    }
}

struct CreateSupportTicket {
    let category: SupportCategory
    let subject: String
    let message: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let networkType: String?
    let diagnosticsConsent: Bool
}
