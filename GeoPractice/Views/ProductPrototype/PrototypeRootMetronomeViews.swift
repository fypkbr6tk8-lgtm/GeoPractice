import SwiftUI

/// A runnable product prototype. Every value in this subtree is in-memory and
/// deliberately isolated from SwiftData until the information architecture is
/// approved by the product owner.
struct ProductPrototypeRootView: View {
    @State private var selectedTab: ProductPrototypeTab = .practice
    @State private var practiceLaunch: PrototypePracticeLaunch?
    @State private var showsSettings = false
    @State private var showsCurrentApp = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep all three prototype branches mounted. Mock edits, filters and
            // navigation stacks therefore survive tab changes during the same
            // review session even though nothing is persisted across launches.
            PrototypeStatisticsView()
                .prototypeTabVisibility(selectedTab == .statistics)

            PrototypePracticeView { launch in
                practiceLaunch = launch
                withAnimation(.snappy(duration: 0.22)) {
                    selectedTab = .metronome
                }
            }
            .prototypeTabVisibility(selectedTab == .practice)

            PrototypeMetronomeView(
                launch: $practiceLaunch,
                onOpenSettings: { showsSettings = true }
            )
            .prototypeTabVisibility(selectedTab == .metronome)

            ProductPrototypeTabBar(selection: $selectedTab)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .zIndex(10)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            PrototypeSettingsView {
                showsSettings = false
                showsCurrentApp = true
            }
        }
        .fullScreenCover(isPresented: $showsCurrentApp) {
            ZStack(alignment: .topTrailing) {
                RootView()
                Button {
                    showsCurrentApp = false
                } label: {
                    Label("返回产品原型", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 8)
                .padding(.trailing, 12)
                .accessibilityHint("关闭当前正式功能并回到 Mock 产品原型")
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct ProductPrototypeTabBar: View {
    @Binding var selection: ProductPrototypeTab

    var body: some View {
        GeoGlassCapsule {
            HStack(spacing: 4) {
                tabButton(.statistics, title: "统计", symbol: "chart.bar.xaxis")
                tabButton(.practice, title: "打卡+", symbol: "checkmark.circle")
                tabButton(.metronome, title: "节拍器", symbol: "metronome")
            }
            .padding(5)
        }
        .frame(maxWidth: 520)
    }

    private func tabButton(
        _ tab: ProductPrototypeTab,
        title: String,
        symbol: String
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                selection = tab
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(selection == tab ? .black : GeoTheme.text)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if selection == tab {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.92))
                            .matchedGeometryEffectFallback(id: title)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}

private extension View {
    /// Keeps the prototype source compatible with all toolchains used by the
    /// project while documenting the intended selection transition.
    @ViewBuilder
    func matchedGeometryEffectFallback(id: String) -> some View {
        self
    }

    func prototypeTabVisibility(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .zIndex(isVisible ? 1 : 0)
    }
}

private struct PrototypeMetronomeView: View {
    @Binding var launch: PrototypePracticeLaunch?
    let onOpenSettings: () -> Void

    @State private var pieceName = "自由练习"
    @State private var sectionName = "未选择曲目"
    @State private var bpm = 120
    @State private var beats = 4
    @State private var trainingNote = "八分音符"
    @State private var referenceNote: String? = "四分音符"
    @State private var selectedHand: PrototypePracticeHand = .left
    @State private var completedByHand: [PrototypePracticeHand: Int] = [:]
    @State private var targetByHand: [PrototypePracticeHand: Int] = [:]
    @State private var isPlaying = false
    @State private var showsSummary = false
    @State private var didLoadLaunch = false

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()

                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 18) {
                            contextHeader
                            PrototypePulseStage(
                                beats: beats,
                                bpm: bpm,
                                isPlaying: isPlaying
                            )
                            .frame(height: max(250, min(430, proxy.size.height * 0.48)))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.2)) {
                                    isPlaying.toggle()
                                }
                            }
                            .accessibilityLabel(isPlaying ? "节拍器正在运行" : "节拍器已暂停")
                            .accessibilityHint("轻点切换运行状态")

                            parameterControls
                            countControl
                            handControl
                            statusHint
                        }
                        .frame(maxWidth: 720)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 112)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenSettings) {
                        Image(systemName: "line.3.horizontal")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("更多设置")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("GEOBEAT")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .tracking(1.6)
                        Text("交互原型")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(GeoTheme.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPlaying = false
                        showsSummary = true
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("练习完毕")
                }
            }
            .toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear(perform: loadLaunchIfNeeded)
        .onChange(of: launch) { _, _ in
            didLoadLaunch = false
            loadLaunchIfNeeded()
        }
        .sheet(isPresented: $showsSummary) {
            PrototypePracticeSummarySheet(
                pieceName: pieceName,
                sectionName: sectionName,
                hand: selectedHand,
                completed: completedCount,
                target: targetByHand[selectedHand],
                bpm: bpm
            )
        }
    }

    private var contextHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pieceName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(sectionName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GeoTheme.muted)
            }
            Spacer()
            Text(isPlaying ? "节拍运行" : "轻点舞台开始")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isPlaying ? .white : GeoTheme.muted)
        }
        .padding(.horizontal, 4)
    }

    private var parameterControls: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 142, maximum: 220), spacing: 8)],
            spacing: 8
        ) {
            parameterTiles
        }
    }

    @ViewBuilder
    private var parameterTiles: some View {
        PrototypeParameterMenu(
            title: "拍数",
            value: "\(beats)",
            symbol: "circle.grid.cross"
        ) {
            ForEach(3...9, id: \.self) { value in
                Button("\(value) 拍") { beats = value }
            }
        }

        PrototypeTempoTile(bpm: $bpm)

        PrototypeParameterMenu(
            title: "训练音符",
            value: trainingNote.replacingOccurrences(of: "音符", with: ""),
            symbol: "music.note"
        ) {
            ForEach(["四分音符", "八分音符", "十六分音符"], id: \.self) { value in
                Button(value) { trainingNote = value }
            }
        }

        if referenceNote != nil {
            PrototypeParameterMenu(
                title: "基准音符 · PRO",
                value: referenceNote?.replacingOccurrences(of: "音符", with: "") ?? "—",
                symbol: "metronome"
            ) {
                ForEach(["二分音符", "四分音符", "八分音符"], id: \.self) { value in
                    Button(value) { referenceNote = value }
                }
            }
        }
    }

    private var countControl: some View {
        Button {
            completedByHand[selectedHand, default: 0] += 1
        } label: {
            HStack {
                Text(selectedHand.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GeoTheme.muted)
                Spacer()
                Text(countDisplay)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .monospacedDigit()
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .bold))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
        }
        .buttonStyle(.plain)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityLabel("为\(selectedHand.title)记录一次练习，当前\(countDisplay)")
    }

    private var handControl: some View {
        HStack(spacing: 4) {
            ForEach(PrototypePracticeHand.allCases) { hand in
                Button {
                    selectedHand = hand
                } label: {
                    VStack(spacing: 2) {
                        Text(hand.shortTitle)
                            .font(.system(size: 14, weight: .black))
                        Text(hand.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(selectedHand == hand ? .black : GeoTheme.text)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        selectedHand == hand ? Color.white.opacity(0.92) : Color.clear,
                        in: Capsule(style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedHand == hand ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.055), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var statusHint: some View {
        Text("原型说明：参数、计次和跳转可操作；本页不会播放声音，也不会写入正式练习记录。")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(GeoTheme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var countDisplay: String {
        if let targetCount = targetByHand[selectedHand] {
            "\(completedCount)/\(targetCount)"
        } else {
            "+1"
        }
    }

    private var completedCount: Int {
        completedByHand[selectedHand, default: 0]
    }

    private func loadLaunchIfNeeded() {
        guard !didLoadLaunch else { return }
        didLoadLaunch = true
        guard let launch else { return }
        pieceName = launch.pieceName
        sectionName = launch.sectionName
        bpm = launch.bpm
        beats = launch.beats
        trainingNote = launch.trainingNote
        referenceNote = launch.referenceNote
        completedByHand = launch.completedByHand
        targetByHand = launch.targetByHand
    }
}

private struct PrototypePulseStage: View {
    let beats: Int
    let bpm: Int
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let beatDuration = 60.0 / Double(max(30, bpm))
            let rawPhase = isPlaying ? seconds / beatDuration : 0
            let beatIndex = Int(rawPhase.rounded(.down)) % max(3, beats)
            let localPhase = rawPhase - rawPhase.rounded(.down)

            Canvas { context, size in
                let count = max(3, beats)
                let radius = min(size.width, size.height) * 0.32
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let points = (0..<count).map { index in
                    let angle = -Double.pi / 2 + Double(index) / Double(count) * 2 * Double.pi
                    return CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                }

                var polygon = Path()
                polygon.move(to: points[0])
                for point in points.dropFirst() { polygon.addLine(to: point) }
                polygon.closeSubpath()
                context.stroke(
                    polygon,
                    with: .color(.white.opacity(0.26)),
                    style: StrokeStyle(lineWidth: 2, lineJoin: .round)
                )

                for (index, point) in points.enumerated() {
                    let active = index == beatIndex
                    let anchorRadius: CGFloat = active ? 7 : 4
                    let rect = CGRect(
                        x: point.x - anchorRadius,
                        y: point.y - anchorRadius,
                        width: anchorRadius * 2,
                        height: anchorRadius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(active ? 0.95 : 0.34))
                    )
                }

                let nextIndex = (beatIndex + 1) % count
                let start = points[beatIndex]
                let end = points[nextIndex]
                let position = CGPoint(
                    x: start.x + (end.x - start.x) * localPhase,
                    y: start.y + (end.y - start.y) * localPhase
                )
                let pulse = 8 + CGFloat(sin(localPhase * Double.pi)) * 2
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: position.x - pulse,
                        y: position.y - pulse,
                        width: pulse * 2,
                        height: pulse * 2
                    )),
                    with: .color(.white.opacity(0.96))
                )
            }
        }
        .background(
            RadialGradient(
                colors: [Color.white.opacity(isPlaying ? 0.075 : 0.035), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 220
            )
        )
    }
}

private struct PrototypeParameterMenu<MenuContent: View>: View {
    let title: String
    let value: String
    let symbol: String
    @ViewBuilder let menuContent: MenuContent

    var body: some View {
        Menu {
            menuContent
        } label: {
            VStack(spacing: 5) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(GeoTheme.muted)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(GeoTheme.text)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 7)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
    }
}

private struct PrototypeTempoTile: View {
    @Binding var bpm: Int
    @State private var dragStart: Int?

    var body: some View {
        VStack(spacing: 4) {
            Text("BPM")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(GeoTheme.muted)
            HStack(spacing: 5) {
                Button { bpm = max(30, bpm - 1) } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 36)
                }
                Text("\(bpm)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 31)
                Button { bpm = min(240, bpm + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 36)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 5)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = dragStart ?? bpm
                    dragStart = start
                    let primary = value.translation.width - value.translation.height
                    bpm = min(240, max(30, start + Int(primary / 4)))
                }
                .onEnded { _ in dragStart = nil }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("速度 \(bpm) BPM")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: bpm = min(240, bpm + 1)
            case .decrement: bpm = max(30, bpm - 1)
            @unknown default: break
            }
        }
    }
}

private struct PrototypePracticeSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let pieceName: String
    let sectionName: String
    let hand: PrototypePracticeHand
    let completed: Int
    let target: Int?
    let bpm: Int

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                        Text("练习结果预览")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                        Text("此结果只用于确认 UI，不会写入历史或统计。")
                            .font(.footnote)
                            .foregroundStyle(GeoTheme.muted)
                            .multilineTextAlignment(.center)

                        GeoCard {
                            VStack(alignment: .leading, spacing: 14) {
                                summaryRow("曲目", pieceName)
                                summaryRow("段落", sectionName)
                                summaryRow("手型", hand.title)
                                summaryRow("速度", "\(bpm) BPM")
                                summaryRow("本轮完成", target.map { "\(completed)/\($0)" } ?? "\(completed) 次")
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(GeoTheme.muted)
            Spacer()
            Text(value).fontWeight(.bold)
        }
        .font(.system(size: 13))
    }
}
