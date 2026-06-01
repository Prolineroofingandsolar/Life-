import Capacitor
import WidgetKit

// Paste this file into: ios/App/App/LifePlugin.swift
// This plugin lets the web app write tasks to App Group storage
// so the widget can read them.

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

        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(tasksJSON, forKey: "life_widget_tasks")
        defaults?.synchronize()

        // Tell iOS to refresh the widget
        WidgetCenter.shared.reloadTimelines(ofKind: "LifeTasksWidget")

        call.resolve()
    }
}
