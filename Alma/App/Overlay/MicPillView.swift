import Cocoa
import SwiftUI

struct MicPillView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.7))
            .frame(width: 180, height: 36)
            .overlay(
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.white)
                    Text("Listening…")
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
            )
    }
}

// Xcode previews helper
#if DEBUG
struct MicPillView_Previews: PreviewProvider {
    static var previews: some View {
        MicPillView()
            .previewLayout(.sizeThatFits)
    }
}
#endif


