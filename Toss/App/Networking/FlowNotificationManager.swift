import AppKit
import Foundation
import UserNotifications

/// Represents a toast notification to show in-app
struct FlowToast: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let icon: String?
    let isError: Bool
    let timestamp: Date

    static func == (lhs: FlowToast, rhs: FlowToast) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages polling for flow completion and showing notifications
/// Shows in-app toasts when app is focused, system notifications when not
@MainActor
final class FlowNotificationManager: ObservableObject {
    static let shared = FlowNotificationManager()

    /// Active toasts to display in-app (observed by toast overlay view)
    @Published var activeToasts: [FlowToast] = []

    private var pollingTasks: [UUID: Task<Void, Never>] = [:]
    private let pollingInterval: TimeInterval = 3.0  // Poll every 3 seconds
    private let maxPollingDuration: TimeInterval = 120.0  // Stop after 2 minutes

    /// Track flows that are currently running
    private var runningFlows: [String: TriggeredFlow] = [:]

    private init() {
        requestNotificationPermission()
    }

    // MARK: - Public API

    /// Start polling for flow completion for a meeting
    func startPolling(for meetingId: UUID, flows: [TriggeredFlow]) {
        // Cancel any existing polling for this meeting
        pollingTasks[meetingId]?.cancel()

        // Store the flows and show "running" notifications
        for flow in flows {
            runningFlows[flow.id] = flow
            Task {
                await showRunningNotification(for: flow)
            }
        }

        pollingTasks[meetingId] = Task {
            await pollForCompletion(meetingId: meetingId, expectedFlowCount: flows.count)
        }
    }

    /// Stop polling for a specific meeting
    func stopPolling(for meetingId: UUID) {
        pollingTasks[meetingId]?.cancel()
        pollingTasks.removeValue(forKey: meetingId)
    }

    /// Dismiss a toast
    func dismissToast(_ toast: FlowToast) {
        activeToasts.removeAll { $0.id == toast.id }
    }

    /// Dismiss all toasts
    func dismissAllToasts() {
        activeToasts.removeAll()
    }

    // MARK: - Polling Logic

    private func pollForCompletion(meetingId: UUID, expectedFlowCount: Int) async {
        let startTime = Date()
        var completedFlowIds: Set<String> = []

        NSLog(
            "[FlowNotificationManager] Starting to poll for \(expectedFlowCount) flow(s) on meeting \(meetingId)"
        )

        while !Task.isCancelled {
            // Check if we've exceeded max polling duration
            if Date().timeIntervalSince(startTime) > maxPollingDuration {
                NSLog(
                    "[FlowNotificationManager] Max polling duration exceeded for meeting \(meetingId)"
                )
                // Remove any remaining running notifications/toasts
                for flowId in runningFlows.keys {
                    UNUserNotificationCenter.current().removeDeliveredNotifications(
                        withIdentifiers: ["flow-\(flowId)-running"]
                    )
                    activeToasts.removeAll { $0.id == "flow-\(flowId)-running" }
                }
                break
            }

            do {
                let runs = try await FlowsAPI.shared.getMeetingFlowRuns(meetingId: meetingId)

                for run in runs {
                    // Skip runs we've already processed
                    guard !completedFlowIds.contains(run.flowId) else { continue }

                    // Only update for completed or failed runs
                    guard run.status == "completed" || run.status == "failed" else { continue }

                    // Show completion notification
                    await showCompletedNotification(for: run)
                    completedFlowIds.insert(run.flowId)
                    runningFlows.removeValue(forKey: run.flowId)
                }

                // Check if all flows are done
                if completedFlowIds.count >= expectedFlowCount {
                    NSLog(
                        "[FlowNotificationManager] All \(expectedFlowCount) flow(s) completed for meeting \(meetingId)"
                    )
                    break
                }
            } catch {
                NSLog("[FlowNotificationManager] Error polling flows: \(error)")
            }

            // Wait before next poll
            try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }

        pollingTasks.removeValue(forKey: meetingId)
        NSLog("[FlowNotificationManager] Stopped polling for meeting \(meetingId)")
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            granted, error in
            if let error = error {
                NSLog("[FlowNotificationManager] Notification permission error: \(error)")
            } else {
                NSLog("[FlowNotificationManager] Notification permission granted: \(granted)")
            }
        }
    }

    /// Show a "running" notification
    private func showRunningNotification(for flow: TriggeredFlow) async {
        if NSApp.isActive {
            // App is focused - show in-app toast
            let toast = FlowToast(
                id: "flow-\(flow.id)-running",
                title: flow.title,
                message: "Running automation...",
                icon: flow.icon,
                isError: false,
                timestamp: Date()
            )
            activeToasts.append(toast)
            NSLog("[FlowNotificationManager] Showed in-app running toast for flow \(flow.id)")
        } else {
            // App is not focused - show system notification
            let content = UNMutableNotificationContent()
            content.title = "⏳ \(flow.title)"
            content.body = "Running automation..."
            content.sound = nil

            let request = UNNotificationRequest(
                identifier: "flow-\(flow.id)-running",
                content: content,
                trigger: nil
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
                NSLog(
                    "[FlowNotificationManager] Showed system running notification for flow \(flow.id)"
                )
            } catch {
                NSLog("[FlowNotificationManager] Failed to show system notification: \(error)")
            }
        }
    }

    /// Show completion notification
    private func showCompletedNotification(for run: MeetingFlowRun) async {
        // First, clean up the "running" state
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["flow-\(run.flowId)-running"]
        )
        activeToasts.removeAll { $0.id == "flow-\(run.flowId)-running" }

        let flowTitle = run.displayTitle
        let isCompleted = run.status == "completed"

        // For in-app toasts, use clean titles (visual indicators show status)
        // For system notifications, use emoji prefixes
        let inAppTitle = flowTitle
        let systemTitle = isCompleted ? "✓ \(flowTitle)" : "✗ \(flowTitle)"

        let message: String
        if isCompleted {
            if let summary = run.resultSummary, !summary.isEmpty {
                let maxLength = 100
                message =
                    summary.count > maxLength
                    ? String(summary.prefix(maxLength)) + "..."
                    : summary
            } else {
                message = "Completed successfully"
            }
        } else {
            message = run.errorMessage ?? "Flow failed"
        }

        if NSApp.isActive {
            // App is focused - show in-app toast
            let toast = FlowToast(
                id: "flow-\(run.flowId)-completed",
                title: inAppTitle,
                message: message,
                icon: run.flowIcon,
                isError: !isCompleted,
                timestamp: Date()
            )
            activeToasts.append(toast)
            NSLog("[FlowNotificationManager] Showed in-app completion toast for flow \(run.flowId)")

            // Auto-dismiss after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                activeToasts.removeAll { $0.id == toast.id }
            }
        } else {
            // App is not focused - show system notification
            let content = UNMutableNotificationContent()
            content.title = systemTitle
            content.body = message
            content.sound = isCompleted ? .default : .defaultCritical

            let request = UNNotificationRequest(
                identifier: "flow-\(run.flowId)-completed",
                content: content,
                trigger: nil
            )

            do {
                try await UNUserNotificationCenter.current().add(request)
                NSLog(
                    "[FlowNotificationManager] Showed system completion notification for flow \(run.flowId)"
                )
            } catch {
                NSLog("[FlowNotificationManager] Failed to show system notification: \(error)")
            }
        }
    }

    // MARK: - Icon Helpers

    /// Get the SF Symbol name for a flow icon
    static func sfSymbol(for icon: String?) -> String {
        switch icon {
        case "slack":
            return "number.square.fill"
        case "notion":
            return "doc.text.fill"
        case "linear":
            return "checklist"
        case "calendar":
            return "calendar"
        default:
            return "arrow.right.circle.fill"
        }
    }
}
