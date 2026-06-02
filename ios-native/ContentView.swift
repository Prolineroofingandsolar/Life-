import SwiftUI

struct ContentView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }

            TasksView()
                .tabItem {
                    Label("Tasks", systemImage: "checkmark.circle.fill")
                }

            TrainView()
                .tabItem {
                    Label("Train", systemImage: "dumbbell.fill")
                }

            HabitsView()
                .tabItem {
                    Label("Habits", systemImage: "chart.bar.fill")
                }

            BodyView()
                .tabItem {
                    Label("Body", systemImage: "figure.stand")
                }

            MoneyView()
                .tabItem {
                    Label("Money", systemImage: "dollarsign.circle.fill")
                }
        }
    }
}
