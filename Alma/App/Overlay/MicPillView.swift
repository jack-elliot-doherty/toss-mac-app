import Cocoa
import SwiftUI

final class MicPillModel: ObservableObject {
    enum State {
        case idle
        case listening
        case loading
    }

    @Published var state: State = .idle
}

struct MicPillView: View {
    @ObservedObject var model: MicPillModel
    @State private var isHovered: Bool = false

    var body: some View {
        let expanded = model.state == .listening || model.state == .loading || isHovered
        let width: CGFloat = expanded ? 180 : 40
        let height: CGFloat = expanded ? 36 : 16
        let radius: CGFloat = expanded ? 16 : 8

        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.black.opacity(0.7))
            .frame(width: width, height: height)
            .overlay(
                Group {
                    if expanded {
                        HStack(spacing: 8) {
                            if model.state == .loading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.7)
                                    .tint(.white)
                                Text("Transcribing…")
                                    .foregroundColor(.white)
                                    .font(.system(size: 13, weight: .medium))
                            } else if model.state == .listening {
                                Image(systemName: "waveform")
                                    .foregroundColor(.white)
                                Text("Listening…")
                                    .foregroundColor(.white)
                                    .font(.system(size: 13, weight: .medium))
                            } else { // idle but hovered
                                Image(systemName: "waveform")
                                    .foregroundColor(.white)
                                Text("Alma")
                                    .foregroundColor(.white)
                                    .font(.system(size: 13, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 12)
                    } else {
                        Image(systemName: "waveform")
                            .foregroundColor(.white)
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            )
            .onHover { over in
                isHovered = over
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: model.state)
    }
}

// Xcode previews helper
#if DEBUG
struct MicPillView_Previews: PreviewProvider {
    static var previews: some View {
        MicPillView(model: MicPillModel())
            .previewLayout(.sizeThatFits)
    }
}
#endif


