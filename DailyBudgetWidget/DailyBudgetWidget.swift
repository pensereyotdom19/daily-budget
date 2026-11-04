import WidgetKit
import SwiftUI
import AppIntents

@main
struct DailyBudgetWidgets: WidgetBundle {
    init() {
        AppLanguage.install()
    }

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
    var quickItems: [WidgetQuickItem] = []
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
                        monthLeftCents: calc.monthLeftCents(inMonthOf: date), hasData: true,
                        quickItems: Array((snap.quickItems ?? []).prefix(3)))
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
        content
            .environment(\.locale, AppLanguage.locale)
            .containerBackground(for: .widget) { background }
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
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ZStack { ring(size: entry.quickItems.isEmpty ? 118 : 100, line: 10); ringLabel }
                if !entry.quickItems.isEmpty {
                    Text("Limit \(limit)").font(.system(size: 10, weight: .semibold)).foregroundStyle(W.secondary)
                }
            }
            if entry.quickItems.isEmpty { stats } else { buttons }
        }
        .foregroundStyle(.white)
    }

    /// Tap to log it right away. The app saves it next time it opens.
    private var buttons: some View {
        VStack(spacing: 6) {
            ForEach(entry.quickItems, id: \.self) { item in
                Button(intent: QuickAddIntent(item: item)) {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(W.base.opacity(0.85))
                            .frame(width: 24, height: 24)
                            .background(Color(widgetHex: item.colorHex), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(Money.format(item.cents, alwaysShowCents: true)).font(W.rounded(12, .semibold))
                        Image(systemName: "plus").font(.system(size: 10, weight: .heavy)).foregroundStyle(W.mint)
                    }
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                stat("DAILY LIMIT", limit)
                stat("SPENT TODAY", Money.format(entry.spentCents, alwaysShowCents: true))
                stat("\(entry.date.formatted(.dateTime.month(.wide).locale(AppLanguage.locale)).uppercased()) LEFT",
                     Money.format(entry.monthLeftCents, alwaysShowCents: true))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
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

private extension Color {
    init(widgetHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// A widget button: queues the expense for the app and updates the ring straight away.
struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick add"
    static let isDiscoverable = false

    @Parameter(title: "Note") var note: String
    @Parameter(title: "Category") var category: String
    @Parameter(title: "Amount in cents") var cents: Int

    init() {}

    init(item: WidgetQuickItem) {
        note = item.note
        category = item.category
        cents = item.cents
    }

    func perform() async throws -> some IntentResult {
        guard cents > 0 else { return .result() }
        let pending = PendingExpense(id: UUID(), cents: cents, category: category, note: note, date: .now)
        QuickAddQueue.append(pending)
        QuickAddQueue.applyToSnapshot(pending, countsAsLiving: QuickAddQueue.countsAsLiving(category))
        return .result()
    }
}
