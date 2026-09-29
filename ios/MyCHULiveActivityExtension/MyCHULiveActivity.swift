import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct MyCHULiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let phase: String
    let title: String
    let body: String
    let shortCriticalText: String?
    let progress: Int
    let progressMax: Int
    let startAt: Date?
    let endAt: Date?
    let targetAppId: String
  }

  let definitionId: String
  let ownerGeneration: String
  let targetAppId: String
}

@main
struct MyCHULiveActivityBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      MyCHULiveActivityWidget()
    }
  }
}

@available(iOS 16.1, *)
struct MyCHULiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MyCHULiveActivityAttributes.self) { context in
      MyCHULiveActivityLockScreenView(context: context)
        .widgetURL(URL(string: "mychu://app/\(context.attributes.targetAppId)"))
        .activityBackgroundTint(Color.blue.opacity(0.12))
        .activitySystemActionForegroundColor(.blue)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.title)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          MyCHULiveActivityTimer(context: context)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.body)
            .font(.subheadline)
            .lineLimit(1)
        }
      } compactLeading: {
        Text("课")
      } compactTrailing: {
        MyCHULiveActivityTimer(context: context)
      } minimal: {
        Text("课")
      }
      .widgetURL(URL(string: "mychu://app/\(context.attributes.targetAppId)"))
    }
  }
}

@available(iOS 16.1, *)
private struct MyCHULiveActivityLockScreenView: View {
  let context: ActivityViewContext<MyCHULiveActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(context.state.title)
          .font(.headline)
          .lineLimit(1)
        Spacer()
        MyCHULiveActivityTimer(context: context)
      }
      Text(context.state.body)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      if context.state.progressMax > 0 {
        ProgressView(
          value: Double(context.state.progress),
          total: Double(context.state.progressMax)
        )
        .tint(.blue)
      }
    }
    .padding(16)
  }
}

@available(iOS 16.1, *)
private struct MyCHULiveActivityTimer: View {
  let context: ActivityViewContext<MyCHULiveActivityAttributes>

  var body: some View {
    if let targetDate {
      Text(timerInterval: Date()...targetDate, countsDown: true)
        .monospacedDigit()
        .font(.caption.weight(.semibold))
    } else {
      Text(fallbackText)
        .font(.caption.weight(.semibold))
    }
  }

  private var targetDate: Date? {
    switch context.state.phase {
    case "upcoming":
      return context.state.startAt
    case "active":
      return context.state.endAt
    default:
      return nil
    }
  }

  private var fallbackText: String {
    switch context.state.phase {
    case "upcoming":
      return "即将开始"
    case "ended":
      return "已结束"
    default:
      return "进行中"
    }
  }
}
