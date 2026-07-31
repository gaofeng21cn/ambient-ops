import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class LiveActivityController {
    private(set) var isActive = false
    private(set) var errorMessage: String?

    init() {
        refreshState()
    }

    func refreshState() {
        isActive = !Activity<LoadActivityAttributes>.activities.isEmpty
    }

    func start(status: AmbientStatus, machine: MachineStatus) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = String(localized: "Live Activities are disabled in system settings.")
            return
        }
        await end()
        do {
            let attributes = LoadActivityAttributes(
                instanceId: status.instanceId,
                siteName: status.site.name,
                machineId: machine.machineId
            )
            let content = ActivityContent(
                state: LoadActivityAttributes.ContentState(machine: machine),
                staleDate: .now.addingTimeInterval(90)
            )
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            errorMessage = nil
            refreshState()
        } catch {
            errorMessage = error.localizedDescription
            refreshState()
        }
    }

    func update(status: AmbientStatus, machine: MachineStatus) async {
        let content = ActivityContent(
            state: LoadActivityAttributes.ContentState(machine: machine),
            staleDate: .now.addingTimeInterval(90)
        )
        for activity in Activity<LoadActivityAttributes>.activities
        where activity.attributes.instanceId == status.instanceId {
            await activity.update(content)
        }
        refreshState()
    }

    func end() async {
        for activity in Activity<LoadActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        refreshState()
    }
}
