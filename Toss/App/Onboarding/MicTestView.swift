import AVFoundation
import SwiftUI

struct MicTestView: View {
    let onConfirm: () -> Void
    let onChangeMic: () -> Void

    @State private var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 12)
    @State private var audioRecorder: AudioRecorder?
    @State private var isListening = false

    private let barCount = 12
    private let accentColor = Color(red: 0.55, green: 0.45, blue: 0.85)  // Purple like in the design

    var body: some View {
        VStack(spacing: 20) {
            Text("Do you see purple bars moving while you speak?")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            // Audio level bars
            HStack(spacing: 6) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(barColor(for: index))
                        .frame(width: 8, height: barHeight(for: index))
                        .animation(.easeOut(duration: 0.08), value: audioLevels[index])
                }
            }
            .frame(height: 60)
            .padding(.vertical, 10)

            // Buttons
            HStack(spacing: 12) {
                Button(action: onChangeMic) {
                    Text("No, change microphone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Yes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.9))
                        )
                }
                .buttonStyle(.plain)
            }
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
            startListening()
        }
        .onDisappear {
            stopListening()
        }
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
        let maxHeight: CGFloat = 50
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
        // Shift levels left and add new level at end with some variation
        var newLevels = Array(audioLevels.dropFirst())

        // Add some randomness to make it look more natural
        let variation = CGFloat.random(in: -0.1...0.1)
        let adjustedLevel = max(0.05, min(1.0, newLevel + variation))
        newLevels.append(adjustedLevel)

        audioLevels = newLevels
    }
}

#Preview {
    ZStack {
        Color(red: 0.98, green: 0.96, blue: 0.90)
            .ignoresSafeArea()

        MicTestView(
            onConfirm: {},
            onChangeMic: {}
        )
        .padding(40)
    }
}
