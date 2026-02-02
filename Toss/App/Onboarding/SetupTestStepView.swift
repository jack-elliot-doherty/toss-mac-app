import AVFoundation
import SwiftUI

struct SetupTestStepView: View {
    @ObservedObject private var manager = OnboardingManager.shared

    var body: some View {
        VStack(spacing: 32) {
            // Headline
            Text("Let's make sure it works")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.primaryText)

            VStack(spacing: 16) {
                // Mic test card
                SetupTestCard(
                    title: "Say something",
                    isComplete: manager.micTestPassed
                ) {
                    MicTestContent(onConfirm: { manager.micTestPassed = true })
                }

                // Hotkey test card
                SetupTestCard(
                    title: "Hold the fn key",
                    isComplete: manager.hotkeyTestPassed
                ) {
                    HotkeyTestContent(onConfirm: { manager.hotkeyTestPassed = true })
                }
            }

            // Status when both pass
            if manager.micTestPassed && manager.hotkeyTestPassed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Everything is working")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
    }
}

// MARK: - Setup Test Card

struct SetupTestCard<Content: View>: View {
    let title: String
    let isComplete: Bool
    @ViewBuilder let content: () -> Content

    private let accentColor = Color(red: 0.55, green: 0.45, blue: 0.85)
    private let grantedColor = Color(red: 0.3, green: 0.8, blue: 0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(grantedColor)
                }

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isComplete ? grantedColor : AppTheme.primaryText)
            }

            // Content (only show when not complete)
            if !isComplete {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isComplete)
    }
}

// MARK: - Mic Test Content

struct MicTestContent: View {
    let onConfirm: () -> Void

    @State private var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 12)
    @State private var audioRecorder: AudioRecorder?
    @State private var isListening = false

    private let barCount = 12
    private let accentColor = Color(red: 0.55, green: 0.45, blue: 0.85)

    var body: some View {
        VStack(spacing: 16) {
            // Audio level bars
            HStack(spacing: 6) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(barColor(for: index))
                        .frame(width: 8, height: barHeight(for: index))
                        .animation(.easeOut(duration: 0.08), value: audioLevels[index])
                }
            }
            .frame(height: 50)

            // Buttons
            HStack(spacing: 12) {
                // Secondary: Not working
                Button(action: restartApp) {
                    Text("Not working? Restart")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                // Primary: Confirm
                Button(action: onConfirm) {
                    Text("Yes, I see bars moving")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    private func barColor(for index: Int) -> Color {
        let level = audioLevels[index]
        if level > 0.15 {
            return accentColor
        } else {
            return Color.white.opacity(0.15)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 12
        let maxHeight: CGFloat = 40
        let level = audioLevels[index]
        return minHeight + (maxHeight - minHeight) * level
    }

    private func startListening() {
        guard !isListening else { return }

        let recorder = AudioRecorder()
        recorder.onLevelUpdate = { level in
            updateLevels(with: CGFloat(level))
        }
        recorder.start()
        audioRecorder = recorder
        isListening = true
    }

    private func stopListening() {
        _ = audioRecorder?.stop()
        audioRecorder = nil
        isListening = false
    }

    private func updateLevels(with newLevel: CGFloat) {
        var newLevels = Array(audioLevels.dropFirst())
        let variation = CGFloat.random(in: -0.1...0.1)
        let adjustedLevel = max(0.05, min(1.0, newLevel + variation))
        newLevels.append(adjustedLevel)
        audioLevels = newLevels
    }

    private func restartApp() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Hotkey Test Content

struct HotkeyTestContent: View {
    let onConfirm: () -> Void

    @State private var isFnPressed = false

    private let accentColor = Color(red: 0.55, green: 0.45, blue: 0.85)

    var body: some View {
        VStack(spacing: 16) {
            // Fn key visualization
            HStack(spacing: 20) {
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

                Text("Press and hold")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

            // Buttons
            HStack(spacing: 12) {
                // Secondary: Not working
                Button(action: restartApp) {
                    Text("Not working? Restart")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                // Primary: Confirm
                Button(action: onConfirm) {
                    Text("Yes, it lights up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { setupFnKeyMonitoring() }
    }

    private func restartApp() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private func setupFnKeyMonitoring() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let fnPressed = event.modifierFlags.contains(.function)
            if fnPressed != isFnPressed {
                isFnPressed = fnPressed
            }
            return event
        }

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
        SetupTestStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 580)
}
