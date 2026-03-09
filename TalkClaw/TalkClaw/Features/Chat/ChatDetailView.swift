import SwiftUI
import SharedModels
import MarkdownUI

struct ChatDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let session: SessionDTO

    @State private var messages: [MessageDTO] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var streamingText = ""
    @State private var errorMessage: String?
    @State private var isNearBottom = true
    @State private var pendingAttachments: [AttachmentItem] = []
    @State private var isUploading = false
    @State private var deltaBuffer = ""
    @State private var flushTask: Task<Void, Never>?
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var currentMatchIndex = 0

    private var isActive: Bool {
        appState.activeSessionIds.contains(session.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ZStack(alignment: .bottom) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                // Top inset so content starts below the floating header
                                Color.clear.frame(height: isSearching ? 100 : 56)

                                ForEach(messages) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                        .overlay(
                                            searchMatchIds.contains(message.id)
                                                ? RoundedRectangle(cornerRadius: Theme.Radius.md)
                                                    .strokeBorder(
                                                        currentMatchId == message.id
                                                            ? Theme.Colors.accent
                                                            : Theme.Colors.accent.opacity(0.4),
                                                        lineWidth: currentMatchId == message.id ? 2 : 1
                                                    )
                                                : nil
                                        )
                                }

                                if isActive && !streamingText.isEmpty {
                                    StreamingBubbleView(text: streamingText)
                                        .id("streaming-bubble")
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                } else if isActive {
                                    StreamingIndicator()
                                        .id("streaming")
                                        .transition(.opacity)
                                }

                                Color.clear.frame(height: 1).id("bottom-anchor")
                                    .onAppear { isNearBottom = true }
                                    .onDisappear { isNearBottom = false }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                        }
                        .onChange(of: messages.count) {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                        .onChange(of: streamingText) {
                            if isActive && isNearBottom {
                                proxy.scrollTo("streaming-bubble", anchor: .bottom)
                            }
                        }
                        .onChange(of: currentMatchIndex) {
                            if let id = currentMatchId {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                        .onChange(of: searchText) {
                            currentMatchIndex = 0
                        }

                        // Jump-to-bottom button
                        if !isNearBottom {
                            Button {
                                scrollToBottom(proxy: proxy, animated: true)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .frame(width: 36, height: 36)
                                    .interactiveGlass(in: Circle())
                            }
                            .padding(.bottom, Theme.Spacing.sm)
                            .transition(.scale.combined(with: .opacity))
                            .animation(Theme.Anim.spring, value: isNearBottom)
                        }
                    }
                }

                MessageComposer(text: $inputText, attachments: $pendingAttachments, isDisabled: isUploading) {
                    sendMessage()
                }
            }

            // Floating header: fade gradient + back button + status pill
            VStack(spacing: 0) {
                ChatHeaderOverlay(isActive: isActive, isSearching: isSearching, onSearch: { withAnimation(Theme.Anim.smooth) { isSearching.toggle(); if !isSearching { searchText = "" } } }) {
                    dismiss()
                }

                if isSearching {
                    ChatSearchBar(
                        text: $searchText,
                        matchCount: searchMatchIds.count,
                        currentIndex: currentMatchIndex,
                        onPrevious: { navigateMatch(direction: -1, proxy: nil) },
                        onNext: { navigateMatch(direction: 1, proxy: nil) },
                        onDismiss: { withAnimation(Theme.Anim.smooth) { isSearching = false; searchText = "" } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))

                    LinearGradient(
                        colors: [Theme.Colors.background, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 20)
                    .allowsHitTesting(false)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            appState.viewingSessionId = session.id
            appState.markSessionRead(session.id)
            appState.getConnectionManager()?.subscribe(to: session.id)
            await loadMessages()
        }
        .onDisappear {
            appState.viewingSessionId = nil
            appState.getConnectionManager()?.unsubscribe(from: session.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatDelta)) { notification in
            guard let delta = notification.userInfo?["delta"] as? WSMessage.ChatDeltaPayload,
                  delta.sessionId == session.id else { return }
            // Batch deltas to reduce re-renders and ensure \n\n arrives atomically
            deltaBuffer += delta.delta
            flushTask?.cancel()
            flushTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                streamingText += deltaBuffer
                deltaBuffer = ""
                if hapticsEnabled {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatComplete)) { notification in
            guard let message = notification.userInfo?["message"] as? MessageDTO,
                  message.sessionId == session.id else { return }
            // Flush any remaining buffer
            flushTask?.cancel()
            streamingText = ""
            deltaBuffer = ""
            messages.append(message)
            if hapticsEnabled {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
        .alert("Send Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var searchMatchIds: Set<UUID> {
        guard !searchText.isEmpty else { return [] }
        let lowered = searchText.lowercased()
        return Set(messages.filter { $0.searchableText.lowercased().contains(lowered) }.map(\.id))
    }

    private var currentMatchId: UUID? {
        let matches = messages.filter { searchMatchIds.contains($0.id) }
        guard !matches.isEmpty else { return nil }
        let idx = currentMatchIndex % matches.count
        return matches[idx].id
    }

    private func navigateMatch(direction: Int, proxy: ScrollViewProxy?) {
        let count = searchMatchIds.count
        guard count > 0 else { return }
        currentMatchIndex = (currentMatchIndex + direction + count) % count
    }

    private func loadMessages() async {
        isLoading = true

        // Load cached messages immediately
        if let cached = await appState.cacheManager?.loadCachedMessages(sessionId: session.id), !cached.isEmpty {
            messages = cached
            isLoading = false
        }

        // Then fetch from server (source of truth)
        guard let client = appState.getAPIClient() else {
            isLoading = false
            return
        }
        do {
            let response = try await client.getMessages(sessionId: session.id)
            messages = response.items
            await appState.cacheManager?.syncMessages(response.items, sessionId: session.id)
        } catch {
            print("Server unreachable, using cached messages: \(error)")
        }
        isLoading = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = false) {
        if animated {
            withAnimation {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentsToSend = pendingAttachments
        guard !text.isEmpty || !attachmentsToSend.isEmpty else { return }
        inputText = ""
        pendingAttachments = []

        // Batch all new messages into a single append to avoid multiple onChange triggers
        var newMessages: [MessageDTO] = []

        // If the agent is mid-stream, commit the partial streaming text as a message
        if isActive && !streamingText.isEmpty {
            newMessages.append(MessageDTO(
                id: UUID(),
                sessionId: session.id,
                role: .assistant,
                content: .text(streamingText)
            ))
            streamingText = ""
        }

        // Add optimistic messages for attachments
        for attachment in attachmentsToSend {
            if attachment.isImage {
                newMessages.append(MessageDTO(
                    id: UUID(),
                    sessionId: session.id,
                    role: .user,
                    content: .image(url: URL(string: "placeholder://\(attachment.filename)")!, caption: nil)
                ))
            } else {
                newMessages.append(MessageDTO(
                    id: UUID(),
                    sessionId: session.id,
                    role: .user,
                    content: .file(name: attachment.filename, url: URL(string: "placeholder://\(attachment.filename)")!, size: attachment.size)
                ))
            }
        }

        // Add text message
        if !text.isEmpty {
            let userMsg = MessageDTO(
                id: UUID(),
                sessionId: session.id,
                role: .user,
                content: .text(text)
            )
            newMessages.append(userMsg)
            Task { await appState.cacheManager?.cacheMessage(userMsg) }
        }

        messages.append(contentsOf: newMessages)

        isNearBottom = true
        appState.activeSessionIds.insert(session.id)
        streamingText = ""
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        Task {
            guard let client = appState.getAPIClient() else { return }
            do {
                // Upload attachments first
                var uploadedAttachments: [AttachmentInfo] = []
                if !attachmentsToSend.isEmpty {
                    isUploading = true
                    for attachment in attachmentsToSend {
                        let info = try await client.uploadAttachment(
                            data: attachment.uploadData,
                            filename: attachment.filename,
                            mimeType: attachment.mimeType
                        )
                        uploadedAttachments.append(info)
                    }
                    isUploading = false
                }

                // Send message with attachment references
                let content = text.isEmpty ? " " : text
                let _ = try await client.sendMessage(
                    sessionId: session.id,
                    content: content,
                    attachments: uploadedAttachments.isEmpty ? nil : uploadedAttachments
                )
            } catch {
                print("Failed to send message: \(error)")
                errorMessage = error.localizedDescription
                isUploading = false
                appState.activeSessionIds.remove(session.id)
            }
        }
    }
}

// MARK: - Floating Header

struct ChatHeaderOverlay: View {
    let isActive: Bool
    var isSearching: Bool = false
    var onSearch: (() -> Void)? = nil
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if isSearching {
                Theme.Colors.background
                    .ignoresSafeArea(edges: .top)
            } else {
                LinearGradient(
                    stops: [
                        .init(color: Theme.Colors.background, location: 0),
                        .init(color: Theme.Colors.background.opacity(0.9), location: 0.4),
                        .init(color: Theme.Colors.background.opacity(0.5), location: 0.7),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            }

            // Glass pills — grouped in container on iOS 26 for unified sampling
            headerPills
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, 4)
        }
        .frame(height: isSearching ? 56 : 80)
    }

    private var pillsContent: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .interactiveGlass()
            }

            Spacer()

            AgentStatusPill(isActive: isActive)

            Spacer()

            if let onSearch {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .interactiveGlass()
                }
            } else {
                Color.clear.frame(width: 40, height: 1)
            }
        }
    }

    @ViewBuilder
    private var headerPills: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                pillsContent
            }
        } else {
            pillsContent
        }
    }
}

// MARK: - Agent Status Pill

struct AgentStatusPill: View {
    let isActive: Bool
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Theme.Colors.success : Theme.Colors.textTertiary)
                .frame(width: 8, height: 8)
                .scaleEffect(isActive && pulsing ? 1.3 : 1.0)
                .animation(
                    isActive
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )

            Text(isActive ? "Active" : "Idle")
                .font(Theme.Typography.subhead)
                .foregroundStyle(isActive ? Theme.Colors.success : Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .interactiveGlass()
        .animation(Theme.Anim.smooth, value: isActive)
        .onChange(of: isActive) { _, active in
            pulsing = active
        }
    }
}

// MARK: - Streaming Views

struct StreamingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.Colors.textSecondary)
                        .frame(width: 7, height: 7)
                        .scaleEffect(animating ? 1.3 : 0.7)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)
            .glassCard(cornerRadius: Theme.Radius.bubble)

            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct StreamingBubbleView: View {
    let text: String

    var body: some View {
        // Trailing newline ensures MarkdownUI closes the last paragraph properly
        Markdown(text + "\n")
            .markdownTheme(.claw)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chat Search Bar

struct ChatSearchBar: View {
    @Binding var text: String
    let matchCount: Int
    let currentIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Colors.textTertiary)

                TextField("Search messages…", text: $text)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .focused($isFocused)
                    .submitLabel(.search)

                if !text.isEmpty {
                    Text("\(matchCount > 0 ? "\(currentIndex + 1)/\(matchCount)" : "0")")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .interactiveGlass(in: RoundedRectangle(cornerRadius: Theme.Radius.sm))

            if !text.isEmpty {
                HStack(spacing: 4) {
                    Button(action: onPrevious) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Button(action: onNext) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .foregroundStyle(matchCount > 0 ? Theme.Colors.textPrimary : Theme.Colors.textDisabled)
                .disabled(matchCount == 0)
            }

            Button("Done", action: onDismiss)
                .font(Theme.Typography.subhead)
                .foregroundStyle(Theme.Colors.accent)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .onAppear { isFocused = true }
    }
}
