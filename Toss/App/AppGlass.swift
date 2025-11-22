import AppKit
import SwiftUI

// Visual hierarchy of glass surfaces
enum AppGlassLevel {
    case surface  // sidebar, main surfaces
    case chrome  // toolbar pills, small buttons
    case card  // inner cards/rows
}

// Full‑window glass background (root canvas)
struct AppGlassBackground: View {
    var body: some View {
        VisualEffectView(
            material: .underWindowBackground,
            blendingMode: .behindWindow,
            state: .active
        )
        .ignoresSafeArea()
        .overlay(Color.black.opacity(0.25).ignoresSafeArea())  // global dark tint
    }
}

// Internal modifier used by .appGlass(...)
private struct AppGlassSurface: ViewModifier {
    let level: AppGlassLevel
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let tintOpacity: Double
        let strokeOpacity: Double

        switch level {
        case .surface:
            tintOpacity = 0.20
            strokeOpacity = 0.09
        case .chrome:
            tintOpacity = 0.30
            strokeOpacity = 0.12
        case .card:
            tintOpacity = 0.35
            strokeOpacity = 0.14
        }

        return
            content
            .background(
                shape
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(
                        shape.fill(Color.black.opacity(tintOpacity))
                    )
            )
    }
}

extension View {
    func appGlass(
        _ level: AppGlassLevel = .surface,
        radius: CGFloat = 16
    ) -> some View {
        modifier(AppGlassSurface(level: level, cornerRadius: radius))
    }
}

// Shared NSVisualEffectView wrapper
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
