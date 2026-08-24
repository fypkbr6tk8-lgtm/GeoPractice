import SwiftUI

// MARK: - Statistics prototype

/// A UI-only interpretation of the product sketches for statistics and bills.
///
/// The records below are deliberately local mock data. This view is intended to
/// validate navigation, filtering vocabulary and information hierarchy before
/// the real statistics engine is connected.
struct PrototypeStatisticsView: View {
    @State private var period: PrototypeStatisticsPeriod = .week
    @State private var anchorDate = Date.now
    @State private var hand: PrototypeStatisticsHand = .left
    @State private var song: String?
    @State private var sort: PrototypeStatisticsSort = .count
    @State private var isShowingBill = false

    private let calendar = Calendar.autoupdatingCurrent
    private let records = PrototypePracticeRecord.samples

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        actionBar
                        periodPicker
                        periodNavigator
                        handPicker
                        summary
                        timeline
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 112)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $isShowingBill) {
                PrototypeBillPreviewView(
                    periodTitle: periodTitle,
                    records: filteredRecords
                )
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 9) {
            Menu {
                Picker("排序依据", selection: $sort) {
                    ForEach(PrototypeStatisticsSort.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
            } label: {
                PrototypeActionButton(
                    title: sort.shortTitle,
                    symbol: sort.symbol
                )
            }

            Menu {
                Button {
                    song = nil
                } label: {
                    PrototypeMenuChoiceLabel(
                        title: "所有曲目",
                        isSelected: song == nil
                    )
                }

                ForEach(songNames, id: \.self) { name in
                    Button {
                        song = name
                    } label: {
                        PrototypeMenuChoiceLabel(
                            title: name,
                            isSelected: song == name
                        )
                    }
                }
            } label: {
                PrototypeActionButton(
                    title: song ?? "曲目选择",
                    symbol: "music.note.list"
                )
            }

            Button {
                isShowingBill = true
            } label: {
                PrototypeActionButton(title: "分享", symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }

    private var periodPicker: some View {
        GeoSegmentContainer {
            ForEach(PrototypeStatisticsPeriod.allCases) { option in
                GeoSegmentButton(
                    title: option.title,
                    symbol: nil,
                    isActive: period == option
                ) {
                    withAnimation(.snappy(duration: 0.20)) {
                        period = option
                        anchorDate = .now
                    }
                }
            }
        }
    }

    private var periodNavigator: some View {
        LiquidControlPanel(contentPadding: 4, cornerRadius: 18) {
            HStack(spacing: 4) {
                periodArrow(direction: -1)

                Button {
                    anchorDate = .now
                } label: {
                    VStack(spacing: 2) {
                        Text(periodTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(GeoTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(period == .all ? "已包含全部模拟记录" : "轻点返回当前周期")
                            .font(.caption2)
                            .foregroundStyle(GeoTheme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(period == .all)

                periodArrow(direction: 1)
            }
        }
    }

    private func periodArrow(direction: Int) -> some View {
        Button {
            shiftPeriod(direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(period == .all ? GeoTheme.muted.opacity(0.35) : GeoTheme.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(period == .all)
        .accessibilityLabel(direction < 0 ? "上一个周期" : "下一个周期")
    }

    private var handPicker: some View {
        GeoSegmentContainer {
            ForEach(PrototypeStatisticsHand.allCases) { option in
                GeoSegmentButton(
                    title: option.title,
                    symbol: nil,
                    isActive: hand == option
                ) {
                    withAnimation(.snappy(duration: 0.20)) {
                        hand = option
                    }
                }
            }
        }
    }

    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                PrototypeMetricCard(
                    title: "练习总次数",
                    value: totalCount.formatted(),
                    symbol: "repeat"
                )
                PrototypeMetricCard(
                    title: "练习总天数",
                    value: activeDayCount.formatted(),
                    symbol: "calendar"
                )
            }

            VStack(spacing: 10) {
                PrototypeMetricCard(
                    title: "练习总次数",
                    value: totalCount.formatted(),
                    symbol: "repeat"
                )
                PrototypeMetricCard(
                    title: "练习总天数",
                    value: activeDayCount.formatted(),
                    symbol: "calendar"
                )
            }
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if groupedRecords.isEmpty {
            GeoCard(cornerRadius: 22) {
                ContentUnavailableView {
                    Label("暂无模拟记录", systemImage: "chart.bar.xaxis")
                } description: {
                    Text("当前筛选组合没有记录。切换周期、曲目或练习方式继续查看原型。")
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        } else {
            LazyVStack(spacing: 14) {
                ForEach(groupedRecords, id: \.day) { group in
                    PrototypeTimelineDayCard(day: group.day, records: group.records)
                }
            }
        }
    }

    private var songNames: [String] {
        Array(Set(records.map(\.song))).sorted()
    }

    private var filteredRecords: [PrototypePracticeRecord] {
        records.filter { record in
            isIncludedInPeriod(record.date)
                && record.hand == hand
                && (song == nil || record.song == song)
        }
    }

    private var groupedRecords: [(day: Date, records: [PrototypePracticeRecord])] {
        Dictionary(grouping: filteredRecords) { record in
            calendar.startOfDay(for: record.date)
        }
        .map { day, values in
            let sortedValues: [PrototypePracticeRecord]
            switch sort {
            case .count:
                sortedValues = values.sorted {
                    $0.count == $1.count ? $0.date > $1.date : $0.count > $1.count
                }
            case .duration:
                sortedValues = values.sorted {
                    $0.duration == $1.duration ? $0.date > $1.date : $0.duration > $1.duration
                }
            }
            return (day, sortedValues)
        }
        .sorted { $0.day > $1.day }
    }

    private var totalCount: Int {
        filteredRecords.reduce(0) { $0 + $1.count }
    }

    private var activeDayCount: Int {
        Set(filteredRecords.map { calendar.startOfDay(for: $0.date) }).count
    }

    private var periodTitle: String {
        switch period {
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: anchorDate) ?? anchorDate
            return "\(start.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) – \(anchorDate.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))"
        case .month:
            return anchorDate.formatted(.dateTime.year().month(.wide))
        case .year:
            return anchorDate.formatted(.dateTime.year())
        case .all:
            return "所有时间"
        }
    }

    private func shiftPeriod(_ direction: Int) {
        let component: Calendar.Component
        switch period {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        case .all: return
        }
        if let shifted = calendar.date(byAdding: component, value: direction, to: anchorDate) {
            withAnimation(.snappy(duration: 0.20)) {
                anchorDate = shifted
            }
        }
    }

    private func isIncludedInPeriod(_ date: Date) -> Bool {
        switch period {
        case .week:
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: anchorDate)) ?? anchorDate
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? .distantPast
            return date >= start && date < end
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: anchorDate) else { return true }
            return interval.contains(date)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: anchorDate) else { return true }
            return interval.contains(date)
        case .all:
            return true
        }
    }
}

private enum PrototypeStatisticsPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "周"
        case .month: "月"
        case .year: "年"
        case .all: "所有"
        }
    }
}

private enum PrototypeStatisticsHand: String, CaseIterable, Identifiable {
    case left
    case together
    case right

    var id: Self { self }

    var title: String {
        switch self {
        case .left: "左"
        case .together: "合"
        case .right: "右"
        }
    }
}

private enum PrototypeStatisticsSort: String, CaseIterable, Identifiable {
    case count
    case duration

    var id: Self { self }

    var title: String {
        switch self {
        case .count: "按次数排序"
        case .duration: "按时长排序"
        }
    }

    var shortTitle: String {
        switch self {
        case .count: "次数排序"
        case .duration: "时长排序"
        }
    }

    var symbol: String {
        switch self {
        case .count: "number"
        case .duration: "clock"
        }
    }
}

private struct PrototypePracticeRecord: Identifiable {
    let id = UUID()
    let date: Date
    let song: String
    let section: String
    let hand: PrototypeStatisticsHand
    let bpm: Int
    let note: String
    let duration: TimeInterval
    let count: Int

    static var samples: [Self] {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date.now

        func time(daysAgo: Int, hour: Int, minute: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        return [
            Self(date: time(daysAgo: 0, hour: 16, minute: 18), song: "月光奏鸣曲", section: "第一段", hand: .left, bpm: 80, note: "八分音符", duration: 390, count: 15),
            Self(date: time(daysAgo: 0, hour: 16, minute: 15), song: "月光奏鸣曲", section: "第二段", hand: .left, bpm: 84, note: "八分音符", duration: 88, count: 5),
            Self(date: time(daysAgo: 0, hour: 16, minute: 11), song: "哈农 No.1", section: "完整练习", hand: .right, bpm: 96, note: "四分音符", duration: 165, count: 8),
            Self(date: time(daysAgo: 1, hour: 19, minute: 42), song: "月光奏鸣曲", section: "第三段", hand: .left, bpm: 76, note: "八分音符", duration: 214, count: 10),
            Self(date: time(daysAgo: 1, hour: 19, minute: 31), song: "巴赫创意曲", section: "主题", hand: .together, bpm: 72, note: "十六分音符", duration: 284, count: 12),
            Self(date: time(daysAgo: 2, hour: 8, minute: 22), song: "哈农 No.1", section: "完整练习", hand: .right, bpm: 104, note: "四分音符", duration: 325, count: 16),
            Self(date: time(daysAgo: 3, hour: 21, minute: 6), song: "巴赫创意曲", section: "再现部", hand: .left, bpm: 68, note: "十六分音符", duration: 405, count: 18),
            Self(date: time(daysAgo: 5, hour: 17, minute: 18), song: "月光奏鸣曲", section: "第四段", hand: .together, bpm: 80, note: "八分音符", duration: 455, count: 15),
            Self(date: time(daysAgo: 12, hour: 16, minute: 4), song: "哈农 No.1", section: "完整练习", hand: .left, bpm: 112, note: "四分音符", duration: 246, count: 20),
            Self(date: time(daysAgo: 29, hour: 20, minute: 9), song: "巴赫创意曲", section: "主题", hand: .right, bpm: 88, note: "十六分音符", duration: 318, count: 14),
            Self(date: time(daysAgo: 93, hour: 9, minute: 45), song: "月光奏鸣曲", section: "第一段", hand: .left, bpm: 72, note: "八分音符", duration: 520, count: 22),
            Self(date: time(daysAgo: 370, hour: 18, minute: 0), song: "哈农 No.1", section: "完整练习", hand: .together, bpm: 100, note: "四分音符", duration: 600, count: 24)
        ]
    }
}

private struct PrototypeActionButton: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(GeoTheme.text)
        .frame(maxWidth: .infinity, minHeight: 46)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(GeoTheme.panelRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
        )
    }
}

private struct PrototypeMenuChoiceLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct PrototypeMetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        GeoCard(cornerRadius: 20) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(GeoTheme.muted)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GeoTheme.muted)
                    Text(value)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(GeoTheme.text)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PrototypeTimelineDayCard: View {
    let day: Date
    let records: [PrototypePracticeRecord]

    var body: some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text(day.formatted(.dateTime.month(.twoDigits).day(.twoDigits).weekday(.abbreviated)))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(GeoTheme.text)

                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }

                    HStack(alignment: .top, spacing: 13) {
                        Text(record.date, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(GeoTheme.muted)
                            .frame(width: 44, alignment: .leading)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(record.song) · \(record.section)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(GeoTheme.text)
                            Text("\(record.hand.title) · \(record.bpm) BPM · \(record.note)")
                                .font(.caption)
                                .foregroundStyle(GeoTheme.muted)
                            Text("\(prototypeDuration(record.duration)) · \(record.count) 次")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GeoTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Bill preview

private struct PrototypeBillPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let periodTitle: String
    let records: [PrototypePracticeRecord]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.025).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        PrototypeNoticeBanner(
                            symbol: "doc.text.magnifyingglass",
                            text: "Mock 账单用于确认信息结构。正式图片或 PDF 导出将在数据口径确认后接入。"
                        )

                        billPaper
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("账单预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareText) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .toolbarBackground(GeoTheme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var billPaper: some View {
        VStack(spacing: 28) {
            VStack(spacing: 4) {
                Text("GEOBEAT BILL")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text(periodTitle)
                    .font(.headline)
                Text(Date.now, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    .font(.caption.monospacedDigit())
            }

            HStack(spacing: 12) {
                PrototypeBillMetric(title: "练习总次数", value: totalCount.formatted())
                PrototypeBillMetric(title: "练习总天数", value: activeDayCount.formatted())
                PrototypeBillMetric(title: "练习时长", value: prototypeDuration(totalDuration))
            }

            VStack(spacing: 0) {
                HStack {
                    Text("PRACTICE")
                    Spacer()
                    Text("DURATION")
                        .frame(width: 82, alignment: .trailing)
                    Text("FREQUENCY")
                        .frame(width: 82, alignment: .trailing)
                }
                .font(.caption.weight(.black))
                .padding(.bottom, 10)

                Divider().overlay(Color.black.opacity(0.16))

                ForEach(billRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.song)
                                .font(.subheadline.weight(.bold))
                            Text(row.section)
                                .font(.caption)
                                .foregroundStyle(Color.black.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(prototypeDuration(row.duration))
                            .frame(width: 82, alignment: .trailing)
                        Text("×\(row.count)")
                            .frame(width: 82, alignment: .trailing)
                    }
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.vertical, 10)

                    Divider().overlay(Color.black.opacity(0.08))
                }
            }

            Spacer(minLength: 80)
            Text("GEOBEAT")
                .font(.headline.weight(.black))
        }
        .foregroundStyle(Color.black.opacity(0.88))
        .padding(24)
        .frame(maxWidth: 560, minHeight: 700, alignment: .top)
        .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        }
    }

    private var totalCount: Int {
        records.reduce(0) { $0 + $1.count }
    }

    private var totalDuration: TimeInterval {
        records.reduce(0) { $0 + $1.duration }
    }

    private var activeDayCount: Int {
        let calendar = Calendar.autoupdatingCurrent
        return Set(records.map { calendar.startOfDay(for: $0.date) }).count
    }

    private var billRows: [PrototypeBillRow] {
        Dictionary(grouping: records) { "\($0.song)|\($0.section)" }
            .compactMap { _, values in
                guard let first = values.first else { return nil }
                return PrototypeBillRow(
                    song: first.song,
                    section: first.section,
                    duration: values.reduce(0) { $0 + $1.duration },
                    count: values.reduce(0) { $0 + $1.count }
                )
            }
            .sorted { $0.song == $1.song ? $0.section < $1.section : $0.song < $1.song }
    }

    private var shareText: String {
        "GEOBEAT BILL · \(periodTitle)\n练习总次数 \(totalCount)\n练习总天数 \(activeDayCount)\n练习时长 \(prototypeDuration(totalDuration))\n\nMock 原型数据"
    }
}

private struct PrototypeBillRow: Identifiable {
    let id = UUID()
    let song: String
    let section: String
    let duration: TimeInterval
    let count: Int
}

private struct PrototypeBillMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.60)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.58))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Settings prototype

/// A navigable settings prototype. All values live in `@State`; StoreKit,
/// notifications, iCloud and backup services are intentionally not connected.
struct PrototypeSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private let onOpenCurrentApp: () -> Void

    @State private var defaultBPM = 120
    @State private var defaultBeats = 4
    @State private var sound = "高穿透木鱼"
    @State private var backgroundPlayback = true
    @State private var restReminderEnabled = true
    @State private var restMinutes = 30
    @State private var dailyReminderEnabled = true
    @State private var dailyReminderHour = 9
    @State private var appearance: PrototypeAppearance = .followSystem
    @State private var buttonHaptics = true
    @State private var beatVibration = false
    @State private var iCloudSync = false
    @State private var activeAlert: PrototypeSettingsAlert?

    init(onOpenCurrentApp: @escaping () -> Void = {}) {
        self.onOpenCurrentApp = onOpenCurrentApp
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()

                ScrollView {
                    LazyVStack(spacing: 16) {
                        prototypeNotice
                        proCard
                        metronomeCard
                        remindersCard
                        appearanceCard
                        dataCard
                        aboutCard
                        currentAppButton
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .alert(item: $activeAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("知道了"))
                )
            }
        }
    }

    private var prototypeNotice: some View {
        PrototypeNoticeBanner(
            symbol: "wand.and.stars",
            text: "UI / 跳转确认版。付款、提醒、iCloud 与备份按钮只演示交互，不会修改系统设置或真实数据。"
        )
    }

    private var proCard: some View {
        NavigationLink {
            PrototypeProView()
        } label: {
            GeoCard(cornerRadius: 24) {
                HStack(spacing: 15) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(GeoTheme.text)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("GeoBeat PRO")
                            .font(.title3.weight(.black))
                            .foregroundStyle(GeoTheme.text)
                        Text("PRO 账户卡片与专属购买页")
                            .font(.caption)
                            .foregroundStyle(GeoTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GeoTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var metronomeCard: some View {
        PrototypeSettingsCard(title: "设置默认节拍器参数", symbol: "metronome") {
            NavigationLink {
                PrototypeMetronomeDefaultsView(
                    bpm: $defaultBPM,
                    beats: $defaultBeats,
                    sound: $sound,
                    backgroundPlayback: $backgroundPlayback
                )
            } label: {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    PrototypeSettingTile(title: "默认 BPM", value: "\(defaultBPM)", symbol: "speedometer")
                    PrototypeSettingTile(title: "默认拍数", value: "\(defaultBeats)", symbol: "music.note")
                    PrototypeSettingTile(title: "节拍音色", value: sound, symbol: "speaker.wave.2")
                    PrototypeSettingTile(title: "后台运行", value: backgroundPlayback ? "开启" : "关闭", symbol: "waveform")
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GeoTheme.muted)
                        .padding(11)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var remindersCard: some View {
        PrototypeSettingsCard(title: "健康与习惯", symbol: "heart") {
            Toggle(isOn: $restReminderEnabled) {
                PrototypeSettingsRowLabel(
                    title: "默认休息提醒",
                    detail: restReminderEnabled ? "每 \(restMinutes) 分钟" : "关闭",
                    symbol: "cup.and.saucer"
                )
            }
            .tint(Color.white.opacity(0.88))

            PrototypeSettingsDivider()

            Toggle(isOn: $dailyReminderEnabled) {
                PrototypeSettingsRowLabel(
                    title: "每日打卡提醒",
                    detail: dailyReminderEnabled ? String(format: "%02d:00", dailyReminderHour) : "关闭",
                    symbol: "alarm"
                )
            }
            .tint(Color.white.opacity(0.88))

            NavigationLink {
                PrototypeReminderSettingsView(
                    restEnabled: $restReminderEnabled,
                    restMinutes: $restMinutes,
                    dailyEnabled: $dailyReminderEnabled,
                    dailyHour: $dailyReminderHour
                )
            } label: {
                PrototypeDisclosureRow(title: "调整提醒时间", symbol: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
        }
    }

    private var appearanceCard: some View {
        PrototypeSettingsCard(title: "外观与交互", symbol: "circle.lefthalf.filled") {
            NavigationLink {
                PrototypeAppearanceSettingsView(
                    appearance: $appearance,
                    buttonHaptics: $buttonHaptics,
                    beatVibration: $beatVibration
                )
            } label: {
                PrototypeSettingsRowLabel(
                    title: "显示模式",
                    detail: appearance.title,
                    symbol: "paintbrush"
                )
            }
            .buttonStyle(.plain)

            PrototypeSettingsDivider()

            Toggle(isOn: $buttonHaptics) {
                PrototypeSettingsRowLabel(
                    title: "按键触感",
                    detail: buttonHaptics ? "开启" : "关闭",
                    symbol: "hand.tap"
                )
            }
            .tint(Color.white.opacity(0.88))

            PrototypeSettingsDivider()

            Toggle(isOn: $beatVibration) {
                PrototypeSettingsRowLabel(
                    title: "节拍震动",
                    detail: beatVibration ? "开启" : "关闭",
                    symbol: "iphone.radiowaves.left.and.right"
                )
            }
            .tint(Color.white.opacity(0.88))
        }
    }

    private var dataCard: some View {
        PrototypeSettingsCard(title: "数据管理", symbol: "externaldrive") {
            Toggle(isOn: $iCloudSync) {
                PrototypeSettingsRowLabel(
                    title: "iCloud 同步",
                    detail: iCloudSync ? "原型状态：已开启" : "原型状态：未开启",
                    symbol: "icloud"
                )
            }
            .tint(Color.white.opacity(0.88))

            PrototypeSettingsDivider()

            NavigationLink {
                PrototypeBackupRestoreView()
            } label: {
                PrototypeDisclosureRow(title: "备份与恢复", symbol: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
        }
    }

    private var aboutCard: some View {
        PrototypeSettingsCard(title: "关于我们", symbol: "info.circle") {
            Button {
                activeAlert = .feedback
            } label: {
                PrototypeDisclosureRow(title: "意见反馈", symbol: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.plain)

            PrototypeSettingsDivider()

            Button {
                activeAlert = .review
            } label: {
                PrototypeDisclosureRow(title: "App Store 评分", symbol: "star")
            }
            .buttonStyle(.plain)

            PrototypeSettingsDivider()

            NavigationLink {
                PrototypeLegalView()
            } label: {
                PrototypeDisclosureRow(title: "隐私政策与协议", symbol: "hand.raised")
            }
            .buttonStyle(.plain)
        }
    }

    private var currentAppButton: some View {
        Button(action: onOpenCurrentApp) {
            Label("查看当前正式功能", systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GeoTheme.text)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(GeoTheme.panelRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private enum PrototypeAppearance: String, CaseIterable, Identifiable {
    case followSystem
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .followSystem: "跟随系统"
        case .light: "白天"
        case .dark: "黑夜"
        }
    }

    var symbol: String {
        switch self {
        case .followSystem: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }
}

private enum PrototypeSettingsAlert: String, Identifiable {
    case feedback
    case review

    var id: Self { self }

    var title: String {
        switch self {
        case .feedback: "意见反馈"
        case .review: "App Store 评分"
        }
    }

    var message: String {
        switch self {
        case .feedback: "确认原型后再接入真实反馈渠道；本按钮目前不会发送内容。"
        case .review: "确认原型后再连接 App Store 评分页；本按钮目前不会离开应用。"
        }
    }
}

private struct PrototypeSettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: symbol)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(GeoTheme.text)
                content
            }
        }
    }
}

private struct PrototypeSettingTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(GeoTheme.muted)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(GeoTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GeoTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct PrototypeSettingsRowLabel: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(GeoTheme.muted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GeoTheme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(GeoTheme.muted)
            }
            Spacer(minLength: 6)
        }
        .contentShape(Rectangle())
    }
}

private struct PrototypeDisclosureRow: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(GeoTheme.muted)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GeoTheme.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(GeoTheme.muted)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct PrototypeSettingsDivider: View {
    var body: some View {
        Divider().overlay(Color.white.opacity(0.08))
    }
}

private struct PrototypeNoticeBanner: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(GeoTheme.text)
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(GeoTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: Settings destinations

private struct PrototypeProView: View {
    @State private var isShowingPlaceholder = false

    var body: some View {
        ZStack {
            GeoBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 64, weight: .semibold))
                    Text("GeoBeat PRO")
                        .font(.largeTitle.weight(.black))
                    Text("更完整的练习档案、账单导出、基准音与跨设备同步。此页目前仅用于确认入口和购买说明层级。")
                        .font(.body)
                        .foregroundStyle(GeoTheme.muted)
                        .multilineTextAlignment(.center)

                    GeoCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("完整统计与账单", systemImage: "chart.bar")
                            Label("更多节拍器声音", systemImage: "speaker.wave.3")
                            Label("云端备份与同步", systemImage: "icloud")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button("查看订阅方案") {
                        isShowingPlaceholder = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.white.opacity(0.90))
                    .foregroundStyle(.black)
                }
                .foregroundStyle(GeoTheme.text)
                .frame(maxWidth: 560)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("GeoBeat PRO")
        .navigationBarTitleDisplayMode(.inline)
        .alert("购买流程占位", isPresented: $isShowingPlaceholder) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("此 Mock 版本不会调用 StoreKit 或产生付款。")
        }
    }
}

private struct PrototypeMetronomeDefaultsView: View {
    @Binding var bpm: Int
    @Binding var beats: Int
    @Binding var sound: String
    @Binding var backgroundPlayback: Bool

    private let sounds = ["高穿透木鱼", "经典节拍", "电子脉冲", "柔和木块"]

    var body: some View {
        PrototypeSettingsDestination(title: "默认节拍器参数") {
            PrototypeSettingsCard(title: "速度与拍号", symbol: "metronome") {
                Stepper(value: $bpm, in: 30...240) {
                    PrototypeSettingsRowLabel(title: "默认 BPM", detail: "\(bpm)", symbol: "speedometer")
                }
                PrototypeSettingsDivider()
                Stepper(value: $beats, in: 1...12) {
                    PrototypeSettingsRowLabel(title: "默认拍数", detail: "每小节 \(beats) 拍", symbol: "music.note")
                }
            }

            PrototypeSettingsCard(title: "声音与运行", symbol: "speaker.wave.2") {
                Picker("节拍音色", selection: $sound) {
                    ForEach(sounds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(GeoTheme.text)

                PrototypeSettingsDivider()

                Toggle(isOn: $backgroundPlayback) {
                    PrototypeSettingsRowLabel(
                        title: "后台运行",
                        detail: backgroundPlayback ? "允许锁屏后继续播放" : "离开页面后停止",
                        symbol: "waveform"
                    )
                }
                .tint(Color.white.opacity(0.88))
            }
        }
    }
}

private struct PrototypeReminderSettingsView: View {
    @Binding var restEnabled: Bool
    @Binding var restMinutes: Int
    @Binding var dailyEnabled: Bool
    @Binding var dailyHour: Int

    var body: some View {
        PrototypeSettingsDestination(title: "提醒设置") {
            PrototypeSettingsCard(title: "休息提醒", symbol: "cup.and.saucer") {
                Toggle("开启休息提醒", isOn: $restEnabled)
                    .tint(Color.white.opacity(0.88))
                if restEnabled {
                    Stepper("每 \(restMinutes) 分钟提醒", value: $restMinutes, in: 10...120, step: 5)
                }
            }

            PrototypeSettingsCard(title: "每日打卡", symbol: "alarm") {
                Toggle("开启每日提醒", isOn: $dailyEnabled)
                    .tint(Color.white.opacity(0.88))
                if dailyEnabled {
                    Stepper(
                        String(format: "每天 %02d:00", dailyHour),
                        value: $dailyHour,
                        in: 0...23
                    )
                }
                Text("Mock 版本不会申请通知权限，也不会创建系统通知。")
                    .font(.caption)
                    .foregroundStyle(GeoTheme.muted)
            }
        }
    }
}

private struct PrototypeAppearanceSettingsView: View {
    @Binding var appearance: PrototypeAppearance
    @Binding var buttonHaptics: Bool
    @Binding var beatVibration: Bool

    var body: some View {
        PrototypeSettingsDestination(title: "外观与交互") {
            PrototypeSettingsCard(title: "显示模式", symbol: "circle.lefthalf.filled") {
                ForEach(PrototypeAppearance.allCases) { option in
                    Button {
                        appearance = option
                    } label: {
                        HStack {
                            Label(option.title, systemImage: option.symbol)
                            Spacer()
                            if appearance == option {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .foregroundStyle(GeoTheme.text)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if option != PrototypeAppearance.allCases.last {
                        PrototypeSettingsDivider()
                    }
                }
            }

            PrototypeSettingsCard(title: "触感", symbol: "hand.tap") {
                Toggle("按键触感", isOn: $buttonHaptics)
                    .tint(Color.white.opacity(0.88))
                PrototypeSettingsDivider()
                Toggle("节拍震动", isOn: $beatVibration)
                    .tint(Color.white.opacity(0.88))
            }
        }
    }
}

private struct PrototypeBackupRestoreView: View {
    @State private var alertMessage: String?

    var body: some View {
        PrototypeSettingsDestination(title: "备份与恢复") {
            PrototypeNoticeBanner(
                symbol: "externaldrive.badge.exclamationmark",
                text: "这里仅演示流程。备份和恢复不会读取、覆盖或删除任何真实练习数据。"
            )

            PrototypeSettingsCard(title: "本地数据", symbol: "externaldrive") {
                Button {
                    alertMessage = "已模拟生成 GeoBeat-Backup.geobeat"
                } label: {
                    PrototypeDisclosureRow(title: "导出备份", symbol: "square.and.arrow.up")
                }
                .buttonStyle(.plain)

                PrototypeSettingsDivider()

                Button {
                    alertMessage = "已模拟选择备份文件；没有写入任何数据"
                } label: {
                    PrototypeDisclosureRow(title: "从备份恢复", symbol: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
            }
        }
        .alert("原型操作", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }
}

private struct PrototypeLegalView: View {
    var body: some View {
        PrototypeSettingsDestination(title: "隐私政策与协议") {
            PrototypeSettingsCard(title: "原型占位", symbol: "hand.raised") {
                Text("正式版本将在这里展示隐私政策、服务协议、生效日期和可访问的网页版链接。")
                    .font(.body)
                    .foregroundStyle(GeoTheme.muted)
                Text("本原型不会采集、上传或同步任何练习数据。")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GeoTheme.text)
            }
        }
    }
}

private struct PrototypeSettingsDestination<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            GeoBackground()
            ScrollView {
                LazyVStack(spacing: 16) {
                    content
                }
                .frame(maxWidth: 680)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private func prototypeDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval.rounded()))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

#Preview("Prototype Statistics") {
    PrototypeStatisticsView()
}

#Preview("Prototype Settings") {
    PrototypeSettingsView()
}
