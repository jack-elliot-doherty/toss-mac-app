import Foundation
import SwiftUI

@MainActor
final class CommandPaletteViewModel: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedIndex: Int = 0

    private let registry = CommandRegistry.shared

    // Callbacks for actions that need external wiring
    var onNavigate: ((SidebarItem) -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onStartDictation: (() -> Void)?
    var onOpenAgent: (() -> Void)?
    var onDismiss: (() -> Void)?

    var filteredCommands: [Command] {
        registry.search(query: searchQuery)
    }

    func selectNext() {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    func selectPrevious() {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex - 1 + count) % count
    }

    func executeSelected() {
        guard selectedIndex < filteredCommands.count else { return }
        let command = filteredCommands[selectedIndex]
        execute(command)
    }

    func execute(_ command: Command) {
        switch command.action {
        case .navigate(let item):
            onNavigate?(item)
        case .execute:
            // Route to the appropriate callback based on command ID
            switch command.id {
            case "action-start-recording":
                onStartRecording?()
            case "action-stop-recording":
                onStopRecording?()
            case "action-start-dictation":
                onStartDictation?()
            case "action-open-agent":
                onOpenAgent?()
            default:
                break
            }
        }
        onDismiss?()
    }

    func reset() {
        searchQuery = ""
        selectedIndex = 0
    }
}
