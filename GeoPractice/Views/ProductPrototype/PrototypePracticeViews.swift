import SwiftUI

// MARK: - Practice browser

/// Runnable, in-memory interpretation of the check-in product sketches.
/// Nothing in this file reads or writes the production SwiftData models.
struct PrototypePracticeView: View {
    let onOpenMetronome: (PrototypePracticeLaunch) -> Void

    @StateObject private var store = PrototypePracticeStore()
    @State private var query = ""
    @State private var showsSearch = false
    @State private var selectedFilter: PrototypePracticeFilter = .today
    @State private var showsNewSong = false
    @State private var showsArchive = false

    init(onOpenMetronome: @escaping (PrototypePracticeLaunch) -> Void = { _ in }) {
        self.onOpenMetronome = onOpenMetronome
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        prototypeNotice
                        filterStrip

                        if showsSearch {
                            searchField
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(sectionTitle)
                                .font(.title3.weight(.bold))
                            Spacer()
                            Text("\(visibleSections.count) 个练习段落")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GeoTheme.muted)
                        }

                        if visibleSections.isEmpty {
                            emptyState
                        } else {
                            ForEach(visibleSections) { item in
                                PrototypePracticeSectionCard(
                                    song: item.song,
                                    section: item.section,
                                    onStart: {
                                        onOpenMetronome(store.launch(song: item.song, section: item.section))
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showsSearch.toggle() }
                    } label: {
                        PrototypeToolbarIconLabel(systemName: "magnifyingglass")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .accessibilityLabel(showsSearch ? "收起搜索" : "搜索曲目和段落")
                }
                .prototypeHidesSharedToolbarBackground()

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showsArchive = true
                    } label: {
                        PrototypeToolbarIconLabel(systemName: "archivebox")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .accessibilityLabel("已归档曲目")

                    Button {
                        showsNewSong = true
                    } label: {
                        PrototypeToolbarIconLabel(systemName: "plus")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .accessibilityLabel("新建曲目")
                }
                .prototypeHidesSharedToolbarBackground()
            }
            .prototypeNavigationBarGlassBackground()
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showsNewSong) {
                PrototypeSongEditorView(store: store, songID: nil)
            }
            .sheet(isPresented: $showsArchive) {
                PrototypeArchiveView(store: store)
            }
        }
        .environmentObject(store)
    }

    private var prototypeNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
            Text("交互原型 · 编辑、补录和计次只在本次运行中保留，不会写入正式数据。")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(GeoTheme.muted)
        .padding(13)
        .prototypeGlassSurface(cornerRadius: 16)
    }

    private var filterStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterButton(.today, title: "今日完成")
                filterButton(.all, title: "所有曲目")

                ForEach(store.activeSongs) { song in
                    filterButton(.song(song.id), title: song.name)
                }

                Button {
                    showsNewSong = true
                } label: {
                    PrototypeGlassControl {
                        Label("新建", systemImage: "plus")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 42)
                    }
                }
                .buttonStyle(LiquidPressButtonStyle())
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
    }

    private func filterButton(_ filter: PrototypePracticeFilter, title: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { selectedFilter = filter }
        } label: {
            PrototypeGlassControl {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedFilter == filter ? GeoTheme.text : GeoTheme.muted)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 42)
                    .prototypeGlassSelection(selectedFilter == filter)
            }
        }
        .buttonStyle(LiquidPressButtonStyle())
        .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GeoTheme.muted)
            TextField("搜索曲目、分组或段落", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GeoTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .prototypeGlassSurface(cornerRadius: 16)
    }

    private var visibleSections: [PrototypeSongSectionItem] {
        store.activeSongs.flatMap { song in
            song.sections.map { PrototypeSongSectionItem(song: song, section: $0) }
        }
        .filter { item in
            let filterMatches: Bool
            switch selectedFilter {
            case .today:
                filterMatches = item.section.completedCount > 0
            case .all:
                filterMatches = true
            case .song(let id):
                filterMatches = item.song.id == id
            }

            guard filterMatches else { return false }
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return true }
            return item.song.name.localizedCaseInsensitiveContains(needle)
                || item.song.group.localizedCaseInsensitiveContains(needle)
                || item.section.name.localizedCaseInsensitiveContains(needle)
        }
    }

    private var sectionTitle: String {
        switch selectedFilter {
        case .today: "今日练习"
        case .all: "全部练习"
        case .song(let id): store.song(id: id)?.name ?? "曲目"
        }
    }

    private var emptyState: some View {
        GeoCard(cornerRadius: 22) {
            ContentUnavailableView {
                Label("没有匹配的练习", systemImage: "music.note.list")
            } description: {
                Text("尝试切换筛选或创建一首新的曲目。")
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        }
    }
}

private struct PrototypePracticeSectionCard: View {
    let song: PrototypeMockSong
    let section: PrototypeMockSection
    let onStart: () -> Void

    var body: some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.name)
                            .font(.headline.weight(.bold))
                        Text("\(song.name) · \(song.group)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(GeoTheme.muted)
                        Text("上次练习 \(section.lastPracticed.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(GeoTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Text(section.target.map { "\(section.completedCount)/\($0)" } ?? "\(section.completedCount) 次")
                        .font(.headline.monospacedDigit().weight(.black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }

                HStack(spacing: 8) {
                    Label("\(section.bpm) BPM", systemImage: "metronome")
                    Text("·")
                    Text("\(section.beats) 拍")
                    Text("·")
                    Text(section.note)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GeoTheme.muted)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actionButtons }
                    VStack(spacing: 10) { actionButtons }
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        NavigationLink {
            PrototypeSongDetailView(songID: song.id)
        } label: {
            Label("详情", systemImage: "doc.text.magnifyingglass")
                .prototypeActionLabel()
        }
        .buttonStyle(.plain)

        Button(action: onStart) {
            Label("进入练习", systemImage: "play.fill")
                .prototypeActionLabel(prominent: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Song detail

private struct PrototypeSongDetailView: View {
    @EnvironmentObject private var store: PrototypePracticeStore

    let songID: UUID
    @State private var showsEditor = false
    @State private var showsBackfill = false

    var body: some View {
        ZStack {
            GeoBackground()

            if let song = store.song(id: songID) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        detailHeader(song)
                        actionGrid
                        overview(song)
                        weekCard(song)
                        monthCard(song)
                        yearCard(song)
                        sectionsCard(song)
                    }
                    .frame(maxWidth: 760)
                    .padding(16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .navigationTitle(song.name)
                .sheet(isPresented: $showsEditor) {
                    PrototypeSongEditorView(store: store, songID: songID)
                }
                .sheet(isPresented: $showsBackfill) {
                    PrototypeBackfillView(store: store, songID: songID)
                }
            } else {
                ContentUnavailableView("曲目不存在", systemImage: "music.note")
            }
        }
    }

    private func detailHeader(_ song: PrototypeMockSong) -> some View {
        VStack(spacing: 5) {
            Text(song.name)
                .font(.system(size: 28, weight: .black, design: .rounded))
            Text("\(song.group) · 建立 \(song.createdAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GeoTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { detailActions }
            VStack(spacing: 10) { detailActions }
        }
    }

    @ViewBuilder
    private var detailActions: some View {
        Button { showsEditor = true } label: {
            Label("编辑", systemImage: "pencil").prototypeActionLabel()
        }
        .buttonStyle(.plain)

        NavigationLink {
            PrototypeSongHistoryView(songID: songID)
        } label: {
            Label("历史记录", systemImage: "clock.arrow.circlepath").prototypeActionLabel()
        }
        .buttonStyle(.plain)

        Button { showsBackfill = true } label: {
            Label("补录", systemImage: "plus.rectangle.on.rectangle").prototypeActionLabel(prominent: true)
        }
        .buttonStyle(.plain)
    }

    private func overview(_ song: PrototypeMockSong) -> some View {
        let records = store.records(for: song.id)
        let count = records.reduce(0) { $0 + $1.count }
        let duration = records.reduce(0.0) { $0 + $1.duration }
        return GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("总览").font(.headline.weight(.bold))
                HStack(spacing: 8) {
                    PrototypeDetailMetric(title: "练习次数", value: count.formatted())
                    PrototypeDetailMetric(title: "练习天数", value: store.activeDays(for: song.id).formatted())
                    PrototypeDetailMetric(title: "总时长", value: prototypePracticeDuration(duration))
                }
            }
        }
    }

    private func weekCard(_ song: PrototypeMockSong) -> some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Text("周统计 · 最近 7 天").font(.headline.weight(.bold))
                HStack(alignment: .bottom, spacing: 9) {
                    ForEach(Array(store.weekCounts(for: song.id).enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white.opacity(value > 0 ? 0.82 : 0.10))
                                .frame(height: max(8, CGFloat(value) * 4))
                            Text("\(index + 1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(GeoTheme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 90, alignment: .bottom)
                Text("Mock 柱形仅用于确认周统计的展示位置。")
                    .font(.caption2)
                    .foregroundStyle(GeoTheme.muted)
            }
        }
    }

    private func monthCard(_ song: PrototypeMockSong) -> some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("月统计 · \(Date.now.formatted(.dateTime.month(.wide)))")
                    .font(.headline.weight(.bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(1...28, id: \.self) { day in
                        let active = (day + song.sections.count) % 4 != 0
                        Text("\(day)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(active ? .black : GeoTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(active ? Color.white.opacity(0.84) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("月历为布局示例，不代表正式统计结果。")
                    .font(.caption2)
                    .foregroundStyle(GeoTheme.muted)
            }
        }
    }

    private func yearCard(_ song: PrototypeMockSong) -> some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("年统计 · \(Date.now.formatted(.dateTime.year()))")
                    .font(.headline.weight(.bold))
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(1...12, id: \.self) { month in
                        VStack(spacing: 5) {
                            Capsule()
                                .fill(Color.white.opacity(0.18 + Double((month + song.sections.count) % 6) * 0.10))
                                .frame(height: CGFloat(12 + ((month * 11) % 54)))
                            Text("\(month)")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(GeoTheme.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 86, alignment: .bottom)
            }
        }
    }

    private func sectionsCard(_ song: PrototypeMockSong) -> some View {
        GeoCard(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 13) {
                Text("练习段落").font(.headline.weight(.bold))
                ForEach(song.sections) { section in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.name).font(.subheadline.weight(.bold))
                            Text("\(section.bpm) BPM · \(section.beats) 拍 · \(section.note)")
                                .font(.caption)
                                .foregroundStyle(GeoTheme.muted)
                        }
                        Spacer()
                        Text(section.target.map { "\(section.completedCount)/\($0)" } ?? "\(section.completedCount)")
                            .font(.subheadline.monospacedDigit().weight(.black))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: - Editor

private struct PrototypeSongEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PrototypePracticeStore
    let songID: UUID?

    @State private var name = ""
    @State private var group = "未分组"
    @State private var sectionNames: [String] = ["第一段"]
    @State private var leftGoal = 10
    @State private var rightGoal = 10
    @State private var bothGoal = 10
    @State private var multiplier = 1
    @State private var resetsDaily = true
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var archived = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("曲目信息") {
                    TextField("曲目名", text: $name)
                    TextField("分组", text: $group)
                }

                Section("练习段落") {
                    ForEach(sectionNames.indices, id: \.self) { index in
                        HStack {
                            TextField("段落 \(index + 1)", text: $sectionNames[index])
                            if sectionNames.count > 1 {
                                Button(role: .destructive) {
                                    sectionNames.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("删除段落 \(index + 1)")
                            }
                        }
                    }
                    Button {
                        sectionNames.append("第\(sectionNames.count + 1)段")
                    } label: {
                        Label("增加段落", systemImage: "plus")
                    }
                }

                Section("目标") {
                    Stepper("左手目标 \(leftGoal)", value: $leftGoal, in: 0...999)
                    Stepper("右手目标 \(rightGoal)", value: $rightGoal, in: 0...999)
                    Stepper("合手目标 \(bothGoal)", value: $bothGoal, in: 0...999)
                }

                Section("计数与周期") {
                    Stepper("每次记录次数 ×\(multiplier)", value: $multiplier, in: 1...20)
                    Toggle("每日重置", isOn: $resetsDaily)
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                }

                if songID != nil {
                    Section {
                        Toggle("归档曲目", isOn: $archived)
                    } footer: {
                        Text("归档后不会出现在打卡首页，可从归档入口恢复。")
                    }
                }

                Section {
                    Text("Mock 编辑仅用于确认字段与跳转；正式的数据约束和迁移将在 UI 通过后实现。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(songID == nil ? "新建曲目" : "编辑曲目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        PrototypeToolbarTextLabel(title: "取消")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                }
                .prototypeHidesSharedToolbarBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.saveSong(
                            id: songID,
                            name: name,
                            group: group,
                            sectionNames: sectionNames,
                            leftGoal: leftGoal,
                            rightGoal: rightGoal,
                            bothGoal: bothGoal,
                            multiplier: multiplier,
                            resetsDaily: resetsDaily,
                            endDate: endDate,
                            archived: archived
                        )
                        dismiss()
                    } label: {
                        PrototypeToolbarTextLabel(title: "保存")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .prototypeHidesSharedToolbarBackground()
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let songID, let song = store.song(id: songID) else { return }
        name = song.name
        group = song.group
        sectionNames = song.sections.map(\.name)
        leftGoal = song.leftGoal
        rightGoal = song.rightGoal
        bothGoal = song.bothGoal
        multiplier = song.multiplier
        resetsDaily = song.resetsDaily
        endDate = song.endDate
        archived = song.isArchived
    }
}

// MARK: - History and backfill

private struct PrototypeSongHistoryView: View {
    @EnvironmentObject private var store: PrototypePracticeStore
    let songID: UUID

    @State private var period: PrototypeHistoryPeriod = .week
    @State private var anchorDate = Date.now
    @State private var hand: PrototypePracticeHand = .left

    var body: some View {
        ZStack {
            GeoBackground()
            ScrollView {
                LazyVStack(spacing: 14) {
                    GeoCard(cornerRadius: 20) {
                        VStack(spacing: 12) {
                            periodControl
                            dateControl
                            handControl
                        }
                    }

                    if groupedRecords.isEmpty {
                        GeoCard(cornerRadius: 20) {
                            ContentUnavailableView {
                                Label("该范围暂无记录", systemImage: "clock")
                            } description: {
                                Text("切换时间范围或手型可查看其他 Mock 记录。")
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    } else {
                        ForEach(groupedRecords, id: \.day) { group in
                            GeoCard(cornerRadius: 20) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(group.day.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                                        .font(.headline.weight(.bold))
                                    ForEach(group.records) { record in
                                        HStack(alignment: .top, spacing: 12) {
                                            Text(record.date, format: .dateTime.hour().minute())
                                                .font(.caption.monospacedDigit().weight(.bold))
                                                .foregroundStyle(GeoTheme.muted)
                                                .frame(width: 44, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("\(record.sectionName) · \(record.hand.title)")
                                                    .font(.subheadline.weight(.bold))
                                                Text("\(record.bpm) BPM · \(record.note) · \(record.count) 次")
                                                    .font(.caption)
                                                    .foregroundStyle(GeoTheme.muted)
                                                HStack(spacing: 8) {
                                                    Text(prototypePracticeDuration(record.duration))
                                                    if let gap = intervalDescription(after: record) {
                                                        Text("距上一条 \(gap)")
                                                    }
                                                }
                                                .font(.caption2)
                                                .foregroundStyle(GeoTheme.muted)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodControl: some View {
        HStack(spacing: 4) {
            ForEach(PrototypeHistoryPeriod.allCases) { value in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { period = value }
                } label: {
                    Text(value.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(period == value ? GeoTheme.text : GeoTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .prototypeGlassSelection(period == value)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == value ? .isSelected : [])
            }
        }
        .padding(4)
        .background { PrototypeGlassControl { Color.clear } }
    }

    private var dateControl: some View {
        HStack(spacing: 8) {
            Button { shiftPeriod(-1) } label: {
                PrototypeGlassControl {
                    Image(systemName: "chevron.left").frame(width: 40, height: 40)
                }
            }
            .buttonStyle(LiquidPressButtonStyle())
            .disabled(period == .all)
            Text(period.rangeTitle(anchor: anchorDate))
                .font(.caption.monospacedDigit().weight(.bold))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Button { shiftPeriod(1) } label: {
                PrototypeGlassControl {
                    Image(systemName: "chevron.right").frame(width: 40, height: 40)
                }
            }
            .buttonStyle(LiquidPressButtonStyle())
            .disabled(period == .all)
        }
        .foregroundStyle(GeoTheme.text)
    }

    private var handControl: some View {
        HStack(spacing: 4) {
            ForEach(PrototypePracticeHand.allCases) { value in
                Button {
                    hand = value
                } label: {
                    Text(value.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hand == value ? GeoTheme.text : GeoTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .prototypeGlassSelection(hand == value)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(hand == value ? .isSelected : [])
            }
        }
        .padding(4)
        .background { PrototypeGlassControl { Color.clear } }
    }

    private var filteredRecords: [PrototypeMockRecord] {
        store.records(for: songID)
            .filter { $0.hand == hand }
            .filter { record in
                guard let interval = period.dateInterval(anchor: anchorDate) else { return true }
                return interval.contains(record.date)
            }
    }

    private var groupedRecords: [(day: Date, records: [PrototypeMockRecord])] {
        Dictionary(grouping: filteredRecords) {
            Calendar.autoupdatingCurrent.startOfDay(for: $0.date)
        }
        .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
        .sorted { $0.day > $1.day }
    }

    private func shiftPeriod(_ offset: Int) {
        guard let component = period.calendarComponent,
              let shifted = Calendar.autoupdatingCurrent.date(byAdding: component, value: offset, to: anchorDate)
        else { return }
        anchorDate = shifted
    }

    private func intervalDescription(after record: PrototypeMockRecord) -> String? {
        guard let index = filteredRecords.firstIndex(where: { $0.id == record.id }),
              filteredRecords.indices.contains(index + 1)
        else { return nil }
        let seconds = max(0, Int(record.date.timeIntervalSince(filteredRecords[index + 1].date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

private enum PrototypeHistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "周"
        case .month: "月"
        case .year: "年"
        case .all: "所有"
        }
    }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }

    func dateInterval(anchor: Date) -> DateInterval? {
        switch self {
        case .week: Calendar.autoupdatingCurrent.dateInterval(of: .weekOfYear, for: anchor)
        case .month: Calendar.autoupdatingCurrent.dateInterval(of: .month, for: anchor)
        case .year: Calendar.autoupdatingCurrent.dateInterval(of: .year, for: anchor)
        case .all: nil
        }
    }

    func rangeTitle(anchor: Date) -> String {
        guard let interval = dateInterval(anchor: anchor) else { return "所有时间" }
        switch self {
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) – \(end.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))"
        case .month:
            return anchor.formatted(.dateTime.year().month(.wide))
        case .year:
            return anchor.formatted(.dateTime.year())
        case .all:
            return "所有时间"
        }
    }
}

private struct PrototypeBackfillView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PrototypePracticeStore
    let songID: UUID

    @State private var date = Date.now
    @State private var sectionID: UUID?
    @State private var hand: PrototypePracticeHand = .left
    @State private var bpm = 80
    @State private var note = "八分音符"
    @State private var minutes = 5
    @State private var count = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("补录") {
                    DatePicker("记录时间", selection: $date)
                    if let song = store.song(id: songID) {
                        Picker("练习段落", selection: $sectionID) {
                            ForEach(song.sections) { section in
                                Text(section.name).tag(Optional(section.id))
                            }
                        }
                    }
                    Picker("手型", selection: $hand) {
                        ForEach(PrototypePracticeHand.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    Stepper("速度 \(bpm) BPM", value: $bpm, in: 30...240)
                    Picker("训练音符", selection: $note) {
                        ForEach(["四分音符", "八分音符", "十六分音符"], id: \.self) { Text($0) }
                    }
                    Stepper("时长 \(minutes) 分钟", value: $minutes, in: 1...240)
                    Stepper("完成 \(count) 次", value: $count, in: 1...999)
                }

                Section {
                    Text("上下滚动或手动填写均为原型交互；保存只加入本次运行的 Mock 历史。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("补录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        PrototypeToolbarTextLabel(title: "取消")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                }
                .prototypeHidesSharedToolbarBackground()
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        store.addRecord(
                            songID: songID,
                            sectionID: sectionID,
                            date: date,
                            hand: hand,
                            bpm: bpm,
                            note: note,
                            duration: TimeInterval(minutes * 60),
                            count: count
                        )
                        dismiss()
                    } label: {
                        PrototypeToolbarTextLabel(title: "保存")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .disabled(sectionID == nil)
                }
                .prototypeHidesSharedToolbarBackground()
            }
        }
        .onAppear {
            if sectionID == nil { sectionID = store.song(id: songID)?.sections.first?.id }
        }
    }
}

private struct PrototypeArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PrototypePracticeStore

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()
                if store.archivedSongs.isEmpty {
                    ContentUnavailableView("暂无归档曲目", systemImage: "archivebox")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(store.archivedSongs) { song in
                                GeoCard(cornerRadius: 18) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(song.name).font(.headline)
                                            Text("\(song.group) · \(song.sections.count) 个段落")
                                                .font(.caption)
                                                .foregroundStyle(GeoTheme.muted)
                                        }
                                        Spacer()
                                        Button { store.setArchived(song.id, false) } label: {
                                            Text("恢复")
                                                .font(.caption.weight(.bold))
                                                .padding(.horizontal, 14)
                                                .frame(minHeight: 40)
                                                .prototypeGlassControl(cornerRadius: 13)
                                        }
                                        .buttonStyle(LiquidPressButtonStyle())
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("已归档")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        PrototypeToolbarTextLabel(title: "完成")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                }
                .prototypeHidesSharedToolbarBackground()
            }
        }
    }
}

// MARK: - Mock store and values

@MainActor
private final class PrototypePracticeStore: ObservableObject {
    @Published private(set) var songs: [PrototypeMockSong]
    @Published private(set) var records: [PrototypeMockRecord]

    init() {
        let fixture = PrototypePracticeFixture.make()
        songs = fixture.songs
        records = fixture.records
    }

    var activeSongs: [PrototypeMockSong] {
        songs.filter { !$0.isArchived }.sorted { $0.name < $1.name }
    }

    var archivedSongs: [PrototypeMockSong] {
        songs.filter(\.isArchived).sorted { $0.name < $1.name }
    }

    func song(id: UUID) -> PrototypeMockSong? {
        songs.first { $0.id == id }
    }

    func records(for songID: UUID) -> [PrototypeMockRecord] {
        records.filter { $0.songID == songID }.sorted { $0.date > $1.date }
    }

    func activeDays(for songID: UUID) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        return Set(records(for: songID).map { calendar.startOfDay(for: $0.date) }).count
    }

    func weekCounts(for songID: UUID) -> [Int] {
        let calendar = Calendar.autoupdatingCurrent
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            return records(for: songID)
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .reduce(0) { $0 + $1.count }
        }
    }

    func launch(song: PrototypeMockSong, section: PrototypeMockSection) -> PrototypePracticeLaunch {
        let completedByHand: [PrototypePracticeHand: Int] = [
            .left: min(section.completedCount, song.leftGoal),
            .right: min(max(0, section.completedCount - 1), song.rightGoal),
            .both: min(max(0, section.completedCount - 2), song.bothGoal)
        ]
        let targetByHand: [PrototypePracticeHand: Int] = [
            .left: song.leftGoal,
            .right: song.rightGoal,
            .both: song.bothGoal
        ]
        return PrototypePracticeLaunch(
            pieceName: song.name,
            sectionName: section.name,
            bpm: section.bpm,
            beats: section.beats,
            trainingNote: section.note,
            referenceNote: "四分音符",
            completedByHand: completedByHand,
            targetByHand: targetByHand
        )
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        songs[index].isArchived = archived
    }

    func saveSong(
        id: UUID?,
        name: String,
        group: String,
        sectionNames: [String],
        leftGoal: Int,
        rightGoal: Int,
        bothGoal: Int,
        multiplier: Int,
        resetsDaily: Bool,
        endDate: Date,
        archived: Bool
    ) {
        let cleanNames = sectionNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let fallback = cleanNames.isEmpty ? ["完整练习"] : cleanNames

        if let id, let index = songs.firstIndex(where: { $0.id == id }) {
            let old = songs[index]
            let sections = fallback.enumerated().map { offset, title in
                old.sections.first(where: { $0.name == title })
                    ?? PrototypeMockSection(
                        name: title,
                        lastPracticed: .now.addingTimeInterval(TimeInterval(-offset * 86_400)),
                        completedCount: 0,
                        target: max(leftGoal, rightGoal, bothGoal),
                        bpm: 80,
                        beats: 4,
                        note: "八分音符"
                    )
            }
            songs[index] = PrototypeMockSong(
                id: old.id,
                name: name,
                group: group.isEmpty ? "未分组" : group,
                sections: sections,
                leftGoal: max(0, leftGoal),
                rightGoal: max(0, rightGoal),
                bothGoal: max(0, bothGoal),
                multiplier: max(1, multiplier),
                resetsDaily: resetsDaily,
                endDate: endDate,
                createdAt: old.createdAt,
                isArchived: archived
            )
        } else {
            let sections = fallback.enumerated().map { offset, title in
                PrototypeMockSection(
                    name: title,
                    lastPracticed: .now.addingTimeInterval(TimeInterval(-offset * 86_400)),
                    completedCount: 0,
                    target: max(leftGoal, rightGoal, bothGoal),
                    bpm: 80,
                    beats: 4,
                    note: "八分音符"
                )
            }
            songs.append(PrototypeMockSong(
                name: name,
                group: group.isEmpty ? "未分组" : group,
                sections: sections,
                leftGoal: max(0, leftGoal),
                rightGoal: max(0, rightGoal),
                bothGoal: max(0, bothGoal),
                multiplier: max(1, multiplier),
                resetsDaily: resetsDaily,
                endDate: endDate,
                createdAt: .now,
                isArchived: archived
            ))
        }
    }

    func addRecord(
        songID: UUID,
        sectionID: UUID?,
        date: Date,
        hand: PrototypePracticeHand,
        bpm: Int,
        note: String,
        duration: TimeInterval,
        count: Int
    ) {
        guard let songIndex = songs.firstIndex(where: { $0.id == songID }),
              let sectionIndex = songs[songIndex].sections.firstIndex(where: { $0.id == sectionID })
        else { return }
        let section = songs[songIndex].sections[sectionIndex]
        let safeCount = max(1, count)
        records.append(PrototypeMockRecord(
            songID: songID,
            sectionID: section.id,
            sectionName: section.name,
            date: date,
            hand: hand,
            bpm: bpm,
            note: note,
            duration: max(0, duration),
            count: safeCount
        ))
        songs[songIndex].sections[sectionIndex].completedCount += safeCount
        if date > songs[songIndex].sections[sectionIndex].lastPracticed {
            songs[songIndex].sections[sectionIndex].lastPracticed = date
        }
    }
}

private enum PrototypePracticeFilter: Hashable {
    case today
    case all
    case song(UUID)
}

private struct PrototypeSongSectionItem: Identifiable {
    var id: String { "\(song.id.uuidString)-\(section.id.uuidString)" }
    let song: PrototypeMockSong
    let section: PrototypeMockSection
}

private struct PrototypeMockSong: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var group: String
    var sections: [PrototypeMockSection]
    var leftGoal: Int
    var rightGoal: Int
    var bothGoal: Int
    var multiplier: Int
    var resetsDaily: Bool
    var endDate: Date
    var createdAt: Date
    var isArchived: Bool
}

private struct PrototypeMockSection: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var lastPracticed: Date
    var completedCount: Int
    var target: Int?
    var bpm: Int
    var beats: Int
    var note: String
}

private struct PrototypeMockRecord: Identifiable, Hashable {
    var id = UUID()
    let songID: UUID
    let sectionID: UUID
    let sectionName: String
    let date: Date
    let hand: PrototypePracticeHand
    let bpm: Int
    let note: String
    let duration: TimeInterval
    let count: Int
}

private enum PrototypePracticeFixture {
    static func make() -> (songs: [PrototypeMockSong], records: [PrototypeMockRecord]) {
        let calendar = Calendar.autoupdatingCurrent
        func date(daysAgo: Int, hour: Int = 18) -> Date {
            let base = calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
            let candidate = calendar.date(
                bySettingHour: hour,
                minute: daysAgo * 7 % 60,
                second: 0,
                of: base
            ) ?? base
            // Today's fixture must never render as an impossible future
            // practice (for example, “1 hour later” when the app is opened
            // before the chosen fixture hour).
            return candidate > .now ? .now.addingTimeInterval(-3_600) : candidate
        }

        let moonSections = (1...5).map { index in
            PrototypeMockSection(
                name: "第\(index)段",
                lastPracticed: date(daysAgo: index - 1),
                completedCount: [6, 10, 4, 8, 3][index - 1],
                target: 10,
                bpm: [80, 84, 76, 88, 72][index - 1],
                beats: index == 3 ? 5 : 4,
                note: index.isMultiple(of: 2) ? "十六分音符" : "八分音符"
            )
        }
        let moon = PrototypeMockSong(
            name: "月光奏鸣曲",
            group: "贝多芬",
            sections: moonSections,
            leftGoal: 10,
            rightGoal: 10,
            bothGoal: 10,
            multiplier: 1,
            resetsDaily: true,
            endDate: calendar.date(byAdding: .month, value: 2, to: .now) ?? .now,
            createdAt: calendar.date(byAdding: .month, value: -4, to: .now) ?? .now,
            isArchived: false
        )

        let hanonSection = PrototypeMockSection(
            name: "完整练习",
            lastPracticed: date(daysAgo: 0, hour: 9),
            completedCount: 12,
            target: 20,
            bpm: 112,
            beats: 4,
            note: "四分音符"
        )
        let hanon = PrototypeMockSong(
            name: "哈农 No.1",
            group: "基本功",
            sections: [hanonSection],
            leftGoal: 20,
            rightGoal: 20,
            bothGoal: 0,
            multiplier: 1,
            resetsDaily: true,
            endDate: calendar.date(byAdding: .month, value: 1, to: .now) ?? .now,
            createdAt: calendar.date(byAdding: .month, value: -2, to: .now) ?? .now,
            isArchived: false
        )

        let bachSection = PrototypeMockSection(
            name: "主题与再现",
            lastPracticed: date(daysAgo: 6),
            completedCount: 0,
            target: nil,
            bpm: 72,
            beats: 3,
            note: "十六分音符"
        )
        let bach = PrototypeMockSong(
            name: "巴赫创意曲",
            group: "复调",
            sections: [bachSection],
            leftGoal: 8,
            rightGoal: 8,
            bothGoal: 8,
            multiplier: 1,
            resetsDaily: false,
            endDate: calendar.date(byAdding: .month, value: 3, to: .now) ?? .now,
            createdAt: calendar.date(byAdding: .month, value: -6, to: .now) ?? .now,
            isArchived: true
        )

        let songs = [moon, hanon, bach]
        var records: [PrototypeMockRecord] = []
        for (songIndex, song) in songs.enumerated() {
            for day in 0..<8 {
                guard let section = song.sections[safe: day % song.sections.count] else { continue }
                let hand = PrototypePracticeHand.allCases[(day + songIndex) % PrototypePracticeHand.allCases.count]
                records.append(PrototypeMockRecord(
                    songID: song.id,
                    sectionID: section.id,
                    sectionName: section.name,
                    date: date(daysAgo: day + songIndex, hour: 16 + songIndex),
                    hand: hand,
                    bpm: section.bpm + (day % 3) * 2,
                    note: section.note,
                    duration: TimeInterval(120 + day * 38),
                    count: 3 + (day * 2) % 12
                ))
            }
        }
        return (songs, records)
    }
}

private struct PrototypeDetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(GeoTheme.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .prototypeGlassSurface(cornerRadius: 13)
    }
}

private extension View {
    func prototypeActionLabel(prominent: Bool = false) -> some View {
        font(.caption.weight(.bold))
            .foregroundStyle(GeoTheme.text)
            .frame(maxWidth: .infinity, minHeight: 46)
            .prototypeGlassControl(cornerRadius: 14)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func prototypePracticeDuration(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    let hours = seconds / 3_600
    let minutes = seconds % 3_600 / 60
    let remainder = seconds % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
    return String(format: "%02d:%02d", minutes, remainder)
}
