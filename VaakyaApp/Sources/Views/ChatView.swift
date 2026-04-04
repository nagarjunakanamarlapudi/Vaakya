import SwiftUI

struct ChatView: View {
    let meetingId: String
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accent)
                Text("Chat")
                    .font(DesignTokens.Typography.sectionHead)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.5)

            // Messages
            if messages.isEmpty && !isLoading {
                Spacer()
                VStack(spacing: DesignTokens.Spacing.space3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.textTertiary)
                    Text("Ask about this meeting")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("Ask questions about the meeting content\nand get AI-powered answers.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: DesignTokens.Spacing.space3) {
                            ForEach(messages) { message in
                                chatBubble(message)
                            }

                            if isLoading {
                                HStack(spacing: DesignTokens.Spacing.space2) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(Color.accent)
                                    Text("Thinking...")
                                        .font(DesignTokens.Typography.label)
                                        .foregroundStyle(Color.textTertiary)
                                    Spacer()
                                }
                                .padding(.horizontal, DesignTokens.Spacing.space4)
                                .id("loading")
                            }
                        }
                        .padding(.vertical, DesignTokens.Spacing.space3)
                        .padding(.horizontal, DesignTokens.Spacing.space3)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            if let lastId = messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) { _, loading in
                        if loading {
                            withAnimation { proxy.scrollTo("loading", anchor: .bottom) }
                        }
                    }
                }
            }

            // Error message
            if let error = errorMessage {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .foregroundStyle(Color.blockRed)
                .padding(.horizontal, DesignTokens.Spacing.space4)
                .padding(.vertical, DesignTokens.Spacing.space2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blockRed.opacity(0.08))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        errorMessage = nil
                    }
                }
            }

            Divider().opacity(0.5)

            // Input bar
            HStack(spacing: DesignTokens.Spacing.space2) {
                TextField("Ask about this meeting...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space2 + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.bgContent)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .onSubmit { sendMessage() }
                    .disabled(isLoading)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(inputText.isEmpty || isLoading ? Color.textTertiary : Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space3)
        }
        #if os(macOS)
        .frame(width: 340)
        #endif
        .background(Color.bgSidebar)
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: DesignTokens.Spacing.space1) {
                Text(message.content)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)

                if message.role == .assistant, let sources = message.sources, !sources.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.space1) {
                        ForEach(sources, id: \.self) { source in
                            Text(source)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 2).fill(Color.accent.opacity(0.08)))
                        }
                    }
                }

                Text(formatTime(message.timestamp))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                    .fill(message.role == .user ? Color.accent.opacity(0.10) : Color.bgCard)
                    .shadow(color: DesignTokens.Shadow.cardColor, radius: 1, y: 1)
            )

            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let doc = LocalStore.shared.loadMeeting(id: meetingId) else {
                    errorMessage = "Meeting not found"
                    isLoading = false
                    return
                }
                let settings = LocalStore.shared.loadSettings()
                let responseText = try await AIService.shared.chat(
                    transcript: doc.transcript,
                    message: text,
                    settings: settings
                )
                let aiMessage = ChatMessage(role: .assistant, content: responseText)
                messages.append(aiMessage)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
