import SwiftUI
import UIKit

private enum SupportDesign {
    static let red = Color(hex: "#DA1D20")
}

struct SupportCenterView: View {
    @StateObject private var viewModel: SupportCenterViewModel
    @State private var searchText = ""
    @State private var showNewTicket = false
    @State private var newTicketCategory: SupportCategory?
    @State private var selectedTicket: SupportTicket?

    init(repository: SupportRepositoryProtocol = RealSupportRepository()) {
        _viewModel = StateObject(
            wrappedValue: SupportCenterViewModel(repository: repository)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if !searchText.isEmpty {
                    faqResults
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                } else {
                    categoryGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    Button {
                        newTicketCategory = nil
                        showNewTicket = true
                    } label: {
                        Label(
                            "support.new_ticket".localized,
                            systemImage: "plus.circle"
                        )
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SupportDesign.red)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)

                    ticketSection
                        .padding(.top, 24)
                }
            }
            .padding(.bottom, 28)
        }
        .background(DB.black.ignoresSafeArea())
        .compactSecondaryNavigation(title: "support.title".localized)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showNewTicket) {
            NewSupportTicketView(
                repository: viewModel.repository,
                initialCategory: newTicketCategory
            ) { ticket in
                viewModel.prepend(ticket)
                selectedTicket = ticket
            }
        }
        .navigationDestination(item: $selectedTicket) { ticket in
            SupportTicketConversationView(
                ticket: ticket,
                repository: viewModel.repository
            )
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DB.mutedText)
            TextField("support.search_placeholder".localized, text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(SupportDesign.red)
            if searchText.isEmpty {
                Menu {
                    ForEach(SupportFAQ.all) { faq in
                        Button(faq.question) {
                            searchText = faq.question
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DB.mutedText)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("support.common_questions".localized)
            }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DB.mutedText)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(DB.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var categoryGrid: some View {
        HStack(spacing: 0) {
            ForEach(
                [
                    SupportCategory.playbackDownload,
                    .paymentCoins,
                    .accountLogin
                ],
                id: \.self
            ) { category in
                Button {
                    newTicketCategory = category
                    showNewTicket = true
                } label: {
                    VStack(spacing: 8) {
                        SupportCategoryIcon(category: category)
                        Text(category.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                }
                .buttonStyle(.plain)

                if category != .accountLogin {
                    Divider().overlay(DB.divider)
                }
            }
        }
        .background(DB.panel.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(DB.divider, lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private var ticketSection: some View {
        HStack {
            Text("support.my_tickets".localized)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            Text("support.response_time".localized)
                .font(.system(size: 11))
                .foregroundColor(DB.mutedText)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)

        if viewModel.isLoading && viewModel.tickets.isEmpty {
            ProgressView()
                .tint(DT.brandGold)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
        } else if let error = viewModel.errorMessage,
                  viewModel.tickets.isEmpty {
            VStack(spacing: 10) {
                Text("support.load_failed".localized)
                    .font(.system(size: 14))
                    .foregroundColor(DB.mutedText)
                Button("wallet.retry".localized) {
                    Task { await viewModel.load() }
                }
                .foregroundColor(SupportDesign.red)
                .accessibilityHint(error)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
        } else if viewModel.tickets.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundColor(DB.mutedText)
                Text("support.no_tickets".localized)
                    .font(.system(size: 14))
                    .foregroundColor(DB.mutedText)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 34)
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.tickets) { ticket in
                    Button {
                        selectedTicket = ticket
                    } label: {
                        SupportTicketRow(ticket: ticket)
                    }
                    .buttonStyle(.plain)

                    if ticket.id != viewModel.tickets.last?.id {
                        Divider()
                            .overlay(DB.divider)
                            .padding(.leading, 20)
                    }
                }
            }
            .background(DB.panel.opacity(0.24))
        }
    }

    private var faqResults: some View {
        VStack(spacing: 0) {
            ForEach(filteredFAQs) { faq in
                DisclosureGroup {
                    Text(faq.answer)
                        .font(.system(size: 13))
                        .foregroundColor(DB.mutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                } label: {
                    Text(faq.question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 13)
                }
                .tint(DB.mutedText)

                if faq.id != filteredFAQs.last?.id {
                    Divider().overlay(DB.divider)
                }
            }

            if filteredFAQs.isEmpty {
                Button {
                    newTicketCategory = nil
                    showNewTicket = true
                } label: {
                    Text("support.no_faq_create_ticket".localized)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SupportDesign.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
        }
    }

    private var filteredFAQs: [SupportFAQ] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return SupportFAQ.all.filter {
            $0.question.localizedCaseInsensitiveContains(query)
                || $0.answer.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct SupportCategoryIcon: View {
    let category: SupportCategory

    @ViewBuilder
    var body: some View {
        if let assetName {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)
        } else {
            Image(systemName: category.icon)
                .font(.system(size: 27, weight: .regular))
                .foregroundColor(Color(hex: "#E6B84E"))
                .frame(width: 44, height: 44)
        }
    }

    private var assetName: String? {
        switch category {
        case .playbackDownload:
            "SupportPlaybackIcon"
        case .paymentCoins:
            "SupportCoinsIcon"
        case .accountLogin:
            "SupportAccountIcon"
        default:
            nil
        }
    }
}

private struct SupportTicketRow: View {
    let ticket: SupportTicket

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    statusChip
                    Text(ticket.subject)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Text("#\(ticket.ticketNumber)")
                    .font(.system(size: 11))
                    .foregroundColor(DB.mutedText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text(relativeDate(ticket.lastMessageAt))
                    .font(.system(size: 11))
                    .foregroundColor(DB.mutedText)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DB.mutedText)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 76)
        .contentShape(Rectangle())
    }

    private var statusChip: some View {
        Text(ticket.status.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 7)
            .frame(height: 23)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(statusColor.opacity(0.72), lineWidth: 0.8)
            }
    }

    private var statusColor: Color {
        switch ticket.status {
        case .waitingSupport: return SupportDesign.red
        case .replied, .waitingUser: return DT.brandGold
        case .resolved: return DT.success
        }
    }

    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLocalization.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct NewSupportTicketView: View {
    @Environment(\.dismiss) private var dismiss

    let repository: SupportRepositoryProtocol
    let onCreated: (SupportTicket) -> Void

    @State private var category: SupportCategory
    @State private var subject = ""
    @State private var message = ""
    @State private var diagnosticsConsent = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        repository: SupportRepositoryProtocol,
        initialCategory: SupportCategory?,
        onCreated: @escaping (SupportTicket) -> Void
    ) {
        self.repository = repository
        self.onCreated = onCreated
        _category = State(initialValue: initialCategory ?? .playbackDownload)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    fieldTitle("support.form.category".localized)
                    categoryPicker

                    fieldTitle("support.form.subject".localized)
                    TextField("support.form.subject_placeholder".localized, text: $subject)
                        .supportField()

                    fieldTitle("support.form.details".localized)
                    TextEditor(text: $message)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .frame(minHeight: 150)
                        .background(DB.panel.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(DB.divider, lineWidth: 0.8)
                        }

                    Toggle(
                        "support.form.diagnostics".localized,
                        isOn: $diagnosticsConsent
                    )
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .tint(SupportDesign.red)

                    Text("support.form.diagnostics_note".localized)
                        .font(.system(size: 11))
                        .foregroundColor(DB.mutedText)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(SupportDesign.red)
                    }

                    Button {
                        submit()
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("support.form.submit".localized)
                            }
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canSubmit ? SupportDesign.red : DB.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(DB.black.ignoresSafeArea())
            .navigationTitle("support.new_ticket".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DB.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var categoryPicker: some View {
        Menu {
            ForEach(SupportCategory.allCases) { item in
                Button(item.title) { category = item }
            }
        } label: {
            HStack {
                Label(category.title, systemImage: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DB.mutedText)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(DB.panel.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(DB.divider, lineWidth: 0.8)
            }
        }
    }

    private var canSubmit: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(DB.mutedText)
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let version = Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "1.0"
        let request = CreateSupportTicket(
            category: category,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceModel: UIDevice.current.model,
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            appVersion: version,
            networkType: nil,
            diagnosticsConsent: diagnosticsConsent
        )
        Task {
            do {
                let ticket = try await repository.createTicket(request)
                await MainActor.run {
                    onCreated(ticket)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

private struct SupportTicketConversationView: View {
    @StateObject private var viewModel: SupportConversationViewModel
    @State private var draft = ""
    @State private var showInfo = true

    init(ticket: SupportTicket, repository: SupportRepositoryProtocol) {
        _viewModel = StateObject(
            wrappedValue: SupportConversationViewModel(
                ticket: ticket,
                repository: repository
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ticketMeta
            Divider().overlay(DB.divider)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        infoPanel

                        ForEach(viewModel.ticket.messages) { message in
                            SupportMessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .onChange(of: viewModel.ticket.messages.count) {
                    guard let id = viewModel.ticket.messages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            composer
        }
        .background(DB.black.ignoresSafeArea())
        .compactSecondaryNavigation(title: viewModel.ticket.subject)
        .task { await viewModel.load() }
        .alert(
            viewModel.errorMessage ?? "",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("common.cancel".localized, role: .cancel) {}
        }
    }

    private var ticketMeta: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(viewModel.ticket.status.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(statusColor)
            Text("#\(viewModel.ticket.ticketNumber)")
                .font(.system(size: 11))
                .foregroundColor(DB.mutedText)
            Spacer()
            if viewModel.ticket.status != .resolved {
                Button("support.resolve".localized) {
                    Task { await viewModel.resolve() }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DB.mutedText)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 42)
    }

    private var infoPanel: some View {
        DisclosureGroup(isExpanded: $showInfo) {
            VStack(alignment: .leading, spacing: 7) {
                infoRow("support.info.device".localized, viewModel.ticket.deviceModel)
                infoRow("support.info.system".localized, viewModel.ticket.osVersion)
                infoRow("support.info.version".localized, viewModel.ticket.appVersion)
            }
            .padding(.top, 8)
        } label: {
            Label(
                "support.info.attached".localized,
                systemImage: "iphone"
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
        }
        .tint(DB.mutedText)
        .padding(12)
        .background(DB.panel.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func infoRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—")
        }
        .font(.system(size: 11))
        .foregroundColor(DB.mutedText)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("support.message_placeholder".localized, text: $draft, axis: .vertical)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .tint(SupportDesign.red)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(DB.panel)
                .clipShape(Capsule())

            Button {
                let text = draft
                draft = ""
                Task { await viewModel.send(text) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(SupportDesign.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(
                draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isSending
                    || viewModel.ticket.status == .resolved
            )
            .opacity(viewModel.ticket.status == .resolved ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DB.black)
        .overlay(alignment: .top) {
            Divider().overlay(DB.divider)
        }
    }

    private var statusColor: Color {
        switch viewModel.ticket.status {
        case .waitingSupport: return SupportDesign.red
        case .replied, .waitingUser: return DT.brandGold
        case .resolved: return DT.success
        }
    }
}

private struct SupportMessageBubble: View {
    let message: SupportMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isCurrentUser {
                Spacer(minLength: 52)
                messageContent
                avatar(title: "support.me".localized, isUser: true)
            } else {
                avatar(title: "R", isUser: false)
                messageContent
                Spacer(minLength: 52)
            }
        }
    }

    private var messageContent: some View {
        VStack(
            alignment: message.isCurrentUser ? .trailing : .leading,
            spacing: 5
        ) {
            HStack(spacing: 7) {
                Text(
                    message.isCurrentUser
                        ? "support.me".localized
                        : message.senderName ?? "support.agent".localized
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(message.isCurrentUser ? .white : SupportDesign.red)

                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundColor(DB.mutedText)
            }

            Text(message.message)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    message.isCurrentUser
                        ? DT.rewardBadgeBackground
                        : DB.panel.opacity(0.74)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            message.isCurrentUser
                                ? SupportDesign.red.opacity(0.76)
                                : DB.divider,
                            lineWidth: 0.8
                        )
                }
        }
        .frame(maxWidth: 274, alignment: message.isCurrentUser ? .trailing : .leading)
    }

    private func avatar(title: String, isUser: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(isUser ? .white : SupportDesign.red)
            .frame(width: 32, height: 32)
            .background(isUser ? SupportDesign.red : DB.panel)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(isUser ? SupportDesign.red : DB.divider, lineWidth: 0.8)
            }
    }

    private var timeText: String {
        guard let date = message.createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

@MainActor
private final class SupportCenterViewModel: ObservableObject {
    let repository: SupportRepositoryProtocol
    @Published private(set) var tickets: [SupportTicket] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    init(repository: SupportRepositoryProtocol) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tickets = try await repository.fetchTickets()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepend(_ ticket: SupportTicket) {
        tickets.removeAll { $0.id == ticket.id }
        tickets.insert(ticket, at: 0)
    }
}

@MainActor
private final class SupportConversationViewModel: ObservableObject {
    @Published var ticket: SupportTicket
    @Published var isSending = false
    @Published var errorMessage: String?

    private let repository: SupportRepositoryProtocol

    init(ticket: SupportTicket, repository: SupportRepositoryProtocol) {
        self.ticket = ticket
        self.repository = repository
    }

    func load() async {
        do {
            ticket = try await repository.fetchTicket(number: ticket.ticketNumber)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ rawMessage: String) async {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            ticket = try await repository.sendMessage(
                ticketNumber: ticket.ticketNumber,
                message: message
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolve() async {
        do {
            ticket = try await repository.resolveTicket(number: ticket.ticketNumber)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SupportFAQ: Identifiable {
    let id: String
    let question: String
    let answer: String

    static var all: [SupportFAQ] {
        [
            SupportFAQ(
                id: "playback",
                question: "support.faq.playback.q".localized,
                answer: "support.faq.playback.a".localized
            ),
            SupportFAQ(
                id: "coins",
                question: "support.faq.coins.q".localized,
                answer: "support.faq.coins.a".localized
            ),
            SupportFAQ(
                id: "vip",
                question: "support.faq.vip.q".localized,
                answer: "support.faq.vip.a".localized
            ),
            SupportFAQ(
                id: "login",
                question: "support.faq.login.q".localized,
                answer: "support.faq.login.a".localized
            )
        ]
    }
}

private extension View {
    func supportField() -> some View {
        self
            .font(.system(size: 15))
            .foregroundColor(.white)
            .tint(SupportDesign.red)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(DB.panel.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(DB.divider, lineWidth: 0.8)
            }
    }
}
