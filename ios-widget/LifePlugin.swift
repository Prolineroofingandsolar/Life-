import Capacitor
import WidgetKit

// Paste this file into: ios/App/App/LifePlugin.swift

@objc(LifePlugin)
public class LifePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "LifePlugin"
    public let jsName = "LifePlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "syncTasks", returnType: CAPPluginReturnPromise)
    ]

    private let appGroup = "group.uk.co.prolineroofingandsolar.life"

    @objc func syncTasks(_ call: CAPPluginCall) {
        guard let tasksJSON = call.getString("tasksJSON") else {
            call.reject("Missing tasksJSON")
            return
        }

        // Write to App Group UserDefaults
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(tasksJSON, forKey: "life_widget_tasks")

        // Also write to shared file as backup
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            let fileURL = containerURL.appendingPathComponent("life_tasks.json")
            try? tasksJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        // Refresh widget
        WidgetCenter.shared.reloadTimelines(ofKind: "LifeTasksWidget")

        call.resolve()
    }
}
