import ActivityKit
import SwiftUI
import WidgetKit

@main
struct JutsuWidgets: WidgetBundle {
    var body: some Widget {
        RenderActivityWidget()
        StatusWidget()
    }
}

private let lime = Color(red: 0.831, green: 1, blue: 0.165)
private let violet = Color(red: 0.545, green: 0.361, blue: 0.965)
private let pink = Color(red: 0.957, green: 0.447, blue: 0.714)

struct RenderActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RenderActivity.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(lime)
                .widgetURL(RenderActivity.queueURL)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        CountBadge(state: state, size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.isDone ? "Done" : "Jutsu").font(.headline)
                            summaryText(state).font(.caption2).foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !state.isDone {
                        Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .foregroundStyle(pink)
                            .monospacedDigit()
                            .frame(width: 76, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.headline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        RunProgress(state: state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                CountBadge(state: state, size: 22)
            } compactTrailing: {
                if state.isDone {
                    Image(systemName: "checkmark").foregroundStyle(lime).fontWeight(.bold)
                } else {
                    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .frame(width: 44)
                        .foregroundStyle(pink)
                }
            } minimal: {
                CountBadge(state: state, size: 22)
            }
            .widgetURL(RenderActivity.queueURL)
            .keylineTint(violet)
        }
    }
}

/// "2 videos · 1 image", "3 ready"; what is being made, then what is finished.
private func summaryText(_ state: RenderActivity.ContentState) -> Text {
    var parts: [Text] = []
    if state.running > 0 { parts.append(state.running == 1 ? Text("1 video") : Text("\(state.running) videos")) }
    if state.images > 0 { parts.append(state.images == 1 ? Text("1 image") : Text("\(state.images) images")) }
    if state.finished > 0 { parts.append(Text("\(state.finished) ready")) }
    guard var text = parts.first else { return Text("") }
    for part in parts.dropFirst() { text = Text("\(text) · \(part)") }
    return text
}

/// How many are being made, in a violet-to-pink circle; a lime check once all is done.
private struct CountBadge: View {
    let state: RenderActivity.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(
                state.isDone
                    ? AnyShapeStyle(lime)
                    : AnyShapeStyle(
                        LinearGradient(colors: [violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing)))
            if state.isDone {
                Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(.black)
            } else {
                Text("\(state.working)").font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.isDone ? Text("All done") : renderingText(state.working))
    }
}

/// What is ready out of everything in this run.
private struct RunProgress: View {
    let state: RenderActivity.ContentState

    var body: some View {
        ProgressView(value: Double(state.finished), total: Double(max(state.finished + state.working, 1)))
            .tint(
                state.isDone
                    ? AnyShapeStyle(lime)
                    : AnyShapeStyle(LinearGradient(colors: [violet, pink], startPoint: .leading, endPoint: .trailing)))
    }
}

/// "1 take rendering", "3 takes rendering".
private func renderingText(_ running: Int) -> Text {
    running == 1 ? Text("1 take rendering") : Text("\(running) takes rendering")
}

private struct LockScreenView: View {
    let state: RenderActivity.ContentState
    /// Room for "1:23:45" in the title face; the timer text otherwise takes all the width it is offered.
    @ScaledMetric(relativeTo: .title) private var timerWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CountBadge(state: state, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.isDone ? "All done" : "Jutsu is making").font(.headline)
                    summaryText(state).font(.caption).foregroundStyle(.secondary)
                    Text(state.headline).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if !state.isDone {
                    Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(.title, design: .monospaced).weight(.semibold))
                        .foregroundStyle(pink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: timerWidth, alignment: .trailing)
                }
            }
            RunProgress(state: state)
            Text(state.isDone ? "Tap to open the Queue" : "Checked \(state.checkedAt, style: .time)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
