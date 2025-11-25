import AppKit
import Foundation
import ServiceManagement
import SwiftUI

struct Breadcrumb: Identifiable, Equatable {
    let id = UUID()
    let title: String
}

struct AppScreenAction {
    let title: String
    let systemImage: String?
    let handler: () -> Void
}

struct AppScreenLayoutState {
    var breadcrumb: [Breadcrumb]
    var action: AppScreenAction?
}

final class AppScreenLayout: ObservableObject {
    @Published private(set) var state: AppScreenLayoutState
    private var defaultState: AppScreenLayoutState
    private var isOverrideActive = false

    init(initialState: AppScreenLayoutState) {
        self.state = initialState
        self.defaultState = initialState
    }

    func setDefault(_ state: AppScreenLayoutState) {
        defaultState = state
        if !isOverrideActive {
            self.state = state
        }
    }

    func override(with state: AppScreenLayoutState) {
        isOverrideActive = true
        self.state = state
    }

    func clearOverride() {
        isOverrideActive = false
        self.state = defaultState
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case meetings
    case activity
    case integrations
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .meetings: return "Meetings"
        case .activity: return "Activity"
        case .integrations: return "Integrations"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .meetings: return "mic.fill"
        case .activity: return "clock.fill"
        case .integrations: return "square.stack.3d.down.right.fill"
        case .settings: return "gear"
        }
    }
}

@MainActor
struct ContentView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject private var meetingRepository: PersistentMeetingRepository
    @State private var selection: SidebarItem? = .home
    @State private var showSettings = false
    @State private var pendingMeetingId: UUID?  // used to switch to the currently recording meeting
    @State private var windowReference: NSWindow?
    @State private var navigationHistory: [SidebarItem] = [.home]
    @State private var meetingsNavigationPath = NavigationPath()
    @State private var historyIndex: Int = 0
    @StateObject private var pageChrome = AppScreenLayout(
        initialState: AppScreenLayoutState(
            breadcrumb: [Breadcrumb(title: "Overview")],
            action: nil
        )
    )

    @ObservedObject private var onboarding = OnboardingManager.shared

    var body: some View {
        if onboarding.needsOnboarding {
            OnboardingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.windowBackground)
        } else {
            main
        }
    }

    var main: some View {
        ZStack {
            AppGlassBackground()

            HStack(alignment: .top, spacing: 16) {
                sidebar
                    .frame(width: 238)
                    .padding(8)

                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .frame(minWidth: 750, minHeight: 600)

            if showSettings {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { showSettings = false }

                SettingsModalView(onClose: { showSettings = false })
                    .frame(width: 760)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(1)
                    .appGlass(.surface, radius: 24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )

        .environmentObject(pageChrome)
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
        .onAppear {
            updateChromeForCurrentSelection()
        }
        .onChange(of: selection) { _ in
            updateChromeForCurrentSelection()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name("OpenMeetingView"))
        ) { notification in
            if let userInfo = notification.userInfo,
                let meetingId = userInfo["meetingId"] as? UUID
            {
                selectSidebarItem(.meetings)
                pendingMeetingId = meetingId
            }
        }
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
                ForEach(SidebarItem.allCases.filter { $0 != .settings }, id: \.self) { item in
                    sidebarButton(for: item)
                }
            }

            Spacer()
            // Settings at bottom
            sidebarButton(for: .settings)
                .padding(.bottom, 4)

            sidebarAuth
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .appGlass(.surface, radius: 10)
    }

    private func sidebarButton(for item: SidebarItem) -> some View {
        let isSelected = selection == item
        return Button {
            handleSelectionTap(item)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var navigationControls: some View {
        HStack(spacing: 8) {
            navButton(systemName: "chevron.left", enabled: canGoBack) {
                navigateBack()
            }

            navButton(systemName: "chevron.right", enabled: canGoForward) {
                navigateForward()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selection {
        case .home:
            HomeView(
                onViewAllDictations: { selectSidebarItem(.activity) },
                onViewAllMeetings: { selectSidebarItem(.meetings) }
            )
        case .meetings:
            MeetingsListView(
                repository: meetingRepository, pendingMeetingId: $pendingMeetingId,
                navigationPath: $meetingsNavigationPath)
        case .activity:
            EmptyView()
        // ActivityView()
        case .integrations:
            EmptyView()
        // IntegrationsView()
        case .settings, .none:
            OnboardingGate()
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 16) {
            navigationControls

            breadcrumbView

            Spacer()

            if let action = pageChrome.state.action {
                AppScreenActionButton(action: action)
            }
        }
    }

    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(
                    enabled ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.5)
                )
                .frame(width: 30, height: 30)
                .appGlass(.chrome, radius: 15)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var breadcrumbView: some View {
        HStack(spacing: 6) {
            let crumbs = pageChrome.state.breadcrumb
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                }
                Text(crumb.title)
                    .font(
                        .system(size: 16, weight: index == crumbs.count - 1 ? .semibold : .regular)
                    )
                    .foregroundColor(
                        index == crumbs.count - 1 ? AppTheme.primaryText : AppTheme.secondaryText)
            }
        }
    }

    private func defaultActionForSelection() -> AppScreenAction? {
        guard selection == .meetings else { return nil }
        return AppScreenAction(title: "Record", systemImage: "plus") {
            NotificationCenter.default.post(name: .requestMeetingRecording, object: nil)
        }
    }

    private func updateChromeForCurrentSelection() {
        let state = AppScreenLayoutState(
            breadcrumb: [Breadcrumb(title: currentPageTitle)],
            action: defaultActionForSelection()
        )
        pageChrome.setDefault(state)
    }

    private struct AppScreenActionButton: View {
        let action: AppScreenAction

        var body: some View {
            Button {
                action.handler()
            } label: {
                HStack(spacing: 6) {
                    if let systemImage = action.systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(action.title)
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .appGlass(.chrome, radius: 16)
                .foregroundColor(AppTheme.primaryText)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var recordButton: some View {
        Button {
            NotificationCenter.default.post(name: .requestMeetingRecording, object: nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Record")
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .appGlass(.chrome, radius: 16)
            .foregroundColor(AppTheme.primaryText)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func handleSelectionTap(_ item: SidebarItem) {
        if item == .settings {
            showSettings = true
        } else {
            selectSidebarItem(item)
        }
    }

    private func selectSidebarItem(_ item: SidebarItem, pushToHistory: Bool = true) {
        guard selection != item else { return }
        selection = item
        if pushToHistory {
            if historyIndex < navigationHistory.count - 1 {
                navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
            }
            navigationHistory.append(item)
            historyIndex = navigationHistory.count - 1
        }
    }

    private var canGoBack: Bool {
        if selection == .meetings && !meetingsNavigationPath.isEmpty { return true }
        return historyIndex > 0
    }

    private var canGoForward: Bool {
        return historyIndex < navigationHistory.count - 1
    }

    private var currentPageTitle: String {
        switch selection {
        case .home:
            return "Overview"
        case .meetings:
            return "Calls"
        case .activity:
            return "Activity"
        case .integrations:
            return "Integrations"
        case .settings:
            return "Settings"
        case .none:
            return ""
        }
    }

    private func navigateBack() {
        if selection == .meetings && !meetingsNavigationPath.isEmpty {
            meetingsNavigationPath.removeLast()
            return
        }
        guard canGoBack else { return }
        historyIndex -= 1
        selection = navigationHistory[historyIndex]
    }

    private func navigateForward() {
        guard canGoForward else { return }
        historyIndex += 1
        selection = navigationHistory[historyIndex]
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            pageHeader
            contentView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }

    private var sidebarAuth: some View {
        VStack(alignment: .leading, spacing: 10) {
            if auth.isAuthenticated {
                HStack(spacing: 10) {
                    // Avatar
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
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(AppTheme.secondaryText)
                    }

                    // Name + email (single-line, truncated)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auth.userName ?? "Signed in")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let email = auth.userEmail {
                            Text(email)
                                .font(.system(size: 11))
                                .foregroundColor(AppTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    // Compact sign-out icon
                    Button(action: { auth.signOut() }) {
                        Image(systemName: "arrow.right.square")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.accent)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.elevatedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
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

    @EnvironmentObject private var meetingRepository: PersistentMeetingRepository
    @State private var recentMeetings: [MeetingModel] = []

    // Callbacks you can later wire to "Activity" and "Calls"
    var onViewAllDictations: () -> Void = {}
    var onViewAllMeetings: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                // QuickActionsCard()

                LastDictationSection(
                    last: dictations.first,
                    onViewAll: onViewAllDictations
                )

                RecentMeetingsSection(
                    meetings: Array(recentMeetings.prefix(3)),
                    onViewAll: onViewAllMeetings
                )
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
        .onAppear {
            loadHistory()
            loadMeetings()
            // Refresh dictations every 2 seconds to catch new ones
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                loadHistory()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
        }
        .onReceive(meetingRepository.objectWillChange) { _ in
            loadMeetings()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Good afternoon, \(auth.userName ?? "there")")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text("Toss is ready. Hold Fn to dictate, or ⌘ Fn for your agent.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()
        }
    }

    private func loadHistory() {
        let t = History.shared.upsertThread(title: "Quick Dictations")
        dictations = History.shared.listMessages(threadId: t.id).reversed()  // newest first
    }

    private func loadMeetings() {
        recentMeetings = meetingRepository.listMeetings()
    }

    // MARK: - Sections

    private struct QuickActionsCard: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Quick Actions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                    Spacer()
                    Button {
                        // TODO: wire up to a nice “try a test command” action
                    } label: {
                        HStack(spacing: 6) {
                            Text("Try a test command")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .appGlass(.chrome, radius: 18)
                    }
                    .buttonStyle(.plain)
                }

                Text("Try selecting some text and asking Toss to rewrite it.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(18)
            .appGlass(.card, radius: 20)
        }
    }

    private struct LastDictationSection: View {
        let last: MessageModel?
        let onViewAll: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last dictation")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .textCase(.uppercase)
                    Spacer()
                    Button("View all", action: onViewAll)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .buttonStyle(.plain)
                }

                if let last {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(last.content)
                            .font(.system(size: 15))
                            .foregroundColor(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Text(last.createdAt, style: .time)
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.secondaryText)

                            Text("Auto‑saved")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.secondaryText.opacity(0.8))

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(last.content, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.elevatedBackground)
                            .cornerRadius(10)
                        }
                    }
                    .padding(18)
                    .appGlass(.card, radius: 20)
                } else {
                    Text("No dictations yet. Hold your hotkey and speak to create your first one.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
    }

    private struct RecentMeetingsSection: View {
        let meetings: [MeetingModel]
        let onViewAll: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent meetings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .textCase(.uppercase)
                    Spacer()
                    Button("View all", action: onViewAll)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .buttonStyle(.plain)
                }

                if meetings.isEmpty {
                    Text("No meetings recorded yet.")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                } else {
                    VStack(spacing: 10) {
                        ForEach(meetings) { meeting in
                            MeetingRow(meeting: meeting)
                        }
                    }
                }
            }
        }

        private struct MeetingRow: View {
            let meeting: MeetingModel

            var body: some View {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(AppTheme.elevatedBackground)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title.isEmpty ? "Untitled meeting" : meeting.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)

                        HStack(spacing: 12) {
                            Text(meeting.startTime, style: .time)
                            if let end = meeting.endTime {
                                let minutes = Int(end.timeIntervalSince(meeting.startTime) / 60)
                                Text("\(minutes)m")
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                    }

                    Spacer()
                }
                .padding(14)
                .appGlass(.card, radius: 18)
            }
        }
    }
}

// @MainActor
// struct HomeView: View {
//     @ObservedObject private var auth = AuthManager.shared
//     @State private var dictations: [MessageModel] = []
//     @State private var refreshTimer: Timer?

//     var body: some View {
//         ScrollView {
//             VStack(alignment: .leading, spacing: 28) {
//                 header

//                 if dictations.isEmpty {
//                     EmptyState()
//                 } else {
//                     VStack(alignment: .leading, spacing: 14) {
//                         Text("Recent")
//                             .font(.system(size: 13, weight: .semibold))
//                             .foregroundColor(AppTheme.secondaryText)
//                             .textCase(.uppercase)

//                         VStack(spacing: 12) {
//                             ForEach(dictations.prefix(50)) { message in
//                                 DictationRow(message: message)
//                             }
//                         }
//                     }
//                 }
//             }
//             .padding(.horizontal, 32)
//             .padding(.vertical, 32)
//         }
//         .onAppear {
//             loadHistory()
//             // Refresh every 2 seconds to catch new dictations
//             refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
//                 loadHistory()
//             }
//         }
//         .onDisappear {
//             refreshTimer?.invalidate()
//         }
//     }

//     private var header: some View {
//         HStack(alignment: .center) {
//             VStack(alignment: .leading, spacing: 6) {
//                 Text("Welcome back, \(auth.userName ?? "there")")
//                     .font(.system(size: 26, weight: .bold))
//                     .foregroundColor(AppTheme.primaryText)
//                 Text("\(dictations.count) dictation\(dictations.count == 1 ? "" : "s") today")
//                     .font(.system(size: 14))
//                     .foregroundColor(AppTheme.secondaryText)
//             }

//             Spacer()

//             Button {
//                 loadHistory()
//             } label: {
//                 Image(systemName: "arrow.clockwise")
//                     .font(.system(size: 14, weight: .semibold))
//                     .foregroundColor(AppTheme.primaryText)
//                     .padding(10)
//                     .background(AppTheme.cardBackground)
//                     .cornerRadius(12)
//             }
//             .buttonStyle(.plain)
//         }
//     }

//     private func loadHistory() {
//         let t = History.shared.upsertThread(title: "Quick Dictations")
//         dictations = History.shared.listMessages(threadId: t.id).reversed()  // newest first
//     }

//     private struct EmptyState: View {
//         var body: some View {
//             VStack(spacing: 10) {
//                 Image(systemName: "waveform")
//                     .font(.system(size: 32, weight: .regular))
//                     .foregroundColor(AppTheme.secondaryText)
//                 Text("No dictations yet")
//                     .font(.system(size: 16, weight: .semibold))
//                     .foregroundColor(AppTheme.primaryText)
//                 Text("Hold your hotkey and speak to create your first dictation.")
//                     .font(.system(size: 13))
//                     .foregroundColor(AppTheme.secondaryText)
//                     .multilineTextAlignment(.center)
//             }
//             .frame(maxWidth: .infinity)
//             .padding(.vertical, 60)
//             .appGlass(.card, radius: 24)
//         }
//     }

//     private struct DictationRow: View {
//         let message: MessageModel
//         @State private var showCopied = false

//         var body: some View {
//             HStack(alignment: .top, spacing: 16) {
//                 VStack(alignment: .leading, spacing: 4) {
//                     Text(message.createdAt, style: .time)
//                         .foregroundColor(AppTheme.secondaryText)
//                         .font(.system(size: 12, weight: .medium))
//                     Text(message.createdAt, style: .date)
//                         .foregroundColor(AppTheme.secondaryText.opacity(0.8))
//                         .font(.system(size: 11))
//                 }
//                 .frame(width: 70, alignment: .leading)

//                 VStack(alignment: .leading, spacing: 12) {
//                     Text(message.content)
//                         .font(.system(size: 15))
//                         .foregroundColor(AppTheme.primaryText)
//                         .fixedSize(horizontal: false, vertical: true)

//                     HStack(spacing: 10) {
//                         Button {
//                             NSPasteboard.general.clearContents()
//                             NSPasteboard.general.setString(message.content, forType: .string)
//                             showCopied = true
//                             DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
//                                 showCopied = false
//                             }
//                         } label: {
//                             Label(
//                                 showCopied ? "Copied" : "Copy",
//                                 systemImage: showCopied ? "checkmark" : "doc.on.doc"
//                             )
//                             .font(.system(size: 12, weight: .medium))
//                             .foregroundColor(showCopied ? .green : AppTheme.secondaryText)
//                             .padding(.horizontal, 12)
//                             .padding(.vertical, 6)
//                             .background(AppTheme.elevatedBackground)
//                             .cornerRadius(10)
//                         }
//                         .buttonStyle(.plain)
//                         .help("Copy to clipboard")
//                     }
//                 }
//                 .frame(maxWidth: .infinity, alignment: .leading)
//                 .padding(18)
//                 .appGlass(.card, radius: 20)
//             }
//             .padding(.vertical, 4)
//         }
//     }
// }

#Preview {
    ContentView()
}

struct SettingsView: View {
    @StateObject private var launchAtLogin = LaunchAtLogin.shared
    @ObservedObject private var ob = OnboardingManager.shared
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin.isEnabled)
            }
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
