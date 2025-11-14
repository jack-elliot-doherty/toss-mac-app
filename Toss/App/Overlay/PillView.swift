import Combine
import SwiftUI

// MARK: - Style

private enum PillStyle {
    static let corner: CGFloat = 16
    static let fill = Color.black.opacity(0.92)  // deeper black
    static let stroke = Color.white.opacity(0.28)  // crisp white outline
    static let hairline = 1.0

    // Idle silhouette (very small)
    static let idleWidth: CGFloat = 40
    static let idleHeight: CGFloat = 10
    static let padXIdle: CGFloat = 6
    static let padYIdle: CGFloat = 3

    // Active states
    static let padXActive: CGFloat = 8
    static let padYActive: CGFloat = 4
    static let spacing: CGFloat = 8

    static let waveformWidth: CGFloat = 64  // compact
    static let waveformHeight: CGFloat = 14
}

// MARK: - Pill

struct PillView: View {
    @ObservedObject var viewModel: PillViewModel
    @State private var isHovered: Bool = false

    var body: some View {
        Group {
            switch viewModel.visualState {
            case .idle:
                idle
            case .hovered:
                hoveredQuickActions
            case .listening(let mode):
                listening(mode: mode)
            case .transcribing(let mode):
                transcribing(mode: mode)
            case .meetingRecording(let meetingId):
                if isHovered {
                    meetingRecordingHovered(meetingId: meetingId)
                } else {
                    meetingRecording(meetingId: meetingId)
                }
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .background(
            Capsule(style: .continuous)
                .fill(PillStyle.fill)
        )
        .overlay(
            Capsule(style: .continuous)
                .inset(by: 0.5)  // makes a crisp 1px stroke on retina
                .stroke(PillStyle.stroke, lineWidth: PillStyle.hairline)
        )
        .contentShape(Capsule())
        .fixedSize(horizontal: true, vertical: true)  // hug content; no stretching
        .animation(.easeInOut(duration: 0.18), value: viewModel.visualState)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                viewModel.onHoverEnter?()
            } else {
                viewModel.onHoverExit?()
            }
        }
        .onTapGesture {
            viewModel.onPillClicked?()
        }
    }

    // MARK: Idle — tiny pill

    // IDLE (narrower & shorter)
    private var idle: some View {
        // Thin ring
        Capsule()
            .stroke(Color.white.opacity(0.36), lineWidth: 1)
            .frame(
                width: PillStyle.idleWidth - 8,
                height: PillStyle.idleHeight - 2
            )
            .blendMode(.plusLighter)

    }

    // NEW: Hovered state with quick actions
    private var hoveredQuickActions: some View {
        HStack(spacing: 8) {
            // Record Meeting button
            Button {
                viewModel.onQuickActionRecordMeeting?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Record Meeting")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.8))
                )
            }
            .buttonStyle(.plain)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 16)

            // Perma Dictation button
            Button {
                viewModel.onQuickActionDictation?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Dictation")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.8))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Listening
    private func listening(mode: PillMode) -> some View {
        HStack(spacing: PillStyle.spacing) {
            if viewModel.isAlwaysOn {
                // Always-on: buttons flank the waveform
                Button {
                    viewModel.onRequestCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            DotWaveformView(viewModel: viewModel)
                .id("waveform")
                .frame(width: PillStyle.waveformWidth, height: PillStyle.waveformHeight)

            if viewModel.isAlwaysOn {
                Button {
                    viewModel.onRequestStop?()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if mode == .command {
                // Temp-hold agent affordance (no toggle)
                AgentChip()
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
            }
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    // MARK: Transcribing — widen a touch and show typing dots

    private func transcribing(mode: PillMode) -> some View {
        HStack(spacing: PillStyle.spacing) {
            DotWaveformView(viewModel: viewModel)  // subtle steady center while uploading
                .frame(width: PillStyle.waveformWidth, height: PillStyle.waveformHeight)

            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)
                .colorInvert()

            if viewModel.isAlwaysOn {
                Button {
                    viewModel.onRequestCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.onRequestStop?()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if mode == .command {
                AgentChip()
            }
        }
        .padding(.horizontal, PillStyle.padXActive + 2)  // tiny widen vs listening
        .padding(.vertical, PillStyle.padYActive)
    }

    // MARK: Meeting Recording

    private func meetingRecording(meetingId: UUID) -> some View {
        HStack(spacing: PillStyle.spacing) {
            DotWaveformView(viewModel: viewModel)
                .frame(width: PillStyle.waveformWidth, height: PillStyle.waveformHeight)
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    // NEW: Meeting recording hovered state (shows stop button)
    private func meetingRecordingHovered(meetingId: UUID) -> some View {
        HStack(spacing: 8) {
            // Current recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Recording")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }

            // Stop button
            Button {
                viewModel.onStopMeetingRecording?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Stop")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.9))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

}

// MARK: - Subviews

/// Small “Agent” badge, purely indicative (no toggle).
private struct AgentChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Agent")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel("Agent mode")
    }
}

private struct DotWaveformView: View {
    @ObservedObject var viewModel: PillViewModel
    private let barCount = 12
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 26
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3

    var body: some View {
        let level = Double(max(0.0, min(1.0, viewModel.levelRMS)))
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.9))
                    .frame(
                        width: barWidth,
                        height: barHeight(at: index, level: level)
                    )
            }
        }
        .animation(.spring(response: 0.12, dampingFraction: 0.65), value: viewModel.levelRMS)
    }

    private func barHeight(at index: Int, level: Double) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center)

        // Gaussian envelope to bias the middle bars
        let sigma: Double = Double(barCount) / 5.0
        let envelope = exp(-pow(distance, 2) / (2 * pow(sigma, 2)))

        // Slight per-bar variation so they aren't perfectly mirrored
        let variation = 1 + 0.2 * sin(Double(index) * 1.25 + level * 6.0)

        // Amplify perceived loudness (gamma curve keeps quiet speech visible)
        let amplifiedLevel = pow(level, 0.65)

        let height =
            minHeight + envelope * variation * amplifiedLevel * Double(maxHeight - minHeight)
        return CGFloat(clamp(height, min: Double(minHeight), max: Double(maxHeight)))
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}
