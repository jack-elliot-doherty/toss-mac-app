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
    private let windowCornerRadius: CGFloat = 18  // Match window clipShape corner radius

    var body: some View {
        VisualEffectView(
            material: .underWindowBackground,
            blendingMode: .behindWindow,
            state: .active,
            cornerRadius: windowCornerRadius
        )
        .ignoresSafeArea()
        .overlay(
            Color.black.opacity(0.25)
                .clipShape(RoundedRectangle(cornerRadius: windowCornerRadius, style: .continuous))
                .ignoresSafeArea()
        )
    }
}

// Internal modifier used by .appGlass(...)
private struct AppGlassSurface: ViewModifier {
    let level: AppGlassLevel
    let cornerRadius: CGFloat
    let opacity: Double?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let tintOpacity: Double
        let strokeOpacity: Double

          // Use provided opacity if present, otherwise use defaults
        let baseTint = opacity ?? (
            level == .surface ? 0.20 :
            level == .chrome ? 0.30 :
            0.35
        )

        tintOpacity = baseTint

        switch level {
        case .surface:
            strokeOpacity = 0.09
        case .chrome:
            strokeOpacity = 0.12
        case .card:
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
        radius: CGFloat = 16,
        opacity: Double? = nil
    ) -> some View {
        modifier(AppGlassSurface(level: level, cornerRadius: radius, opacity: opacity))
    }
}

// Shared NSVisualEffectView wrapper
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state

        // Apply corner radius mask at NSView level
        if cornerRadius > 0 {
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }

        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state

        // Update corner radius
        if cornerRadius > 0 {
            nsView.wantsLayer = true
            nsView.layer?.cornerRadius = cornerRadius
            nsView.layer?.cornerCurve = .continuous
            nsView.layer?.masksToBounds = true
        }
    }
}
