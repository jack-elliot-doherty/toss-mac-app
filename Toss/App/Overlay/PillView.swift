import SwiftUI

// MARK: - Style

private enum PillStyle {
    static let corner: CGFloat = 16
    static let fill      = Color.black.opacity(0.92)     // deeper black
    static let stroke    = Color.white.opacity(0.28)     // crisp white outline
    static let hairline  = 1.0
    
    // Idle silhouette (very small)
      static let idleWidth: CGFloat  = 40
      static let idleHeight: CGFloat = 10
      static let padXIdle: CGFloat   = 6
      static let padYIdle: CGFloat   = 3

      // Active states
      static let padXActive: CGFloat   = 8
      static let padYActive: CGFloat   = 4
      static let spacing: CGFloat      = 4

    static let waveformWidth: CGFloat = 64    // compact
    static let waveformHeight: CGFloat = 14
}

// MARK: - Pill

struct PillView: View {
    @ObservedObject var viewModel: PillViewModel

    var body: some View {
        Group {
            switch viewModel.visualState {
            case .idle:
                idle
            case .listening(let mode):
                listening(mode: mode)
            case .transcribing(let mode):
                transcribing(mode: mode)
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
                      .inset(by: 0.5) // makes a crisp 1px stroke on retina
                      .stroke(PillStyle.stroke, lineWidth: PillStyle.hairline)
              )
              .contentShape(Capsule())
              .fixedSize(horizontal: true, vertical: true) // hug content; no stretching
              .animation(.easeInOut(duration: 0.18), value: viewModel.visualState)
    }

    // MARK: Idle — tiny pill

    // IDLE (narrower & shorter)
    private var idle: some View {
               // Thin ring
               Capsule()
                   .stroke(Color.white.opacity(0.36), lineWidth: 1)
                   .frame(
                       width:  PillStyle.idleWidth - 8,
                       height: PillStyle.idleHeight - 2
                   )
                   .blendMode(.plusLighter)
           
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

               DotWaveformView(level: viewModel.levelRMS)
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
                       .transition(.asymmetric(
                           insertion: .move(edge: .trailing).combined(with: .opacity),
                           removal: .opacity
                       ))
               }
           }
           .padding(.horizontal, PillStyle.padXActive)
           .padding(.vertical,   PillStyle.padYActive)
       }

    // MARK: Transcribing — widen a touch and show typing dots

    private func transcribing(mode: PillMode) -> some View {
           HStack(spacing: PillStyle.spacing) {
               DotWaveformView(level: 0.22) // subtle steady center while uploading
                   .frame(width: PillStyle.waveformWidth, height: PillStyle.waveformHeight)

               TypingDots()
                   .frame(height: PillStyle.waveformHeight)

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
           .padding(.horizontal, PillStyle.padXActive + 2) // tiny widen vs listening
           .padding(.vertical,   PillStyle.padYActive)
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

/// Dot-style waveform (center grows tallest — similar to your screenshots)
private struct DotWaveformView: View {
    let level: Float // 0..1

    var body: some View {
        let clamped = max(0.0, min(1.0, level))
        let bars = 12
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { idx in
                let phase = Double(idx) / Double(bars - 1)
                let height = 4.0 + 10.0 * Double(clamped) * sin(phase * .pi)
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 3, height: max(2, height))
            }
        }
        .animation(.linear(duration: 0.05), value: clamped)
    }
}

/// Three bouncing dots for “transcribing…”
private struct TypingDots: View {
    @State private var t: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(.white)
                    .frame(width: 4, height: 4)
                    .opacity(0.7 + 0.3 * _math.sin(t + CGFloat(i) * 0.6))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                t = .pi * 2
            }
        }
    }
}
