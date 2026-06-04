//
//  LifeTasksWidgetLiveActivity.swift
//  LifeTasksWidget
//
//  Created by Will on 02/06/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct LifeTasksWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct LifeTasksWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LifeTasksWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension LifeTasksWidgetAttributes {
    fileprivate static var preview: LifeTasksWidgetAttributes {
        LifeTasksWidgetAttributes(name: "World")
    }
}

extension LifeTasksWidgetAttributes.ContentState {
    fileprivate static var smiley: LifeTasksWidgetAttributes.ContentState {
        LifeTasksWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: LifeTasksWidgetAttributes.ContentState {
         LifeTasksWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: LifeTasksWidgetAttributes.preview) {
   LifeTasksWidgetLiveActivity()
} contentStates: {
    LifeTasksWidgetAttributes.ContentState.smiley
    LifeTasksWidgetAttributes.ContentState.starEyes
}
