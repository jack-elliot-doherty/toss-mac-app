import Foundation

@MainActor
final class CommandRegistry: ObservableObject {
    static let shared = CommandRegistry()

    @Published private(set) var commands: [Command] = []

    private init() {
        registerDefaultCommands()
    }

    func register(_ command: Command) {
        commands.append(command)
    }

    func search(query: String) -> [Command] {
        guard !query.isEmpty else {
            return commands
        }

        let scored = commands.compactMap { command -> (Command, Double)? in
            let titleScore = fuzzyScore(query: query, against: command.title)
            let keywordScore = command.keywords.map { fuzzyScore(query: query, against: $0) }.max() ?? 0
            let score = max(titleScore, keywordScore)

            guard score > 0.3 else { return nil }
            return (command, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: - Fuzzy Matching

    private func fuzzyScore(query: String, against target: String) -> Double {
        let query = query.lowercased()
        let target = target.lowercased()

        // Exact match
        if target == query { return 1.0 }

        // Contains match
        if target.contains(query) { return 0.9 }

        // Word prefix match
        let words = target.split(separator: " ").map(String.init)
        let matchingWords = words.filter { $0.hasPrefix(query) }
        if !matchingWords.isEmpty {
            return 0.8
        }

        // Subsequence match
        var queryIndex = query.startIndex
        var matchCount = 0

        for char in target {
            if queryIndex < query.endIndex && char == query[queryIndex] {
                matchCount += 1
                queryIndex = query.index(after: queryIndex)
            }
        }

        guard queryIndex == query.endIndex else { return 0 }
        let completeness = Double(matchCount) / Double(target.count)
        return completeness * 0.7
    }

    // MARK: - Default Commands

    private func registerDefaultCommands() {
        // Navigation commands
        register(Command(
            id: "nav-meetings",
            title: "Go to Meetings",
            subtitle: "View your recorded calls",
            icon: "mic.fill",
            category: .navigation,
            keywords: ["meetings", "calls", "recordings"],
            action: .navigate(.meetings)
        ))

        register(Command(
            id: "nav-flows",
            title: "Go to Flows",
            subtitle: "Manage automations",
            icon: "command",
            category: .navigation,
            keywords: ["flows", "automations", "workflows"],
            action: .navigate(.flows)
        ))

        register(Command(
            id: "nav-integrations",
            title: "Go to Integrations",
            subtitle: "Connect apps",
            icon: "square.stack.3d.down.right.fill",
            category: .navigation,
            keywords: ["integrations", "apps", "connect", "slack", "linear", "notion"],
            action: .navigate(.integrations)
        ))

        register(Command(
            id: "nav-settings",
            title: "Go to Settings",
            subtitle: "Preferences and account",
            icon: "gear",
            category: .navigation,
            keywords: ["settings", "preferences", "account"],
            action: .navigate(.settings)
        ))
    }
}
