import SwiftUI

struct ConversationManagerView: View {
    @ObservedObject var session: ChatSessionController
    @StateObject private var conversationStore = ConversationStoreController()
    @State private var isPresented = false
    @State private var renameDraft = ""
    @State private var pendingDelete: ConversationSummary?

    var body: some View {
        Button(action: presentConversationManager) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                Text(session.conversationTitle)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popoverContent
        }
        .confirmationDialog(
            "Delete Conversation?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let pendingDelete else { return }
                deleteConversation(pendingDelete)
                self.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("This removes the selected conversation and its stored messages.")
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button("New Chat", action: startNewConversation)
                    .font(.caption.bold())
            }

            if let errorMessage = conversationStore.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            TextField("Search titles", text: $conversationStore.searchQuery)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(conversationStore.conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 220)

            Divider()

            TextField("Conversation title", text: $renameDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Rename", action: renameSelectedConversation)
                    .disabled(selectedConversationId == nil || renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Delete", role: .destructive) {
                    guard let selected = selectedConversation else { return }
                    pendingDelete = selected
                }
                .disabled(selectedConversation == nil)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var selectedConversationId: String? {
        conversationStore.selectedConversationId ?? session.conversationId
    }

    private var selectedConversation: ConversationSummary? {
        guard let selectedConversationId else { return nil }
        return conversationStore.conversations.first(where: { $0.id == selectedConversationId })
    }

    @ViewBuilder
    private func conversationRow(_ conversation: ConversationSummary) -> some View {
        let isSelected = conversation.id == selectedConversationId
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    Text(conversation.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { conversationStore.togglePinned(id: conversation.id) }) {
                Image(systemName: conversation.isPinned ? "pin.slash" : "pin")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture { selectConversation(conversation.id) }
    }

    private func presentConversationManager() {
        conversationStore.refreshConversations()
        conversationStore.searchQuery = ""
        conversationStore.selectConversation(id: session.conversationId)
        renameDraft = conversationStore.loadedConversation?.title ?? session.conversationTitle
        isPresented = true
    }

    private func startNewConversation() {
        session.startFreshConversation()
        conversationStore.refreshConversations()
        conversationStore.selectConversation(id: session.conversationId)
        renameDraft = session.conversationTitle
    }

    private func selectConversation(_ id: String) {
        conversationStore.loadConversation(id: id)
        if let snapshot = conversationStore.loadedConversation {
            session.loadConversation(snapshot)
            renameDraft = snapshot.title
        }
    }

    private func renameSelectedConversation() {
        guard let selectedConversationId else { return }
        conversationStore.renameConversation(id: selectedConversationId, title: renameDraft)
        if session.conversationId == selectedConversationId {
            session.updateConversationTitle(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let updated = conversationStore.loadedConversation?.title {
            renameDraft = updated
        }
    }

    private func deleteConversation(_ conversation: ConversationSummary) {
        let deletedCurrentConversation = session.conversationId == conversation.id
        conversationStore.deleteConversation(id: conversation.id)

        if deletedCurrentConversation {
            session.startFreshConversation()
        }

        conversationStore.refreshConversations()
        conversationStore.selectConversation(id: session.conversationId)
        renameDraft = conversationStore.loadedConversation?.title ?? session.conversationTitle
    }
}
