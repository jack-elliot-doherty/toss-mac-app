import SwiftUI

// MARK: - Memory Model

struct AgentMemory: Codable, Identifiable, Equatable {
    let id: String
    var content: String
    let createdAt: String

    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
    }
}

struct MemoriesResponse: Codable {
    let memories: [AgentMemory]
}

// MARK: - Memories API

final class MemoriesAPI {
    static let shared = MemoriesAPI()
    private let baseURL: URL

    init(baseURL: URL = URL(string: Config.serverURL)!) {
        self.baseURL = baseURL
    }

    func listMemories() async throws -> [AgentMemory] {
        let url = baseURL.appendingPathComponent("memories")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await APIClient.shared.perform(request)
        let response = try JSONDecoder().decode(MemoriesResponse.self, from: data)
        return response.memories
    }

    func updateMemory(id: String, content: String) async throws {
        let url = baseURL.appendingPathComponent("memories/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["content": content])

        let (_, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    func deleteMemory(id: String) async throws {
        let url = baseURL.appendingPathComponent("memories/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Memories View

@MainActor
struct MemoriesView: View {
    @State private var memories: [AgentMemory] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingMemory: AgentMemory?
    @State private var editText: String = ""
    @State private var hoveredId: String?
    @State private var deletingId: String?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent Memory")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)

                        Text("Facts the agent has learned about you and your contacts")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    }

                    if isLoading && memories.isEmpty {
                        loadingState
                    } else if let error = errorMessage {
                        errorState(error)
                    } else if memories.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(memories) { memory in
                                memoryRow(memory)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 32)
            }
            .onAppear {
                loadMemories()
            }

            // Edit modal overlay
            if editingMemory != nil {
                editModal
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading memories...")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Failed to load memories")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.primaryText)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)

            Button("Try Again") {
                loadMemories()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.accentColor))
            .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))

            Text("No memories yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.primaryText)

            Text(
                "The agent will remember facts about your contacts and preferences as you interact with it"
            )
            .font(.system(size: 13))
            .foregroundColor(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Memory Row

    private func memoryRow(_ memory: AgentMemory) -> some View {
        HStack(alignment: .center, spacing: 16) {
            // Memory icon
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundColor(.yellow.opacity(0.8))
                .frame(width: 24)

            // Content
            Text(memory.content)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Date
            if let date = memory.createdAtDate {
                Text(formattedDate(date))
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.7))
            }

            // Action buttons
            HStack(spacing: 8) {
                // Edit button
                Button {
                    editText = memory.content
                    editingMemory = memory
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundColor(
                            hoveredId == memory.id
                                ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.5)
                        )
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Edit memory")

                // Delete button
                Button {
                    deleteMemory(memory)
                } label: {
                    if deletingId == memory.id {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(
                                hoveredId == memory.id
                                    ? .red.opacity(0.8) : AppTheme.secondaryText.opacity(0.5)
                            )
                            .frame(width: 24, height: 24)
                    }
                }
                .buttonStyle(.plain)
                .help("Delete memory")
                .disabled(deletingId == memory.id)
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredId == memory.id ? AppTheme.cardBackground.opacity(0.5) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredId = hovering ? memory.id : nil
            }
        }
    }

    // MARK: - Edit Modal

    private var editModal: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    editingMemory = nil
                }

            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Edit Memory")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Spacer()

                    Button {
                        editingMemory = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                // Text editor
                TextEditor(text: $editText)
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(height: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppTheme.secondaryText.opacity(0.3), lineWidth: 1)
                    )

                // Buttons
                HStack {
                    Button("Cancel") {
                        editingMemory = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.secondaryText)

                    Spacer()

                    Button {
                        saveEdit()
                    } label: {
                        Text("Save")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(
                        editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }
            .padding(24)
            .frame(width: 450)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: editingMemory != nil)
    }

    // MARK: - Actions

    private func loadMemories() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                memories = try await MemoriesAPI.shared.listMemories()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func saveEdit() {
        guard let memory = editingMemory else { return }
        let newContent = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }

        Task {
            do {
                try await MemoriesAPI.shared.updateMemory(id: memory.id, content: newContent)
                // Update local state
                if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                    memories[index].content = newContent
                }
                editingMemory = nil
            } catch {
                NSLog("[MemoriesView] Failed to update memory: \(error)")
            }
        }
    }

    private func deleteMemory(_ memory: AgentMemory) {
        deletingId = memory.id

        Task {
            do {
                try await MemoriesAPI.shared.deleteMemory(id: memory.id)
                withAnimation {
                    memories.removeAll { $0.id == memory.id }
                }
            } catch {
                NSLog("[MemoriesView] Failed to delete memory: \(error)")
            }
            deletingId = nil
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
