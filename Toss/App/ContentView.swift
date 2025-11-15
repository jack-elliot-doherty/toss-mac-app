import AppKit
import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case meetings
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .meetings: return "Meetings"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .meetings: return "mic.fill"
        case .settings: return "gear"
        }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selection: SidebarItem? = .home
    @State private var showSettings = false
    @State private var pendingMeetingId: UUID?  // used to switch to the currently recording meeting
    @State private var windowReference: NSWindow?

    @StateObject private var meetingRepo = PersistentMeetingRepository()

    var body: some View {
        ZStack {
            AppTheme.windowBackground
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 16) {
                sidebar
                    .frame(width: 238)

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.windowBackground)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .frame(minWidth: 980, minHeight: 600)
            .onReceive(
                NotificationCenter.default.publisher(for: NSNotification.Name("OpenMeetingView"))
            ) { notification in
                if let userInfo = notification.userInfo,
                    let meetingId = userInfo["meetingId"] as? UUID
                {
                    selection = .meetings
                    pendingMeetingId = meetingId
                }
            }

            if showSettings {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { showSettings = false }

                SettingsModalView(onClose: { showSettings = false })
                    .frame(width: 760)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .background(
            WindowReader { window in
                guard let window else { return }
                windowReference = window
                configureWindow(window)
            }
        )
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))
        ) { _ in
            showSettings = true
        }
    }

    private var sidebar: some View {
        VStack(spacing: 18) {
            TrafficLightsView(
                onClose: { windowReference?.performClose(nil) },
                onMinimize: { windowReference?.miniaturize(nil) },
                onZoom: { windowReference?.zoom(nil) }
            )
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Toss")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(SidebarItem.allCases, id: \.self) { item in
                    sidebarButton(for: item)
                }
            }

            Spacer()

            sidebarAuth
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppTheme.sidebarBackground)
                .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 18)
        )
        .padding(.vertical, 0)
        .padding(.horizontal, 0)
    }

    private func sidebarButton(for item: SidebarItem) -> some View {
        let isSelected = selection == item
        return Button {
            if item == .settings {
                showSettings = true
            } else {
                selection = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)

                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .home:
            OnboardingGate()
                .background(AppTheme.windowBackground)
        case .meetings:
            MeetingsListView(repository: meetingRepo, pendingMeetingId: $pendingMeetingId)
        case .settings, .none:
            OnboardingGate()
                .background(AppTheme.windowBackground)
        }
    }

    private var sidebarAuth: some View {
        VStack(alignment: .leading, spacing: 12) {
            if auth.isAuthenticated {
                HStack(spacing: 12) {
                    if let url = auth.userImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: Color.gray.opacity(0.2)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(AppTheme.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.userName ?? "Signed in")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                        if let email = auth.userEmail {
                            Text(email)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }

                    Spacer()

                    Button("Sign out") { auth.signOut() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sign in to Toss")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                    HStack(spacing: 10) {
                        Button {
                            auth.continueWithGoogle()
                        } label: {
                            Label("Google", systemImage: "globe")
                        }
                        Button {
                            auth.continueWithApple()
                        } label: {
                            Label("Apple", systemImage: "applelogo")
                        }
                        Button("Dev token…") { auth.signInDevToken() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .onAppear { Task { await auth.refreshProfile() } }
    }
}

private func configureWindow(_ window: NSWindow) {
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.isMovableByWindowBackground = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titlebarSeparatorStyle = .none
    window.toolbar = nil
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
        titlebarView.isHidden = true
    }
}

private struct WindowReader: NSViewRepresentable {
    var onUpdate: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            onUpdate(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onUpdate(nsView.window)
        }
    }
}

private struct TrafficLightsView: View {
    var onClose: () -> Void
    var onMinimize: () -> Void
    var onZoom: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            trafficButton(color: Color(red: 0.99, green: 0.27, blue: 0.22), action: onClose)
            trafficButton(color: Color(red: 0.99, green: 0.74, blue: 0.22), action: onMinimize)
            trafficButton(color: Color(red: 0.22, green: 0.84, blue: 0.39), action: onZoom)
            Spacer()
        }
        .padding(.top, 4)
        .padding(.leading, 6)
    }

    private func trafficButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

extension Color {
    fileprivate var nsColor: NSColor {
        NSColor(self)
    }
}

@MainActor
struct HomeView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var dictations: [MessageModel] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if dictations.isEmpty {
                    EmptyState()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recent")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                            .textCase(.uppercase)

                        VStack(spacing: 12) {
                            ForEach(dictations.prefix(50)) { message in
                                DictationRow(message: message)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
        .background(AppTheme.windowBackground)
        .onAppear {
            loadHistory()
            // Refresh every 2 seconds to catch new dictations
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                loadHistory()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome back, \(auth.userName ?? "there")")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)
                Text("\(dictations.count) dictation\(dictations.count == 1 ? "" : "s") today")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                loadHistory()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                    .padding(10)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadHistory() {
        let t = History.shared.upsertThread(title: "Quick Dictations")
        dictations = History.shared.listMessages(threadId: t.id).reversed()  // newest first
    }

    private struct EmptyState: View {
        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(AppTheme.secondaryText)
                Text("No dictations yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                Text("Hold your hotkey and speak to create your first dictation.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(AppTheme.subtleStroke, lineWidth: 1)
                    )
            )
        }
    }

    private struct DictationRow: View {
        let message: MessageModel
        @State private var showCopied = false

        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.createdAt, style: .time)
                        .foregroundColor(AppTheme.secondaryText)
                        .font(.system(size: 12, weight: .medium))
                    Text(message.createdAt, style: .date)
                        .foregroundColor(AppTheme.secondaryText.opacity(0.8))
                        .font(.system(size: 11))
                }
                .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            showCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                showCopied = false
                            }
                        } label: {
                            Label(
                                showCopied ? "Copied" : "Copy",
                                systemImage: showCopied ? "checkmark" : "doc.on.doc"
                            )
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(showCopied ? .green : AppTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.elevatedBackground)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppTheme.subtleStroke, lineWidth: 1)
                        )
                )
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    ContentView()
}

struct SettingsView: View {
    @ObservedObject private var ob = OnboardingManager.shared
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        Form {
            Section("Account") {
                if auth.isAuthenticated {
                    HStack {
                        Text(auth.userName ?? "Signed in").font(
                            .system(size: 13, weight: .semibold))
                        Spacer()
                        Button("Sign out") {
                            auth.signOut()
                            ob.refresh()
                        }
                    }
                } else {
                    HStack {
                        Text("Not signed in").foregroundColor(.secondary)
                        Spacer()
                        Button("Sign in") { auth.beginBrowserLogin() }
                    }
                }
            }
            Section("Permissions") {
                permRow(
                    "Accessibility", granted: ob.axGranted,
                    action: {
                        ob.requestAX()
                        ob.openAXSettings()
                    })
                permRow(
                    "Microphone", granted: ob.micGranted,
                    action: {
                        ob.requestMic()
                        ob.openMicSettings()
                    })
            }
        }
        .padding()
        .onAppear { ob.refresh() }
    }

    private func permRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View
    {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundColor(.green)
            } else {
                Button("Allow…", action: action)
            }
        }
    }
}
