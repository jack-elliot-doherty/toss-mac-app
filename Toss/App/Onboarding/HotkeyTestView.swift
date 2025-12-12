import SwiftUI

struct HotkeyTestView: View {
    let onConfirm: () -> Void

    @State private var isFnPressed = false

    private let accentColor = Color(red: 0.55, green: 0.45, blue: 0.85)  // Purple

    var body: some View {
        VStack(spacing: 20) {
            Text("Does the button turn purple while pressing it?")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            // Fn key visualization
            VStack(spacing: 4) {
                Text("fn")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isFnPressed ? .white : AppTheme.secondaryText)

                Image(systemName: "globe")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isFnPressed ? .white : AppTheme.secondaryText)
            }
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isFnPressed ? accentColor : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFnPressed ? accentColor : AppTheme.subtleStroke, lineWidth: 1)
            )
            .shadow(color: isFnPressed ? accentColor.opacity(0.4) : Color.clear, radius: 8, y: 2)
            .animation(.easeOut(duration: 0.1), value: isFnPressed)
            .padding(.vertical, 8)

            // Confirm button
            Button(action: onConfirm) {
                Text("Yes, it works!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .onAppear {
            setupFnKeyMonitoring()
        }
    }

    private func setupFnKeyMonitoring() {
        // Monitor for Fn key press using local event monitor
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let fnPressed = event.modifierFlags.contains(.function)
            if fnPressed != isFnPressed {
                isFnPressed = fnPressed
            }
            return event
        }

        // Also monitor globally for when app window is key but not focused on a text field
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let fnPressed = event.modifierFlags.contains(.function)
            if fnPressed != isFnPressed {
                isFnPressed = fnPressed
            }
        }
    }
}

#Preview {
    ZStack {
        AppGlassBackground()

        HotkeyTestView(
            onConfirm: {}
        )
        .padding(40)
    }
}
