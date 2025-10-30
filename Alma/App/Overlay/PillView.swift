import SwiftUI

struct PillView: View {
    @ObservedObject var viewModel: PillViewModel

    var body: some View {
        let isIdle = {
            if case .idle = viewModel.visualState { return true }
            return false
        }()

        Group {
            switch viewModel.visualState {
            case .idle:
                idle
            case .listening:
                listening
            case .transcribing:
                transcribing
            }
        }
        .padding(.horizontal, isIdle ? 8 : 10)
        .padding(.vertical, isIdle ? 4 : 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.18), value: viewModel.visualState)
    }

    private var idle: some View {
        // Content size = panel size (64x16) minus padding (8px each side, 4px top/bottom)
        // So: 64 - 16 = 48 width, 16 - 8 = 8 height
        Color.clear
            .frame(width: 48, height: 8)
    }

    private var listening: some View {
        HStack(spacing: 10) {
            WaveformView(level: viewModel.levelRMS)
                .frame(width: 80, height: 18)

            Spacer(minLength: 0)

            Toggle(isOn: Binding(get: { viewModel.agentModeEnabled }, set: { new in
                viewModel.agentModeEnabled = new
                viewModel.toggleAgentMode()
            })) {
                Text("Agent")
                    .foregroundColor(.white.opacity(0.9))
                    .font(.system(size: 11, weight: .semibold))
            }
            .toggleStyle(.switch)
            .tint(.red)
            .labelsHidden()

            Button {
                viewModel.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))

            Button {
                viewModel.endListening()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private var transcribing: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.7)
                .tint(.white)
            Text("Transcribing…")
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .medium))
        }
    }
}

private struct WaveformView: View {
    let level: Float // 0…1

    var body: some View {
        let clamped = max(0.0, min(1.0, level))
        let bars = 10
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<bars, id: \.self) { idx in
                let phase = Double(idx) / Double(bars - 1)
                let height = 6.0 + 12.0 * Double(clamped) * sin(phase * .pi)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 3, height: height)
                    .opacity(0.9)
            }
        }
        .animation(.linear(duration: 0.05), value: clamped)
    }
}


