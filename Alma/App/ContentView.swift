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
                        Text("Alma").font(.system(size: 16, weight: .semibold))
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
                    Text("Sign in to Alma").font(.system(size: 13, weight: .semibold))
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

// MARK: - Placeholder Views
struct HomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome back")
                .font(.system(size: 24, weight: .semibold))
            Text("Hold down the hotkey to dictate in any app.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.96, green: 0.96, blue: 1.0),
                    Color(red: 0.90, green: 0.94, blue: 1.0),
                ]), startPoint: .top, endPoint: .bottom))
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
