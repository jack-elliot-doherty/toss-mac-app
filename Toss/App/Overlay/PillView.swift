import Combine
import SwiftUI

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
    @State private var hoverExitWorkItem: DispatchWorkItem?

    var body: some View {
        let isMeetingRecording: Bool = {
            if case .meetingRecording = viewModel.visualState { return true }
            return false
        }()

        Group {
            switch viewModel.visualState {
            case .idle:
                idle.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
            case .hovered:
                hoveredQuickActions.transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            case .listening(let mode):
                listening(mode: mode).transition(
                    .asymmetric(
                        insertion: .scale(scale: 1.05, anchor: .center).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            case .transcribing(let mode):
                transcribing(mode: mode)
            case .meetingDetected:
                meetingDetected
            case .upcomingMeeting(let meeting):
                upcomingMeetingView(meeting: meeting)
            case .meetingRecording(let meetingId, let isPaused):
                meetingRecording(meetingId: meetingId, isPaused: isPaused, isHovered: isHovered)

            case .agentSessionActive:
                agentSessionActive.transition(
                    .opacity.combined(with: .scale(scale: 0.9, anchor: .center)))
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
        .if(!isMeetingRecording) { view in
            view.fixedSize(horizontal: true, vertical: true)
        }
        .animation(
            .spring(response: 0.22, dampingFraction: 0.85),
            value: viewModel.visualState
        )
        .onHover { hovering in
            isHovered = hovering

            // Notify view model if we're in meeting recording state
            // Use same debounce delay as general hover exit
            if case .meetingRecording = viewModel.visualState {
                if hovering {
                    // Cancel any pending hover exit
                    hoverExitWorkItem?.cancel()
                    hoverExitWorkItem = nil
                    viewModel.isMeetingRecordingHovered = true
                } else {
                    // Debounce hover exit to prevent rapid grow/shrink
                    hoverExitWorkItem?.cancel()
                    let item = DispatchWorkItem { [weak viewModel] in
                        viewModel?.isMeetingRecordingHovered = false
                    }
                    hoverExitWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
                }
                // Don't trigger general hover callbacks for meeting recording
                return
            }

            if hovering {
                hoverExitWorkItem?.cancel()
                hoverExitWorkItem = nil
                viewModel.onHoverEnter?()
            } else {
                hoverExitWorkItem?.cancel()
                let item = DispatchWorkItem { [weak viewModel] in
                    viewModel?.onHoverExit?()
                }
                hoverExitWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
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

    // MARK: Agent Session Active — shows there's a minimized agent session
    private var agentSessionActive: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text("Resume")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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

    private func upcomingMeetingView(meeting: UpcomingMeeting) -> some View {
        HStack(spacing: PillStyle.spacing) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Starting \(meeting.relativeTime)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Single Join & Record button
            Button {
                viewModel.onJoinAndRecordUpcoming?(meeting)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Join & Start")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.blue))
            }
            .buttonStyle(.plain)

            // Dismiss X
            Button {
                viewModel.onDismissUpcomingMeeting?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    private var meetingDetected: some View {
        HStack(spacing: PillStyle.spacing) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting detected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Tap Start or press fn to begin recording")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Button {
                viewModel.onQuickActionRecordMeeting?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Start")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.9))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    private func meetingRecording(meetingId: UUID, isPaused: Bool, isHovered: Bool) -> some View {
        HStack(spacing: isHovered ? PillStyle.spacing : 6) {
            // Waveform always on left
            DotWaveformView(viewModel: viewModel)
                .frame(
                    width: isHovered ? PillStyle.waveformWidth : 44,
                    height: isHovered ? PillStyle.waveformHeight : 12
                )
                .clipped()

            if isHovered {
                // Expanded controls
                if isPaused {
                    Button {
                        viewModel.onResumeMeetingRecording?()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.green.opacity(0.9)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.onStopMeetingRecording?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Done")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red.opacity(0.9)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        viewModel.onPauseMeetingRecording?()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Compact: colored dot
                Circle()
                    .fill(isPaused ? Color.yellow : Color.red)
                    .frame(width: 8, height: 8)
                    .modifier(PulsingModifier())
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, isHovered ? PillStyle.padXActive : 10)
        .padding(.vertical, isHovered ? PillStyle.padYActive : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // Fill the panel
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(nil, value: isPaused)
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

private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
