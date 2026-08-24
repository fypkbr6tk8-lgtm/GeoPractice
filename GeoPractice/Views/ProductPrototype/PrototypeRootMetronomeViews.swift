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
        ZStack {
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

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
                        .prototypeGlassControl(cornerRadius: 16)
                }
                .buttonStyle(LiquidPressButtonStyle())
                .foregroundStyle(GeoTheme.text)
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
        PrototypeGlassControl {
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
                .foregroundStyle(selection == tab ? GeoTheme.text : GeoTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44)
                .prototypeGlassSelection(selection == tab)
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
                    let isCompactHeight = proxy.size.height < 700
                    let contentSpacing: CGFloat = isCompactHeight ? 10 : 16
                    let stageRatio: CGFloat = isCompactHeight ? 0.30 : 0.37
                    let stageMaximum: CGFloat = isCompactHeight ? 230 : 340
                    let stageHeight = max(185, min(stageMaximum, proxy.size.height * stageRatio))

                    ScrollView {
                        VStack(spacing: contentSpacing) {
                            contextHeader
                            PrototypePulseStage(
                                beats: beats,
                                bpm: bpm,
                                trainingNote: trainingNote,
                                referenceNote: referenceNote,
                                isPlaying: isPlaying
                            )
                            .frame(height: stageHeight)
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
                        .padding(.top, isCompactHeight ? 2 : 8)
                        .padding(.bottom, isCompactHeight ? 10 : 24)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenSettings) {
                        PrototypeToolbarIconLabel(systemName: "line.3.horizontal")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .accessibilityLabel("更多设置")
                }
                .prototypeHidesSharedToolbarBackground()
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
                        PrototypeToolbarIconLabel(systemName: "checkmark")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                    .accessibilityLabel("练习完毕")
                }
                .prototypeHidesSharedToolbarBackground()
            }
            .prototypeNavigationBarGlassBackground()
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
        .prototypeGlassControl(cornerRadius: 18)
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
                    .foregroundStyle(selectedHand == hand ? GeoTheme.text : GeoTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .prototypeGlassSelection(selectedHand == hand)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedHand == hand ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            PrototypeGlassControl {
                Color.clear
            }
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
    let trainingNote: String
    let referenceNote: String?
    let isPlaying: Bool

    @State private var eventPositionAtAnchor = 0.0
    @State private var eventAnchorDate = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !isPlaying)) { timeline in
            let count = min(9, max(3, beats))
            let pulsesPerBeat = prototypePulsesPerBeat
            let eventsPerMeasure = count * pulsesPerBeat
            let eventInterval = prototypeEventInterval(
                bpm: bpm,
                pulsesPerBeat: pulsesPerBeat,
                referenceNote: referenceNote
            )
            let elapsedSinceAnchor = isPlaying
                ? max(0, timeline.date.timeIntervalSince(eventAnchorDate))
                : 0
            let rawEvent = max(
                0,
                eventPositionAtAnchor + elapsedSinceAnchor / eventInterval
            )
            let absoluteEvent = max(0, Int(floor(rawEvent)))
            let measure = absoluteEvent / eventsPerMeasure
            let eventInMeasure = absoluteEvent % eventsPerMeasure
            let beatIndex = eventInMeasure / pulsesPerBeat
            let subdivision = eventInMeasure % pulsesPerBeat
            let eventProgress = rawEvent - floor(rawEvent)

            Canvas { context, size in
                let radius = min(size.width, size.height) * 0.32
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let halfInteriorAngle = Double.pi / Double(count)
                let apothem = radius * CGFloat(cos(halfInteriorAngle))
                let halfEdge = radius * CGFloat(sin(halfInteriorAngle))
                let baselineY = center.y + apothem
                let step = CGFloat.pi * 2 / CGFloat(count)
                let transition = smoothStep(min(1, eventProgress / 0.56))
                let isBeatBoundary = subdivision == 0

                if isBeatBoundary, beatIndex > 0, transition < 1 {
                    for oldSlot in 0..<beatIndex {
                        drawPrototypeEdge(
                            slot: CGFloat(oldSlot) + transition,
                            center: center,
                            baselineY: baselineY,
                            halfEdge: halfEdge,
                            step: step,
                            opacity: 0.38,
                            progress: 1,
                            in: &context
                        )
                    }
                    drawPrototypeEdge(
                        slot: 0,
                        center: center,
                        baselineY: baselineY,
                        halfEdge: halfEdge,
                        step: step,
                        opacity: 0.76,
                        progress: transition,
                        in: &context
                    )
                } else {
                    let creationProgress: CGFloat = isPlaying
                        && measure > 0
                        && beatIndex == 0
                        && subdivision == 0
                        ? transition
                        : 1
                    for slot in 0...beatIndex {
                        drawPrototypeEdge(
                            slot: CGFloat(slot),
                            center: center,
                            baselineY: baselineY,
                            halfEdge: halfEdge,
                            step: step,
                            opacity: slot == 0 ? 0.76 : 0.38,
                            progress: slot == 0 ? creationProgress : 1,
                            in: &context
                        )
                    }
                }

                let normalizedHeight: Double
                if let target = BeatBounceMotionModel.nextTarget(
                    afterBeat: beatIndex,
                    subdivision: subdivision,
                    beats: count,
                    pulsesPerBeat: pulsesPerBeat,
                    strongBeatIndices: [0],
                    secondaryAccentIndices: count == 4 ? [2] : []
                ) {
                    normalizedHeight = BeatBounceMotionModel.normalizedEventHeight(
                        eventProgress: eventProgress,
                        toward: target.heightTier,
                        startsFromOrigin: absoluteEvent == 0
                    )
                } else {
                    normalizedHeight = 0
                }
                let pulse = 6.4 + CGFloat(normalizedHeight) * 1.8
                let inwardOffset = BeatBounceContactGeometry.inwardOffset(
                    edgeToCenterDistance: Double(apothem),
                    ballRadius: Double(pulse),
                    edgeStrokeWidth: 2,
                    normalizedHeight: normalizedHeight
                )
                let position = CGPoint(
                    x: center.x,
                    y: baselineY - CGFloat(inwardOffset)
                )
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
        .onAppear {
            eventAnchorDate = .now
        }
        .onChange(of: isPlaying) { wasPlaying, nowPlaying in
            let now = Date.now
            if wasPlaying {
                freezePrototypePosition(
                    at: now,
                    bpm: bpm,
                    pulsesPerBeat: prototypePulsesPerBeat,
                    referenceNote: referenceNote
                )
            }
            if nowPlaying {
                eventAnchorDate = now
            }
        }
        .onChange(of: bpm) { previousBPM, _ in
            guard isPlaying else { return }
            freezePrototypePosition(
                at: .now,
                bpm: previousBPM,
                pulsesPerBeat: prototypePulsesPerBeat,
                referenceNote: referenceNote
            )
        }
        .onChange(of: referenceNote) { previousReference, _ in
            guard isPlaying else { return }
            freezePrototypePosition(
                at: .now,
                bpm: bpm,
                pulsesPerBeat: prototypePulsesPerBeat,
                referenceNote: previousReference
            )
        }
        .onChange(of: beats) { _, _ in resetPrototypeClock() }
        .onChange(of: trainingNote) { _, _ in resetPrototypeClock() }
        .background(
            RadialGradient(
                colors: [Color.white.opacity(isPlaying ? 0.075 : 0.035), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 220
            )
        )
    }

    private var prototypePulsesPerBeat: Int {
        if trainingNote.contains("十六") { return 4 }
        if trainingNote.contains("八") { return 2 }
        return 1
    }

    private func resetPrototypeClock() {
        eventPositionAtAnchor = 0
        eventAnchorDate = .now
    }

    private func freezePrototypePosition(
        at date: Date,
        bpm: Int,
        pulsesPerBeat: Int,
        referenceNote: String?
    ) {
        let interval = prototypeEventInterval(
            bpm: bpm,
            pulsesPerBeat: pulsesPerBeat,
            referenceNote: referenceNote
        )
        eventPositionAtAnchor += max(0, date.timeIntervalSince(eventAnchorDate)) / interval
        eventAnchorDate = date
    }

    private func prototypeEventInterval(
        bpm: Int,
        pulsesPerBeat: Int,
        referenceNote: String?
    ) -> TimeInterval {
        let referenceDensity: Double
        if referenceNote?.contains("二分") == true {
            referenceDensity = 0.5
        } else if referenceNote?.contains("八分") == true {
            referenceDensity = 2
        } else {
            referenceDensity = 1
        }
        return 60 / Double(max(30, bpm))
            * referenceDensity / Double(max(1, pulsesPerBeat))
    }

    private func drawPrototypeEdge(
        slot: CGFloat,
        center: CGPoint,
        baselineY: CGFloat,
        halfEdge: CGFloat,
        step: CGFloat,
        opacity: Double,
        progress: CGFloat,
        in context: inout GraphicsContext
    ) {
        let midpoint = CGPoint(x: center.x, y: baselineY)
        let unrotatedStart = CGPoint(x: center.x - halfEdge, y: baselineY)
        let unrotatedEnd = CGPoint(x: center.x + halfEdge, y: baselineY)
        let start = rotate(unrotatedStart, around: center, angle: slot * step)
        let fullEnd = rotate(unrotatedEnd, around: center, angle: slot * step)
        let rotatedMidpoint = rotate(midpoint, around: center, angle: slot * step)
        let clampedProgress = min(1, max(0, progress))
        let drawnStart = interpolate(
            from: rotatedMidpoint,
            to: start,
            progress: clampedProgress
        )
        let drawnEnd = interpolate(
            from: rotatedMidpoint,
            to: fullEnd,
            progress: clampedProgress
        )
        guard clampedProgress > 0.001 else { return }

        var path = Path()
        path.move(to: drawnStart)
        path.addLine(to: drawnEnd)
        context.stroke(
            path,
            with: .color(.white.opacity(opacity)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    private func rotate(_ point: CGPoint, around center: CGPoint, angle: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(angle) - dy * sin(angle),
            y: center.y + dx * sin(angle) + dy * cos(angle)
        )
    }

    private func interpolate(
        from start: CGPoint,
        to end: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let clamped = min(1, max(0, value))
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
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
            .prototypeGlassControl(cornerRadius: 14)
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
                        .frame(width: 44, height: 44)
                        .prototypeGlassControl()
                }
                Text("\(bpm)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 31)
                Button { bpm = min(240, bpm + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .prototypeGlassControl()
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 5)
        .prototypeGlassControl(cornerRadius: 14)
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
                    Button { dismiss() } label: {
                        PrototypeToolbarTextLabel(title: "完成")
                    }
                    .buttonStyle(PrototypeGlassPressButtonStyle())
                }
                .prototypeHidesSharedToolbarBackground()
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
