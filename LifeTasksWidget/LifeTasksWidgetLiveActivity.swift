//
//  LifeTasksWidgetLiveActivity.swift
//  LifeTasksWidget
//
//  Workout Live Activity — elapsed time, rest countdown, sets completed.
//

import ActivityKit
import WidgetKit
import SwiftUI

private let accent = Color(red: 0.19, green: 0.82, blue: 0.35) // #30d158

struct LifeTasksWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // MARK: Lock screen / banner
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(accent)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.workoutName)
                            .font(.caption).fontWeight(.semibold)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .foregroundColor(accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(.title3, design: .rounded).monospacedDigit())
                        .fontWeight(.semibold)
                        .frame(maxWidth: 70, alignment: .trailing)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let restEndsAt = context.state.restEndsAt, restEndsAt > Date() {
                        HStack(spacing: 8) {
                            Image(systemName: "timer").foregroundColor(.orange)
                            Text("Rest")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.orange)
                            ProgressView(timerInterval: Date()...restEndsAt, countsDown: true) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .progressViewStyle(.linear)
                            .tint(.orange)
                            Text(timerInterval: Date()...restEndsAt, countsDown: true)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.orange)
                                .frame(width: 44)
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(accent)
                            Text("\(context.state.setsCompleted) sets done")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional")
                    .foregroundColor(accent)
            } compactTrailing: {
                if let restEndsAt = context.state.restEndsAt, restEndsAt > Date() {
                    Text(timerInterval: Date()...restEndsAt, countsDown: true)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundColor(.orange)
                        .frame(width: 40)
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(.caption, design: .rounded).monospacedDigit())
                        .foregroundColor(accent)
                        .frame(width: 48)
                }
            } minimal: {
                if let restEndsAt = context.state.restEndsAt, restEndsAt > Date() {
                    Image(systemName: "timer").foregroundColor(.orange)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(accent)
                }
            }
            .keylineTint(accent)
        }
    }
}

// MARK: - Lock screen view

private struct LockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label {
                    Text(context.attributes.workoutName)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundColor(accent)
                }
                Spacer()
                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: 80, alignment: .trailing)
            }

            if let restEndsAt = context.state.restEndsAt, restEndsAt > Date() {
                HStack(spacing: 8) {
                    Image(systemName: "timer").foregroundColor(.orange)
                    Text("Rest")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.orange)
                    ProgressView(timerInterval: Date()...restEndsAt, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    Text(timerInterval: Date()...restEndsAt, countsDown: true)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.orange)
                        .frame(width: 44)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(accent)
                    Text("\(context.state.setsCompleted) sets done")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
            }
        }
        .padding(16)
    }
}
