import Cocoa
import SwiftUI

@MainActor
final class AgentPanelController {
    private let panel: NSPanel
    private var hosting: NSHostingView<AgentView>?
    private let historyRepo: InMemoryHistoryRepository

    init(historyRepo: InMemoryHistoryRepository) {
        self.historyRepo = historyRepo
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 220)
        self.panel = NSPanel(contentRect: contentRect,
                              styleMask: [.nonactivatingPanel, .borderless],
                              backing: .buffered,
                              defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
    }

    func show(for thread: ThreadModel) {
        let root = AgentView(historyRepo: historyRepo, threadId: thread.id)
        let hv = NSHostingView(rootView: root)
        hosting = hv
        panel.contentView = hv
        positionBottomCenter()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionBottomCenter(margin: CGFloat = 12) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + margin + 60 // a bit higher than pill
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct AgentView: View {
    let historyRepo: InMemoryHistoryRepository
    let threadId: UUID

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(historyRepo.listMessages(threadId: threadId)) { msg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(label(for: msg.role))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 68, alignment: .trailing)
                            Text(msg.content)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .frame(width: 360, height: 220)
    }

    private func label(for role: MessageRole) -> String {
        switch role {
        case .user: return "You"
        case .assistant: return "Alma"
        case .system: return "System"
        case .tool: return "Tool"
        case .action: return "Action"
        }
    }
}


