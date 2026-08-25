import Photos
import PhotosUI
import AudioToolbox
import SwiftUI
import UIKit
import ObjectiveC

// MARK: - Statistics prototype

/// A UI-only interpretation of the product sketches for statistics and sharing.
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
    @State private var isShowingSharePreview = false

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
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $isShowingSharePreview) {
                PrototypeSharePreviewView(
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
                isShowingSharePreview = true
            } label: {
                PrototypeActionButton(title: "分享", symbol: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }

    private var periodPicker: some View {
        LiquidControlPanel(contentPadding: 4, cornerRadius: 18) {
            HStack(spacing: 5) {
                ForEach(PrototypeStatisticsPeriod.allCases) { option in
                    let isSelected = period == option
                    PrototypeGlassSegment(isSelected: isSelected) {
                        withAnimation(.snappy(duration: 0.20)) {
                            period = option
                            anchorDate = .now
                        }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GeoTheme.text.opacity(isSelected ? 0.98 : 0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 5)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        LiquidControlPanel(contentPadding: 4, cornerRadius: 18) {
            HStack(spacing: 5) {
                ForEach(PrototypeStatisticsHand.allCases) { option in
                    let isSelected = hand == option
                    PrototypeGlassSegment(isSelected: isSelected) {
                        withAnimation(.snappy(duration: 0.20)) {
                            hand = option
                        }
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GeoTheme.text.opacity(isSelected ? 0.98 : 0.55))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 5)
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .prototypeGlassSurface(cornerRadius: 15)
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

// MARK: - Shareable practice summary

/// A social-first image preview. The preview and the exported PNG are built
/// from the same SwiftUI view so what users approve is exactly what is shared.
private struct PrototypeSharePreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let periodTitle: String
    let records: [PrototypePracticeRecord]

    @State private var renderedImage: UIImage?
    @State private var saveState: PrototypePhotoSaveState = .idle

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        PrototypeNoticeBanner(
                            symbol: "photo.on.rectangle.angled",
                            text: "当前使用 Mock 数据生成分享图片；卡片样式、分享流程与相册保存均可直接体验。"
                        )

                        shareCard
                            .aspectRatio(4 / 5, contentMode: .fit)
                            .frame(maxWidth: 560)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(cardAccessibilityLabel)

                        shareActions

                        if saveState != .idle {
                            saveFeedback
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("分享练习总结")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
            }
            .toolbarBackground(GeoTheme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                renderShareImageIfNeeded()
            }
            .onChange(of: saveState) { _, newState in
                guard newState != .idle else { return }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: newState.message
                )
            }
        }
    }

    private var shareCard: some View {
        PrototypePracticeSummaryCard(periodTitle: periodTitle, records: records)
    }

    @ViewBuilder
    private var shareActions: some View {
        HStack(spacing: 10) {
            if let renderedImage {
                let transferableImage = Image(uiImage: renderedImage)

                ShareLink(
                    item: transferableImage,
                    subject: Text("GeoBeat 练习总结"),
                    message: Text("\(periodTitle) · \(totalCount) 次练习"),
                    preview: SharePreview(
                        "GeoBeat 练习总结",
                        image: transferableImage
                    )
                ) {
                    PrototypeShareActionLabel(
                        title: "分享图片",
                        symbol: "square.and.arrow.up"
                    )
                }
                .accessibilityLabel("分享练习总结图片")
            } else {
                PrototypeShareActionLabel(
                    title: "正在生成",
                    symbol: "hourglass"
                )
                .opacity(0.55)
                .accessibilityLabel("正在生成练习总结图片")
            }

            Button {
                saveToPhotoLibrary()
            } label: {
                PrototypeShareActionLabel(
                    title: saveState == .saving ? "保存中" : "保存到相册",
                    symbol: saveState == .saving ? "hourglass" : "square.and.arrow.down"
                )
            }
            .buttonStyle(.plain)
            .disabled(renderedImage == nil || saveState == .saving)
            .accessibilityLabel(saveState == .saving ? "正在保存到相册" : "保存练习总结图片到相册")
        }
        .accessibilityElement(children: .contain)
    }

    private var saveFeedback: some View {
        LiquidControlPanel(contentPadding: 12, cornerRadius: 18) {
            HStack(spacing: 10) {
                if saveState == .saving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: saveState.symbol)
                        .foregroundStyle(saveState.tint)
                }

                Text(saveState.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GeoTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(saveState.message)
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

    private var cardAccessibilityLabel: String {
        "GeoBeat 练习总结，\(periodTitle)，练习 \(totalCount) 次，共 \(activeDayCount) 天，时长 \(prototypeDuration(totalDuration))"
    }

    @MainActor
    private func renderShareImageIfNeeded() {
        guard renderedImage == nil else { return }

        let renderer = ImageRenderer(
            content: shareCard
                .frame(width: 1080, height: 1350)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1
        renderer.isOpaque = true

        if let image = renderer.uiImage {
            renderedImage = image
        } else {
            saveState = .failed("图片生成失败，请稍后重试。")
        }
    }

    private func saveToPhotoLibrary() {
        guard let imageData = renderedImage?.pngData() else {
            saveState = .failed("图片尚未生成，请稍后重试。")
            return
        }

        saveState = .saving

        Task { @MainActor in
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                saveState = .permissionDenied
                return
            }

            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: imageData, options: nil)
                }
                saveState = .saved
            } catch {
                saveState = .failed("保存失败：\(error.localizedDescription)")
            }
        }
    }
}

private struct PrototypePracticeSummaryCard: View {
    let periodTitle: String
    let records: [PrototypePracticeRecord]

    private let accent = Color(red: 0.74, green: 0.96, blue: 0.44)
    private let referenceSize = CGSize(width: 1080, height: 1350)

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / referenceSize.width,
                geometry.size.height / referenceSize.height
            )

            artwork
                .frame(width: referenceSize.width, height: referenceSize.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
        }
        .aspectRatio(4 / 5, contentMode: .fit)
    }

    private var artwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.075),
                    Color(red: 0.02, green: 0.025, blue: 0.045),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            visualTexture

            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                Spacer(minLength: 24)
                titleBlock
                Spacer(minLength: 30)
                metrics
                Spacer(minLength: 28)
                practiceHighlight
                Spacer(minLength: 22)
                handBreakdown
                Spacer(minLength: 24)
                footer
            }
            .padding(64)
        }
        .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 54, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
        }
        .foregroundStyle(Color.white)
    }

    private var visualTexture: some View {
        ZStack {
            PrototypeSharePolygon(sides: max(3, min(9, activeDayCount + 2)))
                .stroke(accent.opacity(0.18), lineWidth: 3)
                .frame(width: 520, height: 520)
                .rotationEffect(.degrees(-16))
                .offset(x: 365, y: -345)

            PrototypeSharePolygon(sides: 7)
                .stroke(Color.white.opacity(0.055), lineWidth: 2)
                .frame(width: 660, height: 660)
                .rotationEffect(.degrees(12))
                .offset(x: -390, y: 500)

            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: 470, y: 510)
        }
        .accessibilityHidden(true)
    }

    private var brandHeader: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(accent)
                Image(systemName: "metronome.fill")
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(Color.black.opacity(0.86))
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text("GEOBEAT")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(2)
                Text("让每次练习都有回声")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
            }

            Spacer()

            Text(Date.now, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.66))
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("练习总结")
                .font(.system(size: 70, weight: .black, design: .rounded))
                .tracking(-2)

            Text(periodTitle)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var metrics: some View {
        HStack(spacing: 14) {
            PrototypeShareMetric(title: "完成次数", value: totalCount.formatted(), suffix: "次")
            PrototypeShareMetric(title: "练习天数", value: activeDayCount.formatted(), suffix: "天")
            PrototypeShareMetric(title: "投入时长", value: compactDuration(totalDuration), suffix: "")
        }
    }

    private var practiceHighlight: some View {
        HStack(spacing: 24) {
            ZStack {
                PrototypeSharePolygon(sides: 6)
                    .fill(accent.opacity(0.14))
                PrototypeSharePolygon(sides: 6)
                    .stroke(accent.opacity(0.72), lineWidth: 3)
                Text("×\(topSong?.count ?? 0)")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .monospacedDigit()
            }
            .frame(width: 142, height: 142)

            VStack(alignment: .leading, spacing: 9) {
                Text("本期最常练习")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(topSong?.name ?? "等待第一次练习")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(topSong.map { "累计 \(compactDuration($0.duration))" } ?? "从今天开始留下记录")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
            }
        }
        .padding(28)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 2)
        }
    }

    private var handBreakdown: some View {
        HStack(spacing: 12) {
            ForEach(PrototypeStatisticsHand.allCases) { hand in
                VStack(spacing: 6) {
                    Text(hand.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Text("\(count(for: hand)) 次")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("持续练习，听见变化", systemImage: "waveform.path")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
            Spacer()
            Text("GEOBEAT")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(accent.opacity(0.82))
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

    private var topSong: PrototypeShareSongHighlight? {
        Dictionary(grouping: records, by: \.song)
            .map { name, values in
                PrototypeShareSongHighlight(
                    name: name,
                    count: values.reduce(0) { $0 + $1.count },
                    duration: values.reduce(0) { $0 + $1.duration }
                )
            }
            .max { lhs, rhs in lhs.count < rhs.count }
    }

    private func count(for hand: PrototypeStatisticsHand) -> Int {
        records
            .filter { $0.hand == hand }
            .reduce(0) { $0 + $1.count }
    }

    private func compactDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration) / 60)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        }
        return "\(max(1, totalMinutes))m"
    }
}

private struct PrototypeShareMetric: View {
    let title: String
    let value: String
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.52))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.46))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 2)
        }
    }
}

private struct PrototypeShareActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(GeoTheme.text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .prototypeGlassSurface(cornerRadius: 18, emphasized: true)
    }
}

private struct PrototypeSharePolygon: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        let count = max(3, sides)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for index in 0..<count {
            let angle = (Double(index) / Double(count)) * Double.pi * 2 - Double.pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct PrototypeShareSongHighlight {
    let name: String
    let count: Int
    let duration: TimeInterval
}

private enum PrototypePhotoSaveState: Equatable {
    case idle
    case saving
    case saved
    case permissionDenied
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return ""
        case .saving:
            return "正在保存练习总结图片…"
        case .saved:
            return "已保存到相册，可以直接从照片中分享。"
        case .permissionDenied:
            return "没有相册添加权限，请在系统设置中允许 GeoBeat 添加照片。"
        case .failed(let message):
            return message
        }
    }

    var symbol: String {
        switch self {
        case .saved:
            return "checkmark.circle.fill"
        case .permissionDenied:
            return "lock.trianglebadge.exclamationmark.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle, .saving:
            return "hourglass"
        }
    }

    var tint: Color {
        switch self {
        case .saved:
            return .green
        case .permissionDenied, .failed:
            return .orange
        case .idle, .saving:
            return GeoTheme.muted
        }
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
                        if #available(iOS 26.0, *) {
                            glassVariantLabEntry
                        }
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
            HStack(spacing: 15) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(GeoTheme.text)
                    .frame(width: 48, height: 48)
                    .prototypeGlassSurface(cornerRadius: 14, emphasized: true)

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
            .padding(20)
            .prototypeGlassSurface(cornerRadius: 24)
        }
        .buttonStyle(.plain)
    }

    private var metronomeCard: some View {
        PrototypeSettingsCard(title: "设置默认节拍器参数", symbol: "metronome") {
            PrototypeGlassSliderRow(
                title: "默认 BPM",
                symbol: "speedometer",
                value: $defaultBPM,
                range: 30...240,
                unit: "BPM"
            )

            PrototypeGlassSliderRow(
                title: "默认拍数",
                symbol: "music.note",
                value: $defaultBeats,
                range: 3...9,
                unit: "拍"
            )

            HStack(spacing: 10) {
                PrototypeSoundMenu(selection: $sound)

                Button {
                    PrototypeMetronomeSound.preview(named: sound)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GeoTheme.text)
                        .frame(width: 52, height: 58)
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(LiquidPressButtonStyle())
                .prototypeGlassSurface(cornerRadius: 18, emphasized: true)
                .accessibilityLabel("试听当前节拍音色")
                .accessibilityValue(sound)
            }

            Toggle(isOn: $backgroundPlayback) {
                PrototypeSettingsRowLabel(
                    title: "后台运行",
                    detail: backgroundPlayback ? "允许锁屏后继续播放" : "离开应用后停止",
                    symbol: "waveform"
                )
            }
            .tint(Color.white.opacity(0.88))
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .prototypeGlassSurface(cornerRadius: 18)
            .accessibilityHint("双击切换节拍器是否允许在后台继续播放")
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

    @available(iOS 26.0, *)
    private var glassVariantLabEntry: some View {
        NavigationLink {
            PrototypeGlassVariantLabView()
        } label: {
            Label("玻璃效果测试（variant 0–15）", systemImage: "square.stack.3d.up")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GeoTheme.text)
                .frame(maxWidth: .infinity, minHeight: 50)
                .prototypeGlassSurface(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private var currentAppButton: some View {
        Button(action: onOpenCurrentApp) {
            Label("查看当前正式功能", systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(GeoTheme.text)
                .frame(maxWidth: .infinity, minHeight: 50)
                .prototypeGlassSurface(cornerRadius: 16)
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
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(GeoTheme.text)
            content
        }
        .padding(20)
        .prototypeGlassSurface(cornerRadius: 22)
    }
}

private struct PrototypeGlassSliderRow: View {
    let title: String
    let symbol: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    private var sliderValue: Binding<Double> {
        Binding(
            get: { Double(value) },
            set: {
                value = min(max(Int($0.rounded()), range.lowerBound), range.upperBound)
            }
        )
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GeoTheme.text)
                Spacer(minLength: 8)
                Text("\(value) \(unit)")
                    .font(.system(.subheadline, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(GeoTheme.text)
            }

            Slider(
                value: sliderValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(Color.white.opacity(0.90))
            .accessibilityLabel(title)
            .accessibilityValue("\(value) \(unit)")
            .accessibilityHint("上下轻扫调整数值")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .prototypeGlassSurface(cornerRadius: 18)
    }
}

private struct PrototypeSoundMenu: View {
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(PrototypeMetronomeSound.allCases) { option in
                Button {
                    selection = option.rawValue
                    option.preview()
                } label: {
                    Label(
                        option.rawValue,
                        systemImage: selection == option.rawValue
                            ? "checkmark.circle.fill"
                            : "speaker.wave.2"
                    )
                }
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(GeoTheme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("节拍音色")
                        .font(.caption)
                        .foregroundStyle(GeoTheme.muted)
                    Text(selection)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GeoTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                Spacer(minLength: 5)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(GeoTheme.muted)
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(LiquidPressButtonStyle())
        .prototypeGlassSurface(cornerRadius: 18)
        .accessibilityLabel("节拍音色")
        .accessibilityValue(selection)
        .accessibilityHint("打开菜单；选择音色时会播放一次短促试听音")
    }
}

private enum PrototypeMetronomeSound: String, CaseIterable, Identifiable {
    case penetratingWoodblock = "高穿透木鱼"
    case classicClick = "经典节拍"
    case electronicPulse = "电子脉冲"
    case softBlock = "柔和木块"

    var id: Self { self }

    /// Short, non-looping system sounds keep this UI prototype isolated from
    /// the real metronome engine and finish by themselves after each preview.
    private var systemSoundID: SystemSoundID {
        switch self {
        case .penetratingWoodblock: 1_104
        case .classicClick: 1_105
        case .electronicPulse: 1_113
        case .softBlock: 1_306
        }
    }

    func preview() {
        AudioServicesPlaySystemSound(systemSoundID)
    }

    static func preview(named name: String) {
        (Self(rawValue: name) ?? .penetratingWoodblock).preview()
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
        .prototypeGlassSurface(cornerRadius: 16)
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
                    Text("更完整的练习档案、练习总结分享、基准音与跨设备同步。此页目前仅用于确认入口和购买说明层级。")
                        .font(.body)
                        .foregroundStyle(GeoTheme.muted)
                        .multilineTextAlignment(.center)

                    GeoCard(cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("完整统计与分享", systemImage: "chart.bar")
                            Label("更多节拍器声音", systemImage: "speaker.wave.3")
                            Label("云端备份与同步", systemImage: "icloud")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    proSubscribeButton
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

    @ViewBuilder
    private var proSubscribeButton: some View {
        let title = Text("查看订阅方案")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 46)
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Button {
                isShowingPlaceholder = true
            } label: {
                title
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.white.opacity(0.16))
        } else {
            Button {
                isShowingPlaceholder = true
            } label: {
                title
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.90))
            .foregroundStyle(.black)
        }
#else
        Button {
            isShowingPlaceholder = true
        } label: {
            title
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.white.opacity(0.90))
        .foregroundStyle(.black)
#endif
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

// MARK: - TEMPORARY DEBUG TOOL — not for shipping.
/// Allocates a `_UIViewGlass` via its private `initWithVariant:size:smoothness:subdued:`
/// initializer using a raw IMP call (like FocusLite's GlassMaterials.swift
/// does for `set_variant:` on macOS), since that selector takes primitive
/// arguments that `perform(_:with:)`/KVC cannot pass. `variant` is read-only
/// after construction, so this is the only way to try values other than the
/// default 0.
@available(iOS 26.0, *)
func makeViewGlass(variant: Int, size: Int, smoothness: Double, subdued: Bool) -> NSObject? {
    guard let glassClass = NSClassFromString("_UIViewGlass") as? NSObject.Type else { return nil }
    let sel = NSSelectorFromString("initWithVariant:size:smoothness:subdued:")
    guard let method = class_getInstanceMethod(glassClass, sel) else {
        print("makeViewGlass: selector not found")
        return nil
    }
    typealias InitFn = @convention(c) (AnyObject, Selector, Int, Int, Double, Bool) -> Unmanaged<AnyObject>?
    let imp = method_getImplementation(method)
    let fn = unsafeBitCast(imp, to: InitFn.self)
    guard let allocated = (glassClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() else { return nil }
    let result = fn(allocated, sel, variant, size, smoothness, subdued)
    return result?.takeUnretainedValue() as? NSObject
}

// MARK: - Glass variant test page

/// One tile showing the explicit `_UIViewGlass` glass (same recipe used in
/// production panels — see `PrototypeGlassPanelBackground` in
/// PrototypeModels.swift) at a specific `variant` index, so all of them can
/// be compared side by side against a chosen backdrop.
@available(iOS 26.0, *)
private struct PrototypeGlassVariantTile: UIViewRepresentable {
    let variant: Int

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: buildEffect())
        view.layer.cornerRadius = 24
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = buildEffect()
    }

    private func buildEffect() -> UIVisualEffect? {
        guard let glassObj = makeViewGlass(variant: variant, size: 0, smoothness: 0, subdued: false) else {
            return nil
        }
        glassObj.setValue(true, forKey: "contentLensing")
        glassObj.setValue(false, forKey: "excludingControlLensing")
        glassObj.setValue(false, forKey: "excludingControlDisplacement")
        glassObj.setValue(true, forKey: "flexible")

        let sel = NSSelectorFromString("effectWithGlass:")
        guard (UIGlassEffect.self as AnyObject).responds(to: sel) else { return nil }
        return (UIGlassEffect.self as AnyObject).perform(sel, with: glassObj)?
            .takeUnretainedValue() as? UIVisualEffect
    }
}

/// High-contrast diagonal stripe field — one of the selectable test
/// backdrops, useful because straight lines make any edge refraction/
/// displacement immediately visible.
private struct PrototypeGlassLabStripeBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<28, id: \.self) { i in
                    Rectangle()
                        .fill(
                            i.isMultiple(of: 2)
                                ? Color(red: 0.35, green: 0.75, blue: 1.0)
                                : Color(red: 0.02, green: 0.05, blue: 0.10)
                        )
                        .frame(width: 46, height: proxy.size.height * 2.4)
                        .rotationEffect(.degrees(35))
                        .offset(x: CGFloat(i) * 60 - 500, y: 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private enum PrototypeGlassLabBackgroundKind: String, CaseIterable, Identifiable {
    case solid = "纯色"
    case stripes = "条纹"
    case photo = "图片"
    var id: Self { self }
}

/// Test page: every `_UIViewGlass` variant (0–15) rendered side by side over
/// a backdrop you can swap — solid color, stripes, or a photo from your
/// library — so refraction/lensing differences between variants are easy to
/// judge against real content instead of guessing from a single fixed scene.
@available(iOS 26.0, *)
struct PrototypeGlassVariantLabView: View {
    @State private var backgroundKind: PrototypeGlassLabBackgroundKind = .stripes
    @State private var solidColor: Color = .blue
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    controls

                    ForEach(0..<16) { variant in
                        VStack(spacing: 6) {
                            Text("variant \(variant)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 3)
                            PrototypeGlassVariantTile(variant: variant)
                                .frame(height: 120)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("玻璃效果测试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch backgroundKind {
        case .solid:
            solidColor
        case .stripes:
            PrototypeGlassLabStripeBackdrop()
        case .photo:
            GeometryReader { proxy in
                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Color.black
                        .overlay {
                            Text("还没有选择图片")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("背景", selection: $backgroundKind) {
                ForEach(PrototypeGlassLabBackgroundKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if backgroundKind == .solid {
                ColorPicker("背景颜色", selection: $solidColor, supportsOpacity: false)
                    .foregroundStyle(.white)
            }

            if backgroundKind == .photo {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(
                        selectedImage == nil ? "从相册选择图片" : "更换图片",
                        systemImage: "photo.on.rectangle"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        guard let newItem,
                              let data = try? await newItem.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: data) else { return }
                        selectedImage = uiImage
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

#Preview("Glass Variant Lab") {
    if #available(iOS 26.0, *) {
        NavigationStack {
            PrototypeGlassVariantLabView()
        }
        .preferredColorScheme(.dark)
    }
}
