import AppKit
import Foundation
import ServiceManagement
import SwiftUI

// MARK: - Notification Names

extension NSNotification.Name {
    static let openMeetingView = NSNotification.Name("OpenMeetingView")
    static let showSettings = NSNotification.Name("ShowSettings")
    static let globalEscapePressed = NSNotification.Name("GlobalEscapePressed")
    static let resumeMeetingRecording = NSNotification.Name("ResumeMeetingRecording")
}

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
    var meetingActionsId: UUID?  // When set, shows meeting-specific share/delete actions
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
    case meetings
    case flows
    case integrations
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meetings: return "Meetings"
        case .flows: return "Flows"
        case .integrations: return "Integrations"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .meetings: return "mic.fill"
        case .flows: return "command"
        case .integrations: return "square.stack.3d.down.right.fill"
        case .settings: return "gear"
        }
    }
}

@MainActor
struct MainAppView: View {
    @ObservedObject private var auth = AuthManager.shared
    // NOTE: Removed unused @ObservedObject subscription - it was causing unnecessary re-renders
    @ObservedObject private var updateManager = UpdateManager.shared
    @EnvironmentObject private var meetingRepository: PersistentMeetingRepository
    @State private var selection: SidebarItem? = .meetings
    @State private var isSettingsMode = false
    @State private var settingsSection: SettingsModalView.Section = .myAccount
    @State private var previousSelection: SidebarItem? = .meetings
    @State private var settingsSectionHistory: [SettingsModalView.Section] = [.myAccount]
    @State private var settingsHistoryIndex: Int = 0
    @State private var showCommandPalette = false
    @State private var pendingMeetingId: UUID?  // used to switch to the currently recording meeting
    @State private var windowReference: NSWindow?
    @State private var navigationHistory: [SidebarItem] = [.meetings]
    @State private var meetingsNavigationPath = NavigationPath()
    @State private var historyIndex: Int = 0
    @State private var showUserMenu = false
    @State private var showPaywall = false
    @State private var showCreateWorkspace = false
    @State private var switchingToOrgId: String?  // Track which org we're switching to (prevents race condition)
    @StateObject private var commandPaletteViewModel = CommandPaletteViewModel()
    @StateObject private var pageChrome = AppScreenLayout(
        initialState: AppScreenLayoutState(
            breadcrumb: [Breadcrumb(title: "Calls")],
            action: nil
        )
    )

    var body: some View {
        let _ = NSLog("[MainAppView] body START")

        GeometryReader { geometry in
            let shouldCollapse = geometry.size.width < 700  // Adjust this threshold as needed

            ZStack {
                AppGlassBackground()

                HStack(alignment: .top, spacing: 16) {
                    if !shouldCollapse {
                        sidebar
                            .frame(width: 238)
                            .padding(8)
                    }
                    detailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .frame(minWidth: 300, minHeight: 400)
                .animation(.easeInOut(duration: 0.25), value: shouldCollapse)


                // Command Palette
                if showCommandPalette {
                    CommandPaletteOverlayWrapper(
                        viewModel: commandPaletteViewModel,
                        onDismiss: { dismissCommandPalette() }
                    )
                    // Note: Escape key handling is done via GlobalEscapePressed notification from HotkeyEventTap
                }

                // Force Update Modal (non-dismissible)
                if updateManager.forceUpdateRequired {
                    ZStack {
                        // Blocking scrim - no dismiss action
                        Color.black.opacity(0.6)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ForceUpdateModal(updateManager: updateManager)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .transition(.opacity)
                }

                // Create Workspace Wizard (full-screen)
                if showCreateWorkspace {
                    CreateWorkspaceView(
                        onComplete: {
                            showCreateWorkspace = false
                        },
                        onCancel: {
                            showCreateWorkspace = false
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .overlay(FlowToastOverlay())

            .environmentObject(pageChrome)
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.2), value: isSettingsMode)
            .animation(.spring(response: 0.25, dampingFraction: 0.88), value: showCommandPalette)
            .background(CommandKListener(onTrigger: { openCommandPalette() }))
            .background(WindowFinder(window: $windowReference))
            .onAppear {
                updateChromeForCurrentSelection()
                setupCommandPaletteCallbacks()
            }
            .onChange(of: selection) { _ in
                updateChromeForCurrentSelection()
            }
            .onChange(of: isSettingsMode) { _ in
                updateChromeForCurrentSelection()
            }
            .onChange(of: settingsSection) { _ in
                updateChromeForCurrentSelection()
            }
            .onChange(of: updateManager.updateAvailable) { newValue in
                NSLog("[MainAppView] updateAvailable changed to: \(newValue), version: \(updateManager.latestVersion ?? "nil")")
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openMeetingView)
            ) { notification in
                if let userInfo = notification.userInfo,
                    let meetingId = userInfo["meetingId"] as? UUID
                {
                    selectSidebarItem(.meetings)
                    pendingMeetingId = meetingId
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .showSettings)
            ) { _ in
                enterSettingsMode()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .globalEscapePressed)
            ) { _ in
                if showCommandPalette {
                    dismissCommandPalette()
                } else if isSettingsMode {
                    exitSettingsMode()
                }
            }
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

            if isSettingsMode {
                // Settings mode: Back button and settings navigation
                settingsBackButton
                    .padding(.bottom, 6)

                settingsSidebarNav

            } else {
                // Normal mode: App title and main navigation
                VStack(alignment: .leading, spacing: 4) {
                    Text("Toss")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                }
                .padding(.bottom, 4)

                // Search button
                searchButton
                    .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SidebarItem.allCases.filter { $0 != .settings }, id: \.self) { item in
                        sidebarButton(for: item)
                    }
                }
            }

            Spacer()

            // Only show these when NOT in settings mode
            if !isSettingsMode {
                // Update available notification
                if updateManager.updateAvailable {
                    let _ = NSLog("[Sidebar] Showing update banner - version: \(updateManager.latestVersion ?? "unknown")")
                    updateAvailableBanner
                        .padding(.bottom, 8)
                }

                // Settings at bottom
                sidebarButton(for: .settings)

                // Contact founder button
                contactFounderButton
                    .padding(.bottom, 4)

                sidebarAuth
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .padding(.horizontal, 8)
        .appGlass(.surface, radius: 10)
    }

    private var settingsBackButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSettingsMode = false
                selection = previousSelection
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text("Back to app")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundColor(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsSidebarNav: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(SettingsModalView.SectionGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .padding(.horizontal, 12)

                    VStack(spacing: 2) {
                        ForEach(group.sections) { section in
                            settingsSectionButton(for: section)
                        }
                    }
                }
            }
        }
    }

    private func settingsSectionButton(for section: SettingsModalView.Section) -> some View {
        let isSelected = settingsSection == section
        return Button {
            selectSettingsSection(section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchButton: some View {
        Button {
            openCommandPalette()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Text("Search")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Spacer()

                Text("⌘K")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var contactFounderButton: some View {
        Button {
            if let url = URL(string: "https://wa.me/353862702345") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Text("Share Feedback")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var updateAvailableBanner: some View {
        Button {
            updateManager.installUpdate()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Title row
                HStack {
                    Text("Update available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    if let version = updateManager.latestVersion {
                        Text("v\(version)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                // Description
                Text("A new version of Toss is available with the latest features and fixes.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(2)

                // Update button - full width, white
                Text("Update now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
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
        if isSettingsMode {
            SettingsContentView(section: $settingsSection)
        } else {
            switch selection {
            case .meetings:
                MeetingsListView(
                    repository: meetingRepository, pendingMeetingId: $pendingMeetingId,
                    navigationPath: $meetingsNavigationPath)
            case .flows:
                FlowsView()
            case .integrations:
                IntegrationsView()
            case .settings, .none:
                OnboardingGate()
            }
        }
    }

    private var pageHeader: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .overlay(alignment: .leading) {
                HStack(spacing: 16) {
                    navigationControls
                    breadcrumbView
                }
            }
            .overlay(alignment: .trailing) {
                pageHeaderActions
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var pageHeaderActions: some View {
        if let meetingId = pageChrome.state.meetingActionsId {
            MeetingChromeActions(
                meetingId: meetingId,
                repository: meetingRepository,
                onDelete: {
                    // Navigate back after delete
                    if !meetingsNavigationPath.isEmpty {
                        meetingsNavigationPath.removeLast()
                    }
                }
            )
        } else if let action = pageChrome.state.action {
            AppScreenActionButton(action: action)
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
                        index == crumbs.count - 1 ? AppTheme.primaryText : AppTheme.secondaryText
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func defaultActionForSelection() -> AppScreenAction? {
        // No action button in settings mode
        guard !isSettingsMode else { return nil }
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
            enterSettingsMode()
        } else {
            selectSidebarItem(item)
        }
    }

    private func enterSettingsMode() {
        previousSelection = selection
        // Reset settings history when entering
        settingsSectionHistory = [.myAccount]
        settingsHistoryIndex = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            isSettingsMode = true
            settingsSection = .myAccount
        }
    }

    private func exitSettingsMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSettingsMode = false
            selection = previousSelection
        }
    }

    private func selectSettingsSection(_ section: SettingsModalView.Section) {
        guard settingsSection != section else { return }

        // Truncate forward history if we're not at the end
        if settingsHistoryIndex < settingsSectionHistory.count - 1 {
            settingsSectionHistory = Array(settingsSectionHistory.prefix(settingsHistoryIndex + 1))
        }

        // Add to history
        settingsSectionHistory.append(section)
        settingsHistoryIndex = settingsSectionHistory.count - 1
        settingsSection = section
    }

    private func selectSidebarItem(_ item: SidebarItem, pushToHistory: Bool = true) {
        // Reset navigation path when clicking Meetings (even if already selected)
        if item == .meetings && !meetingsNavigationPath.isEmpty {
            // Pop all items explicitly - more reliable than assigning new NavigationPath()
            meetingsNavigationPath.removeLast(meetingsNavigationPath.count)
            return  // Already on meetings, just needed to pop back to list
        }

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
        if isSettingsMode {
            // In settings mode, can go back if there's section history or can exit to app
            return settingsHistoryIndex > 0 || true  // Always can go back to exit settings
        }
        if selection == .meetings && !meetingsNavigationPath.isEmpty { return true }
        return historyIndex > 0
    }

    private var canGoForward: Bool {
        if isSettingsMode {
            return settingsHistoryIndex < settingsSectionHistory.count - 1
        }
        return historyIndex < navigationHistory.count - 1
    }

    private var currentPageTitle: String {
        if isSettingsMode {
            return settingsSection.title
        }
        switch selection {
        case .meetings:
            return "Calls"
        case .flows:
            return "Flows"
        case .integrations:
            return "Integrations"
        case .settings:
            return "Settings"
        case .none:
            return ""
        }
    }

    private func navigateBack() {
        if isSettingsMode {
            if settingsHistoryIndex > 0 {
                // Go back in settings history
                settingsHistoryIndex -= 1
                settingsSection = settingsSectionHistory[settingsHistoryIndex]
            } else {
                // Exit settings mode
                exitSettingsMode()
            }
            return
        }
        if selection == .meetings && !meetingsNavigationPath.isEmpty {
            meetingsNavigationPath.removeLast()
            return
        }
        guard canGoBack else { return }
        historyIndex -= 1
        selection = navigationHistory[historyIndex]
    }

    private func navigateForward() {
        if isSettingsMode {
            guard settingsHistoryIndex < settingsSectionHistory.count - 1 else { return }
            settingsHistoryIndex += 1
            settingsSection = settingsSectionHistory[settingsHistoryIndex]
            return
        }
        guard canGoForward else { return }
        historyIndex += 1
        selection = navigationHistory[historyIndex]
    }

    // MARK: - Command Palette

    private func openCommandPalette() {
        guard !isSettingsMode else { return }
        commandPaletteViewModel.reset()
        showCommandPalette = true
    }

    private func dismissCommandPalette() {
        showCommandPalette = false
    }

    private func setupCommandPaletteCallbacks() {
        commandPaletteViewModel.onNavigate = { [weak self] item in
            guard let self else { return }
            if item == .settings {
                enterSettingsMode()
            } else {
                if isSettingsMode {
                    exitSettingsMode()
                }
                selectSidebarItem(item)
            }
        }

        commandPaletteViewModel.onDismiss = { [weak self] in
            self?.dismissCommandPalette()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 12) {
            pageHeader
                .frame(maxWidth: .infinity)
            contentView
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()  // Prevent content from overflowing when window shrinks
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 0)
    }

    private var sidebarAuth: some View {
        Group {
            if auth.isAuthenticated {
                userCardButton
                    .popover(isPresented: $showUserMenu, arrowEdge: .top) {
                        userMenuPopover
                    }
            }
        }
        .onAppear { Task { await auth.refreshProfile() } }
    }

    private var userMenuPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User header
            HStack(spacing: 10) {
                // User avatar
                if let url = auth.userImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.userName ?? "Signed in")
                        .font(.system(size: 14, weight: .semibold))
                    if let memberCount = teamMemberCount {
                        Text("\(memberCount) member\(memberCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)

            // Invite teammates button (if admin)
            if auth.currentOrg?.isAdmin == true {
                Button(action: {
                    showUserMenu = false
                    // Open settings to members pane
                    previousSelection = selection
                    isSettingsMode = true
                    settingsSection = .members
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                        Text("Invite teammates")
                            .font(.system(size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()

            // User email
            if let email = auth.userEmail {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Divider()
            }

            // Organization list
            if !auth.organizations.isEmpty {
                ForEach(auth.organizations) { org in
                    Button(action: {
                        if org.id != auth.currentOrg?.id && switchingToOrgId == nil {
                            Task {
                                switchingToOrgId = org.id
                                do {
                                    try await auth.switchOrganization(to: org.id)
                                } catch {
                                    NSLog("[MainAppView] Failed to switch org: \(error)")
                                }
                                switchingToOrgId = nil
                            }
                        }
                        showUserMenu = false
                    }) {
                        HStack(spacing: 10) {
                            // Workspace icon/avatar
                            workspaceIcon(for: org)

                            Text(org.name)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)

                            Spacer()

                            // Loading indicator when switching to this org
                            if switchingToOrgId == org.id {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 16, height: 16)
                            } else if org.id == auth.currentOrg?.id {
                                // Checkmark for active org
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(switchingToOrgId != nil || org.id == auth.currentOrg?.id)
                }

                // Add workspace button
                Button(action: {
                    showUserMenu = false
                    showCreateWorkspace = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                        Text("Add workspace")
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
            }

            // Settings button
            Button(action: {
                showUserMenu = false
                enterSettingsMode()
            }) {
                HStack {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("Settings")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\u{2318},")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // Logout button
            Button(action: {
                showUserMenu = false
                auth.signOut(reason: "user clicked logout in user menu")
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 13))
                    Text("Logout")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 240)
    }

    private func workspaceIcon(for org: Organization) -> some View {
        let initial = org.name.prefix(1).uppercased()
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.15))
            Text(initial)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .frame(width: 20, height: 20)
    }

    // Computed property for member count (from current org context)
    private var teamMemberCount: Int? {
        // This will be populated when we have the actual member count
        // For now, return 1 as minimum
        return max(1, auth.organizations.count)
    }

    private var userCardButton: some View {
        Button(action: { showUserMenu.toggle() }) {
            HStack(spacing: 10) {
                // User Avatar
                if let url = auth.userImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(AppTheme.secondaryText)
                }

                // User name + email
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.userName ?? "Signed in")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(1)

                    if let email = auth.userEmail {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.elevatedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppTheme.subtleStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Command K Listener

private struct CommandKListener: NSViewRepresentable {
    let onTrigger: () -> Void

    func makeNSView(context: Context) -> CommandKMonitorView {
        let view = CommandKMonitorView()
        view.onCommandK = onTrigger
        return view
    }

    func updateNSView(_ nsView: CommandKMonitorView, context: Context) {
        nsView.onCommandK = onTrigger
    }

    class CommandKMonitorView: NSView {
        var onCommandK: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window != nil && monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    // Check for Command + K (keyCode 40 is 'K')
                    if event.modifierFlags.contains(.command) && event.keyCode == 40 {
                        self?.onCommandK?()
                        return nil  // Consume the event
                    }
                    return event
                }
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)

            if newWindow == nil, let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
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

// MARK: - Window Finder

/// Captures a reference to the hosting NSWindow and passes it back via a binding
private struct WindowFinder: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window == nil {
            DispatchQueue.main.async {
                self.window = nsView.window
            }
        }
    }
}

extension Color {
    fileprivate var nsColor: NSColor {
        NSColor(self)
    }
}

// MARK: - Meeting Chrome Actions

struct MeetingChromeActions: View {
    let meetingId: UUID
    @ObservedObject var repository: PersistentMeetingRepository
    let onDelete: () -> Void

    private var meeting: MeetingModel? {
        repository.getMeeting(id: meetingId)
    }

    private var isRecording: Bool {
        meeting?.endTime == nil
    }

    var body: some View {
        HStack(spacing: 8) {
            // Share dropdown
            Menu {
                Button(action: copyShareLink) {
                    Label("Copy link", systemImage: "link")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .medium))
                    Text("Share")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .foregroundColor(AppTheme.primaryText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()  // Preserve intrinsic size in release builds

            // Ellipsis menu
            Menu {
                if !isRecording {
                    Button(action: resumeRecording) {
                        Label("Resume", systemImage: "mic.fill")
                    }
                }

                Divider()

                Button(role: .destructive, action: deleteMeetingWithConfirmation) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()  // Preserve intrinsic size in release builds
        }
        .fixedSize()  // Ensure HStack doesn't collapse in overlay
    }

    private func copyShareLink() {
        Task {
            do {
                await MeetingSyncManager.shared.syncMeeting(meetingId)
                let shareUrl = try await MeetingsApi.shared.generateShareLink(meetingId: meetingId)
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(shareUrl, forType: .string)
                }
                NSLog("[MeetingChromeActions] Copied share link: \(shareUrl)")
            } catch {
                NSLog("[MeetingChromeActions] Failed to copy share link: \(error)")
            }
        }
    }

    private func resumeRecording() {
        NSLog("[MeetingChromeActions] Resume recording for meeting: \(meetingId)")
        NotificationCenter.default.post(
            name: .resumeMeetingRecording,
            object: nil,
            userInfo: ["meetingId": meetingId]
        )
    }

    private func deleteMeetingWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Delete this call?"
        alert.informativeText = "This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            repository.deleteMeeting(id: meetingId)
            Task { await MeetingSyncManager.shared.deleteMeetingFromServer(meetingId) }
            NSLog("[MeetingChromeActions] Deleted meeting: \(meetingId)")
            onDelete()
        }
    }
}

#Preview {
    MainAppView()
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
                            auth.signOut(reason: "user clicked sign out in settings")
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
