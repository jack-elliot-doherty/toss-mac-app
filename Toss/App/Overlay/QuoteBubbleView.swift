import SwiftUI

struct QuoteBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.75))
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
struct QuoteBubbleView_Previews: PreviewProvider {
    static var previews: some View {
        QuoteBubbleView(text: "Interim transcript appears here…")
            .previewLayout(.sizeThatFits)
    }
}
#endif


