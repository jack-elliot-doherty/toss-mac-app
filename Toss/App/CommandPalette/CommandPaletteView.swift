import AppKit
import SwiftUI

// MARK: - Custom TextField for Command Palette

struct CommandPaletteTextField: NSViewRepresentable {
    @Binding var text: String
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onReturn: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.stringValue = text
        textField.placeholderString = "Search..."
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14)
        textField.textColor = NSColor(AppTheme.primaryText)

        // Become first responder after a short delay
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandPaletteTextField

        init(_ parent: CommandPaletteTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        // Handle arrow keys and return
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            }

            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }

            return false
        }
    }
}

// MARK: - Overlay Container

struct CommandPaletteOverlayWrapper: View {
    @ObservedObject var viewModel: CommandPaletteViewModel
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Scrim - using a button ensures it receives clicks
            Button(action: {
                onDismiss()
            }) {
                Color.black.opacity(0.001) // Nearly transparent but still hittable
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Visible scrim layer (not interactive, just visual)
            Color.black.opacity(0.4)
                .allowsHitTesting(false)

            // Palette at top
            VStack {
                CommandPaletteView(viewModel: viewModel)
                    .fixedSize()
                    .padding(.top, 50)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - Palette View

struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            if !viewModel.filteredCommands.isEmpty {
                Divider()
                    .background(Color.white.opacity(0.1))

                resultsList
            }

            Divider()
                .background(Color.white.opacity(0.1))

            footer
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .appGlass(.surface, radius: 12)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: viewModel.filteredCommands.count)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)

            CommandPaletteTextField(
                text: $viewModel.searchQuery,
                onUpArrow: { viewModel.selectPrevious() },
                onDownArrow: { viewModel.selectNext() },
                onReturn: { viewModel.executeSelected() }
            )
            .frame(height: 20)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        let rowHeight: CGFloat = 48
        let maxVisibleRows = 7
        let contentHeight = min(CGFloat(viewModel.filteredCommands.count) * rowHeight + 8, CGFloat(maxVisibleRows) * rowHeight)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandRow(
                            command: command,
                            isSelected: index == viewModel.selectedIndex
                        )
                        .id(command.id)
                        .onTapGesture {
                            viewModel.execute(command)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(height: contentHeight)
            .onChange(of: viewModel.selectedIndex) { newIndex in
                if newIndex < viewModel.filteredCommands.count {
                    let selectedId = viewModel.filteredCommands[newIndex].id
                    proxy.scrollTo(selectedId, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerHint(keys: ["↑", "↓"], label: "navigate")
            footerHint(keys: ["↵"], label: "select")
            footerHint(keys: ["esc"], label: "close")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func footerHint(keys: [String], label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.secondaryText.opacity(0.7))
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: Command
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: command.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(iconColor.opacity(0.15))
                )

            // Text
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)

                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            // Category badge
            Text(command.category.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var iconColor: Color {
        switch command.category {
        case .navigation:
            return Color.blue
        case .actions:
            return Color.orange
        }
    }
}

#Preview {
    CommandPaletteView(viewModel: CommandPaletteViewModel())
        .preferredColorScheme(.dark)
}
