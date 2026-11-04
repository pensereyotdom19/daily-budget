import WidgetKit
import SwiftUI

@main
struct DailyBudgetWidgets: WidgetBundle {
    var body: some Widget {
        TodayLeftWidget()
    }
}

struct TodayLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayLeft", provider: Provider()) { entry in
            TodayLeftView(entry: entry)
        }
        .configurationDisplayName("Left today")
        .description("How much you can still spend today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct DayEntry: TimelineEntry {
    var date: Date
    var limitCents: Int
    var spentCents: Int
    var monthLeftCents: Int
    var hasData: Bool
    var leftCents: Int { limitCents - spentCents }
    var isOver: Bool { spentCents > limitCents }
    var fraction: Double { limitCents > 0 ? min(1, max(0, Double(leftCents) / Double(limitCents))) : 0 }

    static let placeholder = DayEntry(date: .now, limitCents: 340, spentCents: 125, monthLeftCents: 9_075, hasData: true)
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? .placeholder : entry(on: .now))
    }

    /// One entry now, then one at each of the next midnights, so the limit resets
    /// on a new day even if the app isn't opened. The app reloads this when you log something.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let cal = Calendar.current
        var dates = [Date.now]
        var day = cal.startOfDay(for: .now)
        for _ in 0..<3 {
            day = cal.date(byAdding: .day, value: 1, to: day)!
            dates.append(day)
        }
        completion(Timeline(entries: dates.map(entry(on:)), policy: .atEnd))
    }

    private func entry(on date: Date) -> DayEntry {
        guard let snap = WidgetSnapshot.load() else {
            return DayEntry(date: date, limitCents: 0, spentCents: 0, monthLeftCents: 0, hasData: false)
        }
        let calc = snap.calculator()
        let today = calc.summary(on: date)
        return DayEntry(date: date, limitCents: today.limitCents, spentCents: today.spentCents,
                        monthLeftCents: calc.monthLeftCents(inMonthOf: date), hasData: true)
    }
}

// MARK: - Views

private enum W {
    static let base = Color(red: 0.016, green: 0.020, blue: 0.035)
    static let mint = Color(red: 0.486, green: 0.949, blue: 0.627)
    static let sky = Color(red: 0.373, green: 0.816, blue: 1.0)
    static let warn = Color(red: 1.0, green: 0.788, blue: 0.682)
    static let violet = Color(red: 0.482, green: 0.361, blue: 1.0)
    static let teal = Color(red: 0.071, green: 0.710, blue: 0.635)
    static let secondary = Color.white.opacity(0.72)
    static let accent = LinearGradient(colors: [mint, sky], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct TodayLeftView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DayEntry

    private var left: String { Money.format(entry.leftCents, alwaysShowCents: true) }
    private var limit: String { Money.format(entry.limitCents, alwaysShowCents: true) }

    var body: some View {
        content.containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        if !entry.hasData {
            Text("Open Daily Budget once to set up this widget.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        } else {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: Text(entry.isOver ? "\(Money.format(-entry.leftCents, alwaysShowCents: true)) over today" : "\(left) left today")
            case .systemMedium: medium
            default: small
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch family {
        case .systemSmall, .systemMedium:
            ZStack {
                W.base
                RadialGradient(colors: [W.violet.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 180)
                RadialGradient(colors: [W.teal.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 180)
            }
        default:
            Color.clear
        }
    }

    private func ring(size: CGFloat, line: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.16), lineWidth: line)
            Circle()
                .trim(from: 0, to: entry.fraction)
                .stroke(W.accent, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var ringLabel: some View {
        VStack(spacing: 0) {
            Text(left)
                .font(W.rounded(20))
                .foregroundStyle(entry.isOver ? W.warn : .white)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(entry.isOver ? "OVER TODAY" : "LEFT TODAY")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(W.secondary)
        }
        .padding(14)
    }

    private var small: some View {
        VStack(spacing: 6) {
            ZStack { ring(size: 104, line: 10); ringLabel }
            Text("Limit \(limit)").font(.caption2.weight(.semibold)).foregroundStyle(W.secondary)
        }
        .foregroundStyle(.white)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            ZStack { ring(size: 118, line: 11); ringLabel }
            VStack(alignment: .leading, spacing: 8) {
                stat("DAILY LIMIT", limit)
                stat("SPENT TODAY", Money.format(entry.spentCents, alwaysShowCents: true))
                stat("\(entry.date.formatted(.dateTime.month(.wide)).uppercased()) LEFT",
                     Money.format(entry.monthLeftCents, alwaysShowCents: true))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(W.secondary)
            Text(value).font(W.rounded(17))
        }
    }

    private var circular: some View {
        Gauge(value: entry.fraction) {
            Text("Left")
        } currentValueLabel: {
            Text(Money.format(entry.leftCents)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.isOver ? "Over today" : "Left today").font(.caption2.weight(.semibold))
            Text(entry.isOver ? Money.format(-entry.leftCents, alwaysShowCents: true) : left)
                .font(W.rounded(22)).widgetAccentable()
            Text("Limit \(limit)").font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
