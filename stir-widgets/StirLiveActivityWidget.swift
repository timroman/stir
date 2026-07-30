import ActivityKit
import SwiftUI
import WidgetKit

struct StirLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StirActivityAttributes.self) { context in
            // Lock screen / banner view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isAlarming ? "bell.fill" : "alarm")
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isAlarming {
                        Text("😊")
                            .font(.caption.bold())
                    } else {
                        Text(context.state.wakeWindow)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.message)
                        .font(.caption2)
                        .foregroundColor(context.state.isAlarming ? context.state.accentColor : .gray)
                }
            } compactLeading: {
                Image(systemName: context.state.isAlarming ? "bell.fill" : "alarm")
                    .foregroundColor(.white)
            } compactTrailing: {
                if context.state.isAlarming {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(context.state.accentColor)
                } else {
                    AudioLevelBars(level: context.state.audioLevel, accentColor: context.state.accentColor)
                }
            } minimal: {
                Image(systemName: context.state.isAlarming ? "bell.fill" : "alarm")
                    .foregroundColor(.white)
            }
        }
    }
}

struct AudioLevelBars: View {
    let level: Double
    let accentColor: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 16)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [6, 10, 14, 16]
        return heights[index]
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Double(index + 1) / 4.0
        if level >= threshold {
            return accentColor
        } else {
            return .white.opacity(0.3)
        }
    }
}

struct LockScreenView: View {
    let context: ActivityViewContext<StirActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if context.state.isAlarming {
                    Text(context.state.message)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                } else {
                    Text(context.state.wakeWindow)
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    Text(context.state.message)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            if context.state.isAlarming {
                Image(systemName: "bell.fill")
                    .font(.title)
                    .foregroundColor(.white)
            } else {
                AudioLevelBarsLarge(level: context.state.audioLevel, accentColor: context.state.accentColor)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }
}

struct AudioLevelBarsLarge: View {
    let level: Double
    let accentColor: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .frame(height: 28)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [8, 12, 18, 24, 28]
        return heights[index]
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Double(index + 1) / 5.0
        if level >= threshold {
            return accentColor
        } else {
            return .white.opacity(0.3)
        }
    }
}
