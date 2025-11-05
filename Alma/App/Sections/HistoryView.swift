import SwiftUI

@MainActor
struct HistoryView: View {
    private let repo = PersistentHistoryRepository()

    @State private var threads: [ThreadModel] = []
    @State private var messages: [MessageModel] = []

    var body: some View {
        HStack {
            List(threads, selection: .constant(threads.first?.id)) { t in
                VStack(alignment: .leading) {
                    Text(t.title).font(.system(size: 13, weight: .semibold))
                    Text(t.updatedAt, style: .time).foregroundColor(.secondary).font(
                        .system(size: 11))
                }
            }
            .frame(width: 220)

            List(messages) { m in
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.content).font(.system(size: 13))
                    HStack {
                        Text(m.role.rawValue).foregroundColor(.secondary)
                        Text(m.createdAt, style: .time).foregroundColor(.secondary)
                    }
                    .font(.system(size: 11))
                }
                .contextMenu {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(m.content, forType: .string)
                    }
                }
            }
        }
        .onAppear {
            let t = repo.upsertThread(title: "Quick Dictations")
            self.threads = repo.listThreads()
            self.messages = repo.listMessages(threadId: t.id)
        }
    }
}
