import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .settings: return "gear"
        }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selection: SidebarItem? = .home
    @State private var showSettings = false

    var body: some View {
        ZStack {

            NavigationSplitView {
                List(SidebarItem.allCases, id: \.self, selection: $selection) { item in
                    Label(item.title, systemImage: item.systemImage).contentShape(Rectangle())
                        .onTapGesture {
                            if item == .settings {
                                showSettings = true
                            } else {
                                selection = item
                            }
                        }
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Text("Toss").font(.system(size: 16, weight: .semibold))
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    sidebarAuth
                        .padding(12)
                        .background(.bar)
                        .overlay(Divider(), alignment: .top)
                }
            } detail: {
                OnboardingGate()
            }
            .frame(minWidth: 820, minHeight: 520)

            if showSettings {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { showSettings = false }

                SettingsModalView(onClose: { showSettings = false })
                    .frame(width: 760)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
            }
        }.animation(.easeInOut(duration: 0.2), value: showSettings)

    }

    private var sidebarAuth: some View {
        HStack(spacing: 10) {
            if auth.isAuthenticated {
                if let url = auth.userImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.userName ?? "Signed in").font(.system(size: 13, weight: .semibold))
                    if let email = auth.userEmail {
                        Text(email).foregroundColor(.secondary).font(.system(size: 11))
                    }
                }
                Spacer()
                Button("Sign out") { auth.signOut() }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to Toss").font(.system(size: 13, weight: .semibold))
                    HStack {
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
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .onAppear { Task { await auth.refreshProfile() } }
    }
}

@MainActor
struct HomeView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var dictations: [MessageModel] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome back, \(auth.userName ?? "there")")
                            .font(.system(size: 28, weight: .semibold))
                        Text(
                            "\(dictations.count) dictation\(dictations.count == 1 ? "" : "s") today"
                        )
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        loadHistory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                }

                // Today section
                if dictations.isEmpty {
                    EmptyState()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent").font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)

                        VStack(spacing: 12) {
                            ForEach(dictations.prefix(50)) { m in
                                DictationRow(message: m)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.98, blue: 1.0),
                    Color(red: 0.94, green: 0.96, blue: 1.0),
                ]), startPoint: .top, endPoint: .bottom)
        )
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

    private func loadHistory() {
        let t = History.shared.upsertThread(title: "Quick Dictations")
        dictations = History.shared.listMessages(threadId: t.id).reversed()  // newest first
    }

    private struct EmptyState: View {
        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(.secondary)
                Text("No dictations yet")
                    .font(.system(size: 16, weight: .semibold))
                Text("Hold your hotkey and speak to create your first dictation.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
    }

    private struct DictationRow: View {
        let message: MessageModel
        @State private var showCopied = false

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message.createdAt, style: .time)
                        .foregroundColor(.secondary)
                        .font(.system(size: 11, weight: .medium))
                    Text(message.createdAt, style: .date)
                        .foregroundColor(.secondary)
                        .font(.system(size: 10))
                }
                .frame(width: 68, alignment: .leading)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        HStack(alignment: .top, spacing: 12) {
                            Text(message.content)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                                showCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showCopied = false
                                }
                            } label: {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(showCopied ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy to clipboard")
                        }
                        .padding(14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12).stroke(
                            Color.black.opacity(0.06), lineWidth: 1)
                    )
            }
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
