import SwiftUI

// MARK: - Grok Bot chat
//
// Talk to Grok Bot from inside Life. A message goes to the server, which sends
// it to a Grok Bot routine's webhook trigger. Grok Bot wakes, does whatever was
// asked through its Life page, and replies with the page's "Reply to Will"
// form, which lands here. Replies take as long as Grok Bot takes, usually a
// minute or two, so this screen checks for new ones every few seconds.

struct GrokBotMessage: Identifiable, Equatable {
    var id: String
    var fromBot: Bool
    var text: String
    var status: String?
    var error: String?
    var date: Date

    init?(_ raw: [String: Any]) {
        guard let id = raw["id"] as? String, let text = raw["text"] as? String else { return nil }
        self.id = id
        self.fromBot = (raw["from"] as? String) == "bot"
        self.text = text
        self.status = raw["status"] as? String
        self.error = raw["error"] as? String
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.date = (raw["createdAt"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
    }
}

@MainActor
@Observable
final class GrokBotChatModel {
    var messages: [GrokBotMessage] = []
    var chatConnected: Bool?
    var sending = false
    var error: String?

    func refreshStatus() async {
        if let status = try? await LifeBotAPI.call(["action": "status"]) {
            chatConnected = status["chatConnected"] as? Bool ?? false
        }
    }

    func load() async {
        guard let result = try? await LifeBotAPI.call(["action": "chat"]),
              let raw = result["messages"] as? [[String: Any]] else { return }
        let fresh = raw.compactMap(GrokBotMessage.init)
        if fresh != messages { messages = fresh }
    }

    func send(_ text: String) async -> Bool {
        sending = true
        error = nil
        defer { sending = false }
        do {
            let result = try await LifeBotAPI.call(["action": "sendChat", "text": text])
            if result["ok"] as? Bool != true {
                error = result["error"] as? String ?? "Grok Bot didn't get that."
            }
            await load()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func connect(url: String, key: String) async -> Bool {
        error = nil
        do {
            _ = try await LifeBotAPI.call(["action": "setWebhook", "url": url, "key": key])
            chatConnected = true
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func disconnect() async {
        _ = try? await LifeBotAPI.call(["action": "clearWebhook"])
        chatConnected = false
    }
}

struct GrokBotChatView: View {

    @State private var model = GrokBotChatModel()
    @State private var draft = ""
    @State private var showSetup = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.chatConnected == false {
                setupPrompt
            } else {
                conversation
                inputBar
            }
        }
        .navigationTitle("Grok Bot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSetup = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Chat connection")
            }
        }
        .sheet(isPresented: $showSetup) {
            GrokBotChatSetupSheet(model: model)
        }
        .task {
            await model.refreshStatus()
            while !Task.isCancelled {
                await model.load()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var setupPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Connect the chat to Grok Bot")
                .font(.headline)
            Text("In Grok Bot, make a routine with a Webhook trigger, then paste its address and secret key here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Connect") { showSetup = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if model.messages.isEmpty {
                        Text("Say hello, or ask Grok Bot to do something in Life. Tap the mic on the keyboard to talk instead of typing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40)
                            .padding(.horizontal)
                    }
                    ForEach(model.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if let last = model.messages.last, !last.fromBot, last.status == "sent" {
                        HStack {
                            Text("Grok Bot is working on it…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                if let id = model.messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ message: GrokBotMessage) -> some View {
        HStack {
            if !message.fromBot { Spacer(minLength: 40) }
            VStack(alignment: message.fromBot ? .leading : .trailing, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.fromBot ? Color(.secondarySystemBackground) : AppTheme.primary.opacity(0.85))
                    .foregroundStyle(message.fromBot ? Color.primary : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if let error = message.error, message.status == "failed" {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text(message.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if message.fromBot { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Grok Bot", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    draft = ""
                    Task {
                        let sent = await model.send(text)
                        if !sent { draft = text }
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(model.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// Where the Grok Bot routine's webhook address and key go.
struct GrokBotChatSetupSheet: View {

    let model: GrokBotChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var key = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api2.cursor.sh/automations/webhook/…", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Secret key (starts crsr_)", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Grok Bot webhook")
                } footer: {
                    Text("In Grok Bot: make a new routine, tap Add trigger, choose Webhook, and copy the address and key it shows. Switch the routine on. Its instruction is in the setup steps you were sent.")
                }

                if let error = model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if model.chatConnected == true {
                    Section {
                        Button("Disconnect chat", role: .destructive) {
                            Task {
                                await model.disconnect()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chat connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            let ok = await model.connect(
                                url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                key: key.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving || url.isEmpty || key.isEmpty)
                }
            }
        }
    }
}
