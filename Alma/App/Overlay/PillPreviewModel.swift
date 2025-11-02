#if DEBUG
import SwiftUI
import Combine

struct PillPreviewHarness: View {
    @StateObject var vm = PillViewModel()

    var body: some View {
        VStack(spacing: 16) {
            PillView(viewModel: vm)
                .padding()
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Controls to flip preview states without recording audio
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("State")
                    Picker("", selection: Binding(
                        get: { visualPickerTag(for: vm.visualState) },
                        set: { vm.visualState = stateForPickerTag($0, current: vm.visualState) }
                    )) {
                        Text("Idle").tag(0)
                        Text("Listening • Dictation").tag(1)
                        Text("Listening • Command").tag(2)
                        Text("Transcribing • Dictation").tag(3)
                        Text("Transcribing • Command").tag(4)
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("Always-On", isOn: $vm.isAlwaysOn)
                    .toggleStyle(.switch)

                HStack {
                    Text("Level")
                    Slider(value: Binding(
                        get: { Double(vm.levelRMS) },
                        set: { vm.updateLevelRMS(Float($0)) }
                    ), in: 0...1)
                }
            }
            .padding()
        }
        .padding()
        .onAppear {
            // tiny waveform animation for the preview
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                let base = (sin(CFAbsoluteTimeGetCurrent() * 2.4) + 1) / 2
                let jitter = Double.random(in: -0.06...0.06)
                vm.updateLevelRMS(Float(max(0, min(1, base + jitter))))
            }
        }
    }

    // Helpers to map enum to a stable picker selection
    private func visualPickerTag(for s: PillVisualState) -> Int {
        switch s {
        case .idle: return 0
        case .listening(.dictation): return 1
        case .listening(.command): return 2
        case .transcribing(.dictation): return 3
        case .transcribing(.command): return 4
        }
    }
    private func stateForPickerTag(_ tag: Int, current: PillVisualState) -> PillVisualState {
        switch tag {
        case 0: return .idle
        case 1: return .listening(.dictation)
        case 2: return .listening(.command)
        case 3: return .transcribing(.dictation)
        case 4: return .transcribing(.command)
        default: return current
        }
    }
}

struct PillView_Previews: PreviewProvider {
    static var previews: some View {
        PillPreviewHarness()
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
    }
}
#endif
