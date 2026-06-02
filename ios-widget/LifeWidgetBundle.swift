import WidgetKit
import SwiftUI

@main
struct LifeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeTasksWidget()
        LifeHabitsWidget()
    }
}
