import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ContextualSidebar: View {
    let meetingId: String
    @Environment(MeetingViewModel.self) private var meetingVM
    @State private var chatInput: String = ""
    @State private var chatResponse: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "rectangle.rightthird.inset.filled")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accent)
                Text("Actions")
                    .font(DesignTokens.Typography.sectionHead)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.space4)
            .padding(.vertical, DesignTokens.Spacing.space3)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space6) {
                    // Share Notes section
                    shareNotesSection

                    Divider().opacity(0.3)
                        .padding(.horizontal, DesignTokens.Spacing.space2)

                    // Ask Vaakya section
                    askVaakyaSection
                }
                .padding(.horizontal, DesignTokens.Spacing.space4)
                .padding(.vertical, DesignTokens.Spacing.space4)
            }
        }
        .frame(width: 240)
        .background(Color.bgSidebar)
    }

    // MARK: - Share Notes

    private var shareNotesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space3) {
            Text("Share Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            VStack(spacing: DesignTokens.Spacing.space2) {
                sidebarButton(icon: "doc.on.doc", label: "Copy text") {
                    copyRichText()
                }

                sidebarButton(icon: "envelope", label: "Email") {
                    openEmailCompose()
                }

                sidebarButton(icon: "number", label: "Copy for Slack") {
                    copySlackFormatted()
                }
            }
        }
    }

    // MARK: - Ask Vaakya

    private var askVaakyaSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space3) {
            Text("Ask Vaakya")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            // Quick action buttons
            VStack(spacing: DesignTokens.Spacing.space2) {
                quickActionButton(label: "List action items") {
                    await sendChat("List all action items from this meeting")
                }

                quickActionButton(label: "Write follow-up") {
                    await sendChat("Write a follow-up email summarizing this meeting")
                }

                quickActionButton(label: "Summarize") {
                    await sendChat("Give me a brief summary of this meeting")
                }
            }

            // Freeform input
            HStack(spacing: DesignTokens.Spacing.space2) {
                TextField("Ask about the meeting...", text: $chatInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, DesignTokens.Spacing.space3)
                    .padding(.vertical, DesignTokens.Spacing.space2)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                            .fill(Color.bgContent)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .onSubmit {
                        let text = chatInput
                        chatInput = ""
                        Task { await sendChat(text) }
                    }
                    .disabled(isLoading)

                Button(action: {
                    let text = chatInput
                    chatInput = ""
                    Task { await sendChat(text) }
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(chatInput.isEmpty || isLoading ? Color.textTertiary : Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(chatInput.isEmpty || isLoading)
            }

            // Response area
            if isLoading {
                HStack(spacing: DesignTokens.Spacing.space2) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Color.accent)
                    Text("Thinking...")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .padding(.vertical, DesignTokens.Spacing.space2)
            }

            if let error = errorMessage {
                HStack(spacing: DesignTokens.Spacing.space1) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 10))
                        .lineLimit(3)
                }
                .foregroundStyle(Color.blockRed)
                .padding(.vertical, DesignTokens.Spacing.space1)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        errorMessage = nil
                    }
                }
            }

            if !chatResponse.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space2) {
                    HStack(spacing: DesignTokens.Spacing.space1) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accent)
                        Text("Vaakya")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accent)
                        Spacer()

                        Button(action: {
                            #if canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(chatResponse, forType: .string)
                            #endif
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy response")
                    }

                    Text(chatResponse)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(DesignTokens.Spacing.space3)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .fill(Color.bgCard)
                )
            }
        }
    }

    // MARK: - Sidebar Button

    private func sidebarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.space2) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.bgCard)
            )
        }
        .buttonStyle(.plain)
    }

    private func quickActionButton(label: String, action: @escaping () async -> Void) -> some View {
        Button(action: { Task { await action() } }) {
            HStack(spacing: DesignTokens.Spacing.space2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accent)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: DesignTokens.Button.compactFontSize, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.space3)
            .padding(.vertical, DesignTokens.Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(Color.accent.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    // MARK: - Actions

    private func sendChat(_ message: String) async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isLoading = true
        chatResponse = ""
        errorMessage = nil

        do {
            // Load transcript from the current meeting document
            guard let doc = LocalStore.shared.loadMeeting(id: meetingId) else {
                errorMessage = "Meeting not found"
                isLoading = false
                return
            }
            let settings = LocalStore.shared.loadSettings()
            chatResponse = try await AIService.shared.chat(
                transcript: doc.transcript,
                message: text,
                settings: settings,
                language: settings.notesLanguage
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func copyRichText() {
        #if canImport(AppKit)
        let blocks = meetingVM.blocks
        let meeting = meetingVM.selectedMeeting
        var text = ""

        if let title = meeting?.title {
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            text += "\(title)\n"
            text += "\(df.string(from: meeting?.startedAt ?? Date()))\n\n"
        }

        for block in blocks {
            switch block.type.lowercased() {
            case "summary":
                text += "\(block.content)\n\n"
            case "decision":
                text += "Decision: \(block.content)\n"
            case "action":
                let check = block.isChecked ? "[x]" : "[ ]"
                text += "\(check) \(block.content)\n"
            case "quote":
                text += "\"\(block.content)\"\n"
                if let speaker = block.speaker {
                    text += "  -- \(speaker)\n"
                }
            default:
                text += "\(block.content)\n"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func openEmailCompose() {
        #if canImport(AppKit)
        let blocks = meetingVM.blocks
        let meeting = meetingVM.selectedMeeting
        let title = meeting?.title ?? "Meeting Notes"

        let df = DateFormatter()
        df.dateFormat = "MMM d, h:mm a"
        var body = "\(title)\n\(df.string(from: meeting?.startedAt ?? Date()))\n\n"
        for block in blocks {
            switch block.type.lowercased() {
            case "summary":  body += "\(block.content)\n\n"
            case "decision": body += "Decision: \(block.content)\n"
            case "action":   body += "- \(block.content)\n"
            case "quote":    body += "> \(block.content)\n"
            default:         body += "\(block.content)\n"
            }
        }

        let subject = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let emailBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:?subject=\(subject)&body=\(emailBody)") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func copySlackFormatted() {
        #if canImport(AppKit)
        let blocks = meetingVM.blocks
        let meeting = meetingVM.selectedMeeting
        var text = ""

        if let title = meeting?.title {
            let df = DateFormatter()
            df.dateFormat = "MMM d, h:mm a"
            text += "*\(title)*\n"
            text += "_\(df.string(from: meeting?.startedAt ?? Date()))_\n\n"
        }

        for block in blocks {
            switch block.type.lowercased() {
            case "summary":
                text += "\(block.content)\n\n"
            case "decision":
                text += ":white_check_mark: *Decision:* \(block.content)\n"
            case "action":
                let emoji = block.isChecked ? ":ballot_box_with_check:" : ":black_square_button:"
                text += "\(emoji) \(block.content)\n"
            case "quote":
                text += "> _\(block.content)_\n"
                if let speaker = block.speaker {
                    text += "> -- \(speaker)\n"
                }
            default:
                text += "\(block.content)\n"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
