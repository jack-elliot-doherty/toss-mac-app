//
//  ContentView.swift
//  Alma
//
//  Created by Jack Doherty on 23/10/2025.
//

import SwiftUI
import Foundation

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case dictionary
    case snippets
    case notes
    case integrations
    case settings
    case help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .notes: return "Notes"
        case .integrations: return "Integrations"
        case .settings: return "Settings"
        case .help: return "Help"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "book"
        case .snippets: return "text.badge.plus"
        case .notes: return "note.text"
        case .integrations: return "puzzlepiece.extension"
        case .settings: return "gear"
        case .help: return "questionmark.circle"
        }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .toolbar {
                ToolbarItem(placement: .navigation){ Text("Alma").font(.system(size: 16, weight: .semibold)) }
            }
            .safeAreaInset(edge: .bottom) {
                sidebarAuth
                    .padding(12)
                    .background(.bar)
                    .overlay(Divider(), alignment: .top)
            }
        } detail: {
            Group {
                switch selection ?? .home {
                case .home: HomeView()
                case .dictionary: DictionaryView()
                case .snippets: SnippetsView()
                case .notes: NotesView()
                case .integrations: IntegrationsView()
                case .settings: SettingsView()
                case .help: HelpView()
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
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
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 24)).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.userName ?? "Signed in").font(.system(size: 13, weight: .semibold))
                    if let email = auth.userEmail { Text(email).foregroundColor(.secondary).font(.system(size: 11)) }
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
        .background(LinearGradient(gradient: Gradient(colors: [
            Color(red: 0.96, green: 0.96, blue: 1.0),
            Color(red: 0.90, green: 0.94, blue: 1.0)
        ]), startPoint: .top, endPoint: .bottom))
    }
}

struct DictionaryView: View { var body: some View { Placeholder("Dictionary") } }
struct SnippetsView: View { var body: some View { Placeholder("Snippets") } }
struct NotesView: View { var body: some View { Placeholder("Notes") } }
struct IntegrationsView: View { var body: some View { Placeholder("Integrations") } }
struct SettingsView: View { var body: some View { Placeholder("Settings") } }
struct HelpView: View { var body: some View { Placeholder("Help") } }

private struct Placeholder: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 40, weight: .regular))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    ContentView()
}
