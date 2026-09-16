import Combine
import SwiftData
import SwiftUI
import UIKit

/// The shipping product interface. Every page in this tree reads and mutates
/// the same SwiftData-backed library and the same live metronome/session.
struct ProductPrototypeRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @AppStorage(PracticePreferenceKeys.continueAudioInBackground)
    private var continueAudioInBackground = true
    @AppStorage(PracticePreferenceKeys.keepScreenAwake)
    private var keepScreenAwake = false
    @AppStorage(PracticePreferenceKeys.defaultBPM)
    private var defaultBPM = PracticePreferencePolicy.defaultBPM
    @AppStorage(PracticePreferenceKeys.defaultBeats)
    private var defaultBeats = PracticePreferencePolicy.defaultBeats
    @AppStorage(PracticePreferenceKeys.metronomeSound)
    private var metronomeSoundRaw = PracticeMetronomeSound.penetratingWoodblock.rawValue
    @AppStorage(PracticePreferenceKeys.appearanceMode)
    private var appearanceModeRaw = PracticeAppearanceMode.dark.rawValue
    @AppStorage(PracticePreferenceKeys.restReminderEnabled)
    private var restReminderEnabled = false
    @AppStorage(PracticePreferenceKeys.restReminderMinutes)
    private var restReminderMinutes = PracticePreferencePolicy.defaultRestReminderMinutes

    @State private var selectedTab: ProductPrototypeTab = .practice
    @State private var practiceLaunch: PrototypePracticeLaunch?
    @State private var pendingPracticeLaunch: PrototypePracticeLaunch?
    @State private var showsSettings = false
    @State private var launchError: String?
    @State private var restReminderMessage: String?
    @State private var lastReminderElapsedMilliseconds: Int64 = 0
    @StateObject private var practiceStore = PracticeLibraryStore()
    @StateObject private var metronome = MetronomeEngine()
    @StateObject private var practiceSession = PracticeSessionController()
    @ObservedObject private var cloudSync = ICloudSyncService.shared
    private let checkpointTimer = Timer.publish(
        every: 15,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        // A stock TabView gets the system's own Liquid Glass tab bar for
        // free on iOS 26 (glass while content scrolls under it, opaque at
        // rest, selected tint shows through) - the exact behavior a
        // hand-rolled floating capsule can only approximate. Each branch
        // keeps its own NavigationStack/GeoBackground, and SwiftUI retains
        // all three tabs' state across switches the same way the previous
        // always-mounted ZStack did.
        TabView(selection: $selectedTab) {
            PrototypeStatisticsView(practiceStore: practiceStore)
                .tag(ProductPrototypeTab.statistics)
                .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }

            PrototypePracticeView(
                store: practiceStore
            ) { launch in
                requestPracticeLaunch(launch)
            }
            .tag(ProductPrototypeTab.practice)
            .tabItem { Label("打卡+", systemImage: "checkmark.circle") }

            PrototypeMetronomeView(
                launch: $practiceLaunch,
                engine: metronome,
                practiceSession: practiceSession,
                practiceStore: practiceStore,
                onOpenSettings: { showsSettings = true }
            )
            .tag(ProductPrototypeTab.metronome)
            .tabItem { Label("节拍器", systemImage: "metronome") }
        }
        .tint(GeoTheme.controlAccent)
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $showsSettings) {
            PrototypeSettingsView(practiceStore: practiceStore)
        }
        .confirmationDialog(
            "当前练习尚未处理完",
            isPresented: Binding(
                get: { pendingPracticeLaunch != nil },
                set: { if !$0 { pendingPracticeLaunch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("返回当前练习") {
                pendingPracticeLaunch = nil
                selectedTab = .metronome
            }
            if let pendingPracticeLaunch {
                Button("放弃本次并开始“\(pendingPracticeLaunch.sectionName)”", role: .destructive) {
                    practiceSession.reset()
                    metronome.stop()
                    self.pendingPracticeLaunch = nil
                    beginPractice(pendingPracticeLaunch)
                }
            }
            Button("取消", role: .cancel) { pendingPracticeLaunch = nil }
        } message: {
            Text("当前次数和时长尚未保存。请返回完成本轮，或明确放弃后开始新的练习。")
        }
        .alert("无法开始练习", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("好", role: .cancel) { launchError = nil }
        } message: {
            Text(launchError ?? "请稍后重试。")
        }
        .alert("休息提醒", isPresented: Binding(
            get: { restReminderMessage != nil },
            set: { if !$0 { restReminderMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { restReminderMessage = nil }
        } message: {
            Text(restReminderMessage ?? "建议稍作休息。")
        }
        .onAppear {
            do {
                try practiceStore.configure(modelContext: modelContext)
                cloudSync.start(store: practiceStore)
            } catch {
                launchError = error.localizedDescription
            }
            if let restoredPreset = practiceSession.sessionPreset {
                metronome.apply(restoredPreset)
            } else {
                var preset = MetronomePreset.standard
                preset.bpm = PracticePreferencePolicy.normalizedBPM(defaultBPM)
                preset.beats = PracticePreferencePolicy.normalizedBeats(defaultBeats)
                metronome.apply(preset)
            }
            metronome.setSoundProfile(selectedMetronomeSound)
            restorePersistedPracticeIfNeeded()
            synchronizeRuntimeState()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .metronome {
                metronome.pause()
                practiceSession.pause()
            }
            synchronizeRuntimeState()
        }
        .onChange(of: practiceSession.session) { _, _ in
            practiceStore.protectedEventID = protectedEventID
            cloudSync.retryNow()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
            if phase == .active {
                Task { await subscriptionStore.refreshEntitlements() }
            }
        }
        .onChange(of: metronome.isPlaying) { wasPlaying, isPlaying in
            if selectedTab == .metronome,
               wasPlaying,
               !isPlaying,
               practiceSession.session.isRunning {
                practiceSession.pause()
            }
            synchronizeRuntimeState()
        }
        .onChange(of: metronomeSoundRaw) { _, _ in
            metronome.setSoundProfile(selectedMetronomeSound)
        }
        .onChange(of: defaultBPM) { _, value in
            guard practiceSession.session.phase == .idle, practiceLaunch == nil else { return }
            metronome.setBPM(PracticePreferencePolicy.normalizedBPM(value))
        }
        .onChange(of: defaultBeats) { _, value in
            guard practiceSession.session.phase == .idle, practiceLaunch == nil else { return }
            metronome.setBeats(PracticePreferencePolicy.normalizedBeats(value))
        }
        .onChange(of: keepScreenAwake) { _, _ in
            synchronizeRuntimeState()
        }
        .onReceive(practiceStore.$lastErrorMessage.compactMap { $0 }) { message in
            launchError = message
        }
        .onReceive(checkpointTimer) { date in
            evaluateRestReminder(at: date)
            guard runtimePolicy.shouldPersistCheckpoint(
                sceneState: runtimeSceneState,
                isMetronomeSelected: selectedTab == .metronome,
                isMetronomePlaying: metronome.isPlaying,
                isPracticeRunning: practiceSession.session.isRunning
            ) else { return }
            practiceSession.persistSnapshot(at: date)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func requestPracticeLaunch(_ launch: PrototypePracticeLaunch) {
        switch practiceSession.session.phase {
        case .idle:
            beginPractice(launch)
        case .running, .paused, .finished:
            pendingPracticeLaunch = launch
        }
    }

    /// Reconnects the durable session draft to its persisted section. The
    /// draft intentionally stores UUIDs rather than model objects, so it can
    /// survive process termination and SwiftData context recreation.
    private func restorePersistedPracticeIfNeeded() {
        guard practiceSession.session.phase != .idle else { return }

        if let eventID = practiceSession.session.sourceEventID {
            guard let restoredLaunch = practiceStore.launch(eventID: eventID) else {
                practiceSession.reset()
                practiceStore.protectedEventID = nil
                launchError = "上次练习对应的段落已不存在，未保存的会话已安全丢弃。"
                return
            }
            practiceLaunch = restoredLaunch
            practiceStore.protectedEventID = eventID
        } else {
            // Free practice has no library identity, but its timer/count draft
            // remains valid and can still be reviewed or discarded.
            practiceLaunch = nil
            practiceStore.protectedEventID = nil
        }
        selectedTab = .metronome
    }

    private func beginPractice(_ launch: PrototypePracticeLaunch, at date: Date = .now) {
        do {
            let goalContext: PracticeGoalLaunchContext?
            if let eventID = launch.eventID {
                goalContext = try practiceStore.goalLaunchContext(
                    eventID: eventID,
                    at: date,
                    timeZone: .autoupdatingCurrent
                )
            } else {
                goalContext = nil
            }

            let initialPreset = launch.preset
            metronome.apply(initialPreset)
            practiceSession.begin(
                sourceEventID: launch.eventID,
                preset: initialPreset,
                goalContext: goalContext,
                initialHand: .left,
                at: date
            )
            // The session becomes active only when the user starts audible
            // playback; time spent reading the screen is not practice time.
            practiceSession.pause(at: date)
            practiceLaunch = launch
            practiceStore.protectedEventID = launch.eventID
            withAnimation(.snappy(duration: 0.22)) {
                selectedTab = .metronome
            }
        } catch {
            launchError = error.localizedDescription
        }
    }

    private var protectedEventID: UUID? {
        switch practiceSession.session.phase {
        case .idle: nil
        case .running, .paused, .finished:
            practiceSession.session.sourceEventID
        }
    }

    private var runtimePolicy: PracticeRuntimePolicy {
        PracticeRuntimePolicy(
            continueAudioInBackground: continueAudioInBackground,
            keepScreenAwake: keepScreenAwake
        )
    }

    private var selectedMetronomeSound: PracticeMetronomeSound {
        PracticeMetronomeSound(rawValue: metronomeSoundRaw) ?? .penetratingWoodblock
    }

    private var preferredColorScheme: ColorScheme? {
        switch PracticeAppearanceMode(rawValue: appearanceModeRaw) ?? .dark {
        case .followSystem:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    private func evaluateRestReminder(at date: Date) {
        guard selectedTab == .metronome else {
            lastReminderElapsedMilliseconds = 0
            return
        }
        let elapsed = PracticeHand.allCases.reduce(Int64(0)) { result, hand in
            let value = practiceSession.session.stats(for: hand, at: date)
                .durationMilliseconds
            let (sum, overflowed) = result.addingReportingOverflow(value)
            return overflowed ? Int64.max : sum
        }
        let policy = PracticeRestReminderPolicy(
            isEnabled: restReminderEnabled,
            intervalMinutes: restReminderMinutes
        )
        if policy.shouldRemind(
            previousElapsedMilliseconds: lastReminderElapsedMilliseconds,
            currentElapsedMilliseconds: elapsed
        ) {
            restReminderMessage = "你已经连续练习约 \(policy.intervalMinutes) 分钟，建议放松手腕和肩颈。"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        lastReminderElapsedMilliseconds = elapsed
    }

    private var runtimeSceneState: PracticeRuntimePolicy.SceneState {
        switch scenePhase {
        case .active: .active
        case .inactive: .inactive
        case .background: .background
        @unknown default: .inactive
        }
    }

    private func handleScenePhase(_ phase: ScenePhase, at date: Date = .now) {
        switch phase {
        case .inactive:
            cloudSync.syncBeforeBackgrounding()
            if runtimePolicy.shouldPauseWhenEnteringInactive(
                isMetronomeSelected: selectedTab == .metronome,
                isMetronomePlaying: metronome.isPlaying,
                isPracticeRunning: practiceSession.session.isRunning
            ) {
                practiceSession.pause(at: date)
            }
            practiceSession.persistSnapshot(at: date)
        case .background:
            cloudSync.syncBeforeBackgrounding()
            if runtimePolicy.backgroundAction(
                isMetronomeSelected: selectedTab == .metronome,
                isMetronomePlaying: metronome.isPlaying
            ) == .stopAndPause {
                metronome.pause()
                practiceSession.pause(at: date)
            }
            practiceSession.persistSnapshot(at: date)
        case .active:
            cloudSync.syncWhenAppBecomesActive()
        @unknown default:
            practiceSession.persistSnapshot(at: date)
        }
        synchronizeRuntimeState()
    }

    private func synchronizeRuntimeState() {
        let shouldDisable = runtimePolicy.shouldDisableIdleTimer(
            sceneState: runtimeSceneState,
            isMetronomeSelected: selectedTab == .metronome,
            isMetronomePlaying: metronome.isPlaying
        )
        if UIApplication.shared.isIdleTimerDisabled != shouldDisable {
            UIApplication.shared.isIdleTimerDisabled = shouldDisable
        }
    }
}

private enum PrototypeMetronomeLayout {
    static let horizontalInset: CGFloat = 16
    static let maxContentWidth: CGFloat = 720
    static let controlSpacing: CGFloat = 8
    static let controlHeight: CGFloat = 58
    static let cardCornerRadius: CGFloat = 18
    static let selectionInset: CGFloat = 4
    static let selectionCornerRadius: CGFloat = cardCornerRadius - selectionInset

    static func minimumStageHeight(isLandscape: Bool) -> CGFloat {
        isLandscape ? 150 : 200
    }
}

/// Measures the header and controls first, then gives the animation all
/// remaining viewport height. If accessibility text or a compact landscape
/// needs more room, the stage keeps a safe minimum and the enclosing
/// ScrollView becomes the fallback instead of clipping controls.
private struct PrototypeMetronomeContentLayout: Layout {
    let viewportHeight: CGFloat
    let spacing: CGFloat
    let minimumStageHeight: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let childProposal = ProposedViewSize(width: proposal.width, height: nil)
        let headerSize = subviews[0].sizeThatFits(childProposal)
        let lowerSize = subviews[2].sizeThatFits(childProposal)
        let fixedHeight = headerSize.height + lowerSize.height + spacing * 2
        let stageHeight = max(minimumStageHeight, viewportHeight - fixedHeight)
        let contentHeight = max(viewportHeight, fixedHeight + stageHeight)
        let width = proposal.width ?? max(headerSize.width, lowerSize.width)
        return CGSize(width: width, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        guard subviews.count == 3 else { return }
        let widthProposal = ProposedViewSize(width: bounds.width, height: nil)
        let headerSize = subviews[0].sizeThatFits(widthProposal)
        let lowerSize = subviews[2].sizeThatFits(widthProposal)
        let fixedHeight = headerSize.height + lowerSize.height + spacing * 2
        let stageHeight = max(minimumStageHeight, viewportHeight - fixedHeight)

        var y = bounds.minY
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: headerSize.height)
        )
        y += headerSize.height + spacing
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: stageHeight)
        )
        y += stageHeight + spacing
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: lowerSize.height)
        )
    }
}

/// The product count button represents one completed practice repetition.
/// Meter and subdivision describe playback only and must never scale this
/// mutation.
enum PrototypePracticeCountAction {
    @MainActor
    static func recordOne(
        on session: PracticeSessionController,
        for hand: PracticeHand,
        preset: MetronomePreset,
        at date: Date = .now
    ) {
        session.recordCompletion(for: hand, preset: preset, at: date)
    }
}

/// Keeps the visual count independent from meter and subdivision semantics.
/// A free practice has no task context, so its compact counter is deliberately
/// numeric-only; assigned practice keeps the existing goal/unit wording.
enum PrototypePracticeCountDisplay {
    static func text(
        completed: Int,
        target: Int?,
        hasAssignedTask: Bool
    ) -> String {
        let safeCompleted = max(0, completed)
        guard hasAssignedTask else { return safeCompleted.formatted() }
        if let target {
            return "\(safeCompleted)/\(max(0, target))"
        }
        return "\(safeCompleted.formatted()) 次"
    }
}

private struct PrototypeMetronomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @AppStorage(PracticePreferenceKeys.buttonHapticsEnabled)
    private var buttonHapticsEnabled = true
    @AppStorage(PracticePreferenceKeys.beatVibrationEnabled)
    private var beatVibrationEnabled = false

    @Binding var launch: PrototypePracticeLaunch?
    @ObservedObject var engine: MetronomeEngine
    @ObservedObject var practiceSession: PracticeSessionController
    @ObservedObject var practiceStore: PracticeLibraryStore
    let onOpenSettings: () -> Void

    @State private var selectedHand: PrototypePracticeHand = .left
    @State private var showsSummary = false
    @State private var pendingSummary: PracticeSessionSummary?
    @State private var saveError: String?
    @State private var saveSuccessMessage: String?
    @State private var isSaving = false
    @State private var showsProPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()

                GeometryReader { proxy in
                    let isCompactHeight = proxy.size.height < 700
                    let usesWideControlGrid = proxy.size.width >= 640
                        && proxy.size.width > proxy.size.height
                    let contentSpacing: CGFloat = isCompactHeight ? 10 : 16
                    let topPadding: CGFloat = isCompactHeight ? 0 : 4
                    // TabView already reports a content-safe viewport above
                    // its native tab bar. A second tab-bar-sized inset used to
                    // reserve the same space again, leaving a large dead area
                    // below the controls. Keep only a small visual margin and
                    // give every other available point to the pulse stage.
                    let bottomPadding: CGFloat = isCompactHeight ? 4 : 8
                    let viewportHeight = max(
                        0,
                        proxy.size.height - topPadding - bottomPadding
                    )
                    let minimumStageHeight = PrototypeMetronomeLayout.minimumStageHeight(
                        isLandscape: proxy.size.width > proxy.size.height
                    )

                    ScrollView {
                        PrototypeMetronomeContentLayout(
                            viewportHeight: viewportHeight,
                            spacing: contentSpacing,
                            minimumStageHeight: minimumStageHeight
                        ) {
                            contextHeader
                            PrototypePulseStage(
                                preset: engine.preset,
                                pulse: engine.lastPulse,
                                isPlaying: engine.isPlaying
                            )
                            .id(practiceSession.session.sessionID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: togglePlayback)
                            .accessibilityLabel(engine.isPlaying ? "节拍器正在运行" : "节拍器已暂停")
                            .accessibilityHint("轻点切换运行状态")

                            VStack(spacing: contentSpacing) {
                                parameterControls(columnCount: usesWideControlGrid ? 4 : 2)
                                countControl
                                handControl
                                statusHint
                            }
                        }
                        .frame(maxWidth: PrototypeMetronomeLayout.maxContentWidth)
                        .padding(.horizontal, PrototypeMetronomeLayout.horizontalInset)
                        .padding(.top, topPadding)
                        .padding(.bottom, bottomPadding)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenSettings) {
                        GeoToolbarIconLabel(symbol: "line.3.horizontal")
                    }
                    .buttonStyle(LiquidPressButtonStyle())
                    .accessibilityLabel("更多设置")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("GEOBEAT")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .tracking(1.6)
                        Text(engine.isPlaying ? "正在练习" : "准备就绪")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(GeoTheme.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: finishCurrentSession) {
                        GeoToolbarIconLabel(symbol: "checkmark")
                    }
                    .buttonStyle(LiquidPressButtonStyle())
                    .accessibilityLabel("练习完毕")
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .toolbarBackground(GeoTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            synchronizeLaunch()
            synchronizeReferenceNoteAccess()
            presentRestoredSummaryIfNeeded()
        }
        .onChange(of: launch) { _, _ in synchronizeLaunch() }
        .onChange(of: subscriptionStore.accessState) { _, _ in
            synchronizeReferenceNoteAccess()
        }
        .onChange(of: engine.lastPulse) { _, pulse in
            guard beatVibrationEnabled, pulse?.subdivision == 0 else { return }
            UIImpactFeedbackGenerator(style: pulse?.kind == .strong ? .medium : .light)
                .impactOccurred()
        }
        .sheet(isPresented: $showsSummary) {
            if let pendingSummary {
                PrototypePracticeSummarySheet(
                    pieceName: pieceName,
                    sectionName: sectionName,
                    hand: selectedHand,
                    completed: totalCompletedCount,
                    target: launch?.targetByHand[selectedHand],
                    bpm: engine.preset.bpm,
                    durationMilliseconds: pendingSummary.totalDurationMilliseconds,
                    willSaveToLibrary: pendingSummary.sourceEventID != nil,
                    isSaving: isSaving,
                    onComplete: saveFinishedSession
                )
                .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $showsProPaywall) {
            NavigationStack {
                PrototypeProView()
            }
        }
        .alert("无法保存练习", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "请稍后重试。")
        }
        .alert("练习已保存", isPresented: Binding(
            get: { saveSuccessMessage != nil },
            set: { if !$0 { saveSuccessMessage = nil } }
        )) {
            Button("好", role: .cancel) { saveSuccessMessage = nil }
        } message: {
            Text(saveSuccessMessage ?? "本轮练习记录已写入曲目统计。")
        }
        .alert("节拍器声音错误", isPresented: Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { engine.errorMessage = nil }
        } message: {
            Text(engine.errorMessage ?? "声音暂时无法播放，请稍后重试。")
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
            Text(engine.isPlaying ? "节拍运行" : "轻点舞台开始")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(engine.isPlaying ? GeoTheme.text : GeoTheme.muted)
        }
        .padding(.horizontal, 4)
    }

    private func parameterControls(columnCount: Int) -> some View {
        VStack(spacing: PrototypeMetronomeLayout.controlSpacing) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .flexible(),
                        spacing: PrototypeMetronomeLayout.controlSpacing
                    ),
                    count: max(2, min(4, columnCount))
                ),
                spacing: PrototypeMetronomeLayout.controlSpacing
            ) {
                parameterTiles
            }

            let groupings = MetronomePreset.groupings(for: engine.preset.beats)
            if groupings.count > 1 {
                PrototypeBeatGroupingSelector(
                    options: groupings,
                    selection: engine.preset.grouping
                ) { grouping in
                    engine.setGrouping(grouping)
                    rememberCurrentPreset()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.22), value: engine.preset.beats)
    }

    @ViewBuilder
    private var parameterTiles: some View {
        PrototypeParameterMenu(
            title: "拍数",
            value: "\(engine.preset.beats)",
            symbol: "circle.grid.cross"
        ) {
            ForEach(3...9, id: \.self) { value in
                Button("\(value) 拍") {
                    engine.setBeats(value)
                    rememberCurrentPreset()
                }
            }
        }

        PrototypeTempoTile(bpm: Binding(
            get: { engine.preset.bpm },
            set: { value in
                engine.setBPM(value)
                rememberCurrentPreset()
            }
        ))

        PrototypeParameterMenu(
            title: "训练音符",
            value: trainingNote.replacingOccurrences(of: "音符", with: ""),
            symbol: "music.note"
        ) {
            ForEach(["四分音符", "八分音符", "十六分音符"], id: \.self) { value in
                Button(value) {
                    engine.setSubdivision(subdivision(for: value))
                    rememberCurrentPreset()
                }
            }
        }

        if subscriptionStore.isPro, let currentReferenceNote = referenceNote {
            PrototypeParameterMenu(
                title: "基准音符 · PRO",
                value: currentReferenceNote.replacingOccurrences(of: "音符", with: ""),
                symbol: "metronome"
            ) {
                ForEach(["二分音符", "四分音符", "八分音符"], id: \.self) { value in
                    Button(value) {
                        engine.setTempoReferenceNote(referenceNote(for: value))
                        rememberCurrentPreset()
                    }
                }
            }
        } else {
            PrototypeLockedParameterTile(
                title: "基准音符 · PRO",
                value: subscriptionStore.accessState == .checking ? "核对中" : "解锁",
                symbol: "lock.fill"
            ) {
                showsProPaywall = true
            }
        }
    }

    private var countControl: some View {
        Button {
            ensureSessionExists()
            PrototypePracticeCountAction.recordOne(
                on: practiceSession,
                for: selectedHand.practiceHand,
                preset: engine.effectivePlaybackPreset
            )
            if buttonHapticsEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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
            .frame(minHeight: PrototypeMetronomeLayout.controlHeight)
        }
        .buttonStyle(.plain)
        .prototypeGlassSurface(
            cornerRadius: PrototypeMetronomeLayout.cardCornerRadius,
            emphasized: true
        )
        .accessibilityLabel("为\(selectedHand.title)记录一次练习，当前\(countDisplay)")
    }

    private var handControl: some View {
        HStack(spacing: 4) {
            ForEach(PrototypePracticeHand.allCases) { hand in
                Button {
                    guard hand != selectedHand else { return }
                    selectedHand = hand
                    ensureSessionExists()
                    practiceSession.switchHand(to: hand.practiceHand)
                } label: {
                    VStack(spacing: 2) {
                        Text(hand.shortTitle)
                            .font(.system(size: 14, weight: .black))
                        Text(hand.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(
                        selectedHand == hand
                            ? GeoTheme.selectionText
                            : GeoTheme.text
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: PrototypeMetronomeLayout.controlHeight
                            - PrototypeMetronomeLayout.selectionInset * 2
                    )
                    .background(
                        selectedHand == hand ? GeoTheme.selectionFill : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius: PrototypeMetronomeLayout.selectionCornerRadius,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedHand == hand ? .isSelected : [])
            }
        }
        .padding(PrototypeMetronomeLayout.selectionInset)
        .background(
            RoundedRectangle(
                cornerRadius: PrototypeMetronomeLayout.cardCornerRadius,
                style: .continuous
            )
                .fill(GeoTheme.panel)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: PrototypeMetronomeLayout.cardCornerRadius,
                        style: .continuous
                    )
                        .stroke(GeoTheme.surfaceInk.opacity(0.06), lineWidth: 1)
                }
        )
    }

    private var statusHint: some View {
        Text(launch?.eventID == nil
            ? "自由练习会播放真实节拍声，但不会计入曲目统计；请从打卡页选择段落以保存记录。"
            : "完成后，本轮次数、时长、速度与目标进度会保存到当前段落。")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(GeoTheme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var countDisplay: String {
        PrototypePracticeCountDisplay.text(
            completed: totalCompletedCount,
            target: launch?.targetByHand[selectedHand],
            hasAssignedTask: launch?.eventID != nil
        )
    }

    private var sessionCompletedCount: Int {
        practiceSession.session.stats(
            for: selectedHand.practiceHand,
            at: .now
        ).count
    }

    private var totalCompletedCount: Int {
        (launch?.completedByHand[selectedHand] ?? 0) + sessionCompletedCount
    }

    private var pieceName: String { launch?.pieceName ?? "自由练习" }
    private var sectionName: String { launch?.sectionName ?? "未选择曲目" }

    private var trainingNote: String {
        switch engine.preset.subdivision {
        case 4: "十六分音符"
        case 2: "八分音符"
        case 0: "二分音符"
        default: "四分音符"
        }
    }

    private var referenceNote: String? {
        engine.preset.referenceNote.title
    }

    private func synchronizeLaunch() {
        if practiceSession.session.phase != .idle {
            // A durable in-progress session owns its live parameters. The
            // section preset may have changed since the draft was checkpointed
            // and must not overwrite the values the user was actually using.
            selectedHand = PrototypePracticeHand(practiceSession.session.currentHand)
            let activePreset = practiceSession.sessionPreset
                ?? launch?.preset
                ?? engine.preset
            engine.apply(activePreset)
            practiceSession.updateLivePreset(activePreset)
        } else if let launch {
            selectedHand = .left
            let initialPreset = launch.preset
            engine.apply(initialPreset)
        } else {
            selectedHand = .left
        }
        if practiceSession.session.phase == .running, !engine.isPlaying {
            practiceSession.pause()
        }
        if practiceSession.session.phase == .running
            || practiceSession.session.phase == .paused {
            practiceSession.switchHand(to: selectedHand.practiceHand)
        }
    }

    private func rememberCurrentPreset() {
        practiceSession.updateLivePreset(engine.effectivePlaybackPreset)
    }

    private func synchronizeReferenceNoteAccess() {
        engine.setPremiumReferenceNoteAccess(subscriptionStore.isPro)
        practiceSession.updateLivePreset(engine.effectivePlaybackPreset)
    }

    private func presentRestoredSummaryIfNeeded() {
        guard pendingSummary == nil,
              let restoredSummary = practiceSession.session.reviewSummary
        else { return }
        pendingSummary = restoredSummary
        showsSummary = true
    }

    private func ensureSessionExists() {
        switch practiceSession.session.phase {
        case .idle:
            practiceSession.begin(
                sourceEventID: launch?.eventID,
                preset: engine.effectivePlaybackPreset,
                initialHand: selectedHand.practiceHand
            )
            practiceSession.pause()
        case .finished:
            practiceSession.continueAfterReview()
            practiceSession.pause()
        case .running, .paused:
            break
        }
    }

    private func togglePlayback() {
        ensureSessionExists()
        if engine.isPlaying {
            engine.pause()
            practiceSession.pause()
        } else {
            practiceSession.resume()
            engine.start()
            if !engine.isPlaying {
                practiceSession.pause()
            }
        }
    }

    private func finishCurrentSession() {
        ensureSessionExists()
        engine.stop()
        guard let summary = practiceSession.finish() else { return }
        pendingSummary = summary
        showsSummary = true
    }

    private func saveFinishedSession() {
        guard let summary = pendingSummary, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let willSaveToLibrary = summary.sourceEventID != nil
            let savedDestination = "\(pieceName) · \(sectionName)"
            if summary.sourceEventID != nil {
                _ = try practiceStore.commit(summary: summary)
            }
            practiceSession.reset()
            pendingSummary = nil
            showsSummary = false
            launch = nil
            if willSaveToLibrary {
                saveSuccessMessage = "“\(savedDestination)”的练习记录已保存，统计与目标进度已更新。"
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func subdivision(for title: String) -> Int {
        if title.contains("十六") { return 4 }
        if title.contains("八") { return 2 }
        if title.contains("二分") { return 0 }
        return 1
    }

    private func referenceNote(for title: String) -> TempoReferenceNote {
        if title.contains("二分") { return .half }
        if title.contains("八分") { return .eighth }
        if title.contains("十六") { return .sixteenth }
        return .quarter
    }
}

private struct PrototypeStageContactGeometry {
    let start: CGPoint
    let end: CGPoint
    let point: CGPoint
    let inwardNormal: CGVector
    /// Distance from the boundary point along `inwardNormal` which keeps the
    /// entire ball outside every edge participating in a vertex contact.
    let minimumInwardOffset: CGFloat
    let edgeToCenterDistance: CGFloat
}

private struct PrototypePulseStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights

    let preset: MetronomePreset
    let pulse: BeatPlaybackPulse?
    let isPlaying: Bool

    /// Keep the renderer's committed preset in state so a beat-count change can
    /// reset the visual lifecycle and its scheduler cursor in one transaction.
    @State private var visualPreset: MetronomePreset
    @State private var lifecycle: BeatVisualLifecycle
    @State private var acceptedPulse: BeatPlaybackPulse?
    @State private var lastAcceptedAddress: BeatPresentationEventAddress?
    @State private var frozenAt: Date?
    @State private var frozenEdgePresentations: [BeatEdgePresentation]?
    @State private var frozenBallNormalizedHeight: Double?
    @State private var edgeResumeBridge: BeatEdgeResumeBridge?

    init(
        preset: MetronomePreset,
        pulse: BeatPlaybackPulse?,
        isPlaying: Bool
    ) {
        self.preset = preset
        self.pulse = pulse
        self.isPlaying = isPlaying
        let normalized = preset.normalized
        _visualPreset = State(initialValue: normalized)
        _lifecycle = State(initialValue: BeatVisualLifecycle(beats: normalized.beats))
    }

    var body: some View {
        let normalizedPreset = visualPreset.normalized
        let count = normalizedPreset.beats
        let safePulsesPerBeat = normalizedPreset.pulsesPerBeat

        TimelineView(.animation(paused: !isPlaying)) { timeline in
            let renderedPulse = acceptedPulse
            let beatIndex = min(count - 1, max(0, renderedPulse?.beat ?? 0))
            let subdivision = min(
                safePulsesPerBeat - 1,
                max(0, renderedPulse?.subdivision ?? 0)
            )
            let presentationDate = frozenAt ?? timeline.date
            let trainingEventProgress = eventProgress(
                for: renderedPulse,
                at: presentationDate
            )
            let intervalGeometry = renderedPulse.map {
                BeatPolygonPresentationModel.intervalGeometry(
                    lifecycle: lifecycle,
                    beat: $0.beat,
                    subdivision: $0.subdivision,
                    cycle: $0.cycle,
                    pulsesPerBeat: safePulsesPerBeat,
                    reduceMotion: reduceMotion
                )
            } ?? BeatVisualIntervalGeometry(
                placements: lifecycle.visibleEdgePlacements,
                transition: nil
            )
            let currentTransition = intervalGeometry.transition
            let targetPresentations: [BeatEdgePresentation] = BeatPolygonPresentationModel.edgePresentations(
                placements: intervalGeometry.placements,
                transition: currentTransition,
                eventProgress: trainingEventProgress,
                strongBeatIndices: normalizedPreset.strongBeatIndices,
                secondaryAccentIndices: normalizedPreset.secondaryAccentIndices,
                startsFromOrigin: false,
                reduceMotion: reduceMotion
            )
            let edgePresentations = resolvedPresentations(
                target: targetPresentations,
                pulse: renderedPulse,
                eventProgress: trainingEventProgress,
                preset: normalizedPreset
            )

            Canvas { context, size in
                let dimension = min(size.width, size.height)
                // The stage expands to the remaining device viewport. Scale
                // the complete visual system with it so the polygon, ball and
                // collision feedback retain the same proportions on compact
                // and large iPhones instead of only moving farther apart.
                let visualScale = min(1.55, max(0.86, dimension / 300))
                let safetyInset = max(14, dimension * 0.08)
                let radius = max(0, dimension / 2 - safetyInset)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let halfInteriorAngle = Double.pi / Double(count)
                let apothem = radius * CGFloat(cos(halfInteriorAngle))
                let halfEdge = radius * CGFloat(sin(halfInteriorAngle))
                let baselineY = center.y + apothem
                let step = CGFloat.pi * 2 / CGFloat(count)

                for edge in edgePresentations {
                    drawPrototypeEdge(
                        slot: CGFloat(edge.slot),
                        center: center,
                        baselineY: baselineY,
                        halfEdge: halfEdge,
                        step: step,
                        opacity: edge.opacity,
                        lineWidth: CGFloat(edge.lineWidth) * visualScale,
                        progress: CGFloat(edge.drawProgress),
                        in: &context
                    )
                }

                var targetBallNormalizedHeight = lifecycle.ballIsAtOrigin ? 1.0 : 0.0
                if let target = BeatBounceMotionModel.nextTarget(
                    afterBeat: beatIndex,
                    subdivision: subdivision,
                    beats: count,
                    pulsesPerBeat: safePulsesPerBeat,
                    strongBeatIndices: normalizedPreset.strongBeatIndices,
                    secondaryAccentIndices: normalizedPreset.secondaryAccentIndices
                ) {
                    targetBallNormalizedHeight = BeatBounceMotionModel.normalizedAudibleEventHeight(
                        eventProgress: trainingEventProgress,
                        toward: target.heightTier,
                        motionScale: reduceMotion ? 0.30 : 1
                    )
                }
                let normalizedHeight = resolvedBallNormalizedHeight(
                    targetHeight: targetBallNormalizedHeight,
                    pulse: renderedPulse,
                    eventProgress: trainingEventProgress
                )

                let feedbackStyle = renderedPulse.map {
                    BeatPulseVisualModel.style(
                        for: $0.kind,
                        eventInterval: $0.eventInterval,
                        dimFlashingLights: dimFlashingLights
                    )
                }
                let collisionAge = renderedPulse.map { value in
                    BeatCollisionVisualModel.collisionAge(
                        eventAge: presentationDate.timeIntervalSince(value.presentedAt),
                        eventInterval: value.eventInterval,
                        startsFromOrigin: false
                    )
                } ?? -.infinity
                let collisionDuration: TimeInterval
                if let renderedPulse, let feedbackStyle {
                    collisionDuration = BeatCollisionVisualModel.effectDuration(
                        styleDuration: feedbackStyle.duration,
                        eventInterval: renderedPulse.eventInterval,
                        startsFromOrigin: false
                    )
                } else {
                    collisionDuration = 0
                }
                let feedbackEnvelope = feedbackStyle.map { _ in
                    BeatPulseVisualModel.envelope(
                        age: collisionAge,
                        duration: collisionDuration
                    )
                } ?? 0
                let resumeBridgeMatchesPulse = renderedPulse.map { pulse in
                    edgeResumeBridge?.matches(
                        beat: pulse.beat,
                        subdivision: pulse.subdivision,
                        cycle: pulse.cycle,
                        sequence: pulse.sequence
                    ) ?? false
                } ?? false
                let suppressTransientCollision = frozenAt != nil
                    || resumeBridgeMatchesPulse
                let collisionSample: BeatCollisionVisualSample
                if isPlaying, let renderedPulse, feedbackStyle != nil {
                    collisionSample = BeatCollisionVisualModel.sample(
                        for: renderedPulse.kind,
                        age: collisionAge,
                        duration: collisionDuration,
                        reduceMotion: reduceMotion,
                        dimFlashingLights: dimFlashingLights,
                        suppressTransientFeedback: suppressTransientCollision
                    )
                } else {
                    collisionSample = .empty
                }
                let ballRadius: CGFloat = 6.4 * visualScale
                    + CGFloat(feedbackEnvelope)
                    * CGFloat(feedbackStyle?.peakOpacity ?? 0)
                    * CGFloat(1.35)
                    * visualScale
                let edgeStrokeWidth = BeatPolygonPresentationModel.contactLineWidth(
                    presentations: edgePresentations,
                    beatCount: count
                ) * Double(visualScale)
                let visibleClearance = ballRadius
                    + CGFloat(edgeStrokeWidth) / 2
                let contact = PrototypeStageContactGeometry(
                    start: CGPoint(x: center.x - halfEdge, y: baselineY),
                    end: CGPoint(x: center.x + halfEdge, y: baselineY),
                    point: CGPoint(x: center.x, y: baselineY),
                    inwardNormal: CGVector(dx: 0, dy: -1),
                    minimumInwardOffset: visibleClearance,
                    edgeToCenterDistance: apothem
                )
                let clampedHeight = CGFloat(min(1, max(0, normalizedHeight)))
                let restingPosition = CGPoint(
                    x: contact.point.x
                        + contact.inwardNormal.dx * contact.minimumInwardOffset,
                    y: contact.point.y
                        + contact.inwardNormal.dy * contact.minimumInwardOffset
                )
                let position = CGPoint(
                    x: restingPosition.x
                        + (center.x - restingPosition.x) * clampedHeight,
                    y: restingPosition.y
                        + (center.y - restingPosition.y) * clampedHeight
                )
                let inwardOffset = Double(
                    contact.minimumInwardOffset
                        + max(
                            0,
                            contact.edgeToCenterDistance
                                - contact.minimumInwardOffset
                        ) * clampedHeight
                )

                drawPrototypeCollision(
                    collisionSample,
                    contact: contact,
                    edgeStrokeWidth: CGFloat(edgeStrokeWidth),
                    in: &context
                )

                if let feedbackStyle, feedbackEnvelope > 0 {
                    let requestedHaloRadius = ballRadius
                        + CGFloat(feedbackStyle.peakRadius * feedbackEnvelope * 0.58)
                            * visualScale
                    let maximumHaloRadius = CGFloat(
                        BeatBounceContactGeometry.maximumNonPenetratingRadius(
                            inwardCenterOffset: inwardOffset,
                            edgeStrokeWidth: edgeStrokeWidth
                        )
                    )
                    let haloRadius = min(requestedHaloRadius, maximumHaloRadius)
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: position.x - haloRadius,
                            y: position.y - haloRadius,
                            width: haloRadius * 2,
                            height: haloRadius * 2
                        )),
                        with: .color(
                            Color(red: 0.70, green: 0.64, blue: 1)
                                .opacity(
                                    0.17
                                        * feedbackStyle.peakOpacity
                                        * feedbackEnvelope
                                )
                        )
                    )
                }
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: position.x - ballRadius,
                        y: position.y - ballRadius,
                        width: ballRadius * 2,
                        height: ballRadius * 2
                    )),
                    with: .color(GeoTheme.text.opacity(0.96))
                )
            }
        }
        .background {
            GeometryReader { proxy in
                let dimension = min(proxy.size.width, proxy.size.height)
                RadialGradient(
                    colors: [GeoTheme.surfaceInk.opacity(isPlaying ? 0.075 : 0.035), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(1, dimension * 0.56)
                )
            }
        }
        .onAppear {
            synchronizeBeatCount()
            frozenAt = isPlaying ? nil : .now
            consume(pulse)
            if !isPlaying, let frozenAt {
                freezePresentation(at: frozenAt)
            }
        }
        .onChange(of: preset) { _, nextPreset in
            synchronizePreset(nextPreset.normalized)
        }
        .onChange(of: pulse) { _, nextPulse in
            consume(nextPulse)
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                // Keep the captured presentation until the scheduler delivers
                // the next authoritative event that will drive the bridge.
                if frozenEdgePresentations == nil {
                    frozenAt = nil
                }
            } else {
                freezePresentation(at: .now)
            }
        }
    }

    private func synchronizePreset(_ nextPreset: MetronomePreset) {
        let current = visualPreset.normalized
        if nextPreset.beats != current.beats {
            visualPreset = nextPreset
            synchronizeBeatCount()
            return
        }

        visualPreset = nextPreset
        if nextPreset.pulsesPerBeat != current.pulsesPerBeat {
            resynchronizeSchedulePreservingGeometry()
        }
    }

    private func synchronizeBeatCount() {
        let beats = visualPreset.normalized.beats
        guard lifecycle.beatCount != beats else { return }
        lifecycle.reconfigure(beats: beats)
        acceptedPulse = nil
        lastAcceptedAddress = nil
        frozenEdgePresentations = nil
        frozenBallNormalizedHeight = nil
        edgeResumeBridge = nil
        frozenAt = isPlaying ? nil : .now
    }

    private func resynchronizeSchedulePreservingGeometry() {
        lifecycle.resetScheduleTopology(
            beats: visualPreset.normalized.beats,
            isPlaying: isPlaying
        )
        acceptedPulse = nil
        lastAcceptedAddress = nil
        frozenEdgePresentations = nil
        frozenBallNormalizedHeight = nil
        edgeResumeBridge = nil
        frozenAt = isPlaying ? nil : .now
    }

    private func consume(_ nextPulse: BeatPlaybackPulse?) {
        guard let nextPulse else {
            acceptedPulse = nil
            frozenEdgePresentations = nil
            frozenBallNormalizedHeight = nil
            edgeResumeBridge = nil
            return
        }

        if preset.normalized.beats != visualPreset.normalized.beats {
            // Publisher delivery order is not a rendering contract. Commit the
            // new topology before accepting the new scheduler's first pulse.
            synchronizePreset(preset.normalized)
        }
        synchronizeBeatCount()
        let nextAddress = eventAddress(nextPulse)
        // Sequence is local to one scheduler run and intentionally returns to
        // zero after pause -> start. Musical address is the only valid ordering
        // key; an explicit pulsesPerBeat change resets this cursor separately.
        guard lastAcceptedAddress.map({ $0 < nextAddress }) ?? true else { return }

        lifecycle.record(
            beat: nextPulse.beat,
            subdivision: nextPulse.subdivision,
            cycle: nextPulse.cycle,
            beats: visualPreset.normalized.beats,
            pulsesPerBeat: visualPreset.normalized.pulsesPerBeat
        )
        lastAcceptedAddress = nextAddress
        // The first pulse after resume is already audible and therefore owns a
        // real landing. Bridging from a paused mid-air frame would put that
        // sound ahead of the ball and edge again.
        edgeResumeBridge = nil
        frozenEdgePresentations = nil
        frozenBallNormalizedHeight = nil
        frozenAt = isPlaying ? nil : (frozenAt ?? .now)
        acceptedPulse = nextPulse
    }

    private func eventProgress(
        for pulse: BeatPlaybackPulse?,
        at date: Date
    ) -> Double {
        guard let pulse,
              pulse.eventInterval.isFinite,
              pulse.eventInterval > 0
        else { return 0 }
        return min(
            1,
            max(0, date.timeIntervalSince(pulse.presentedAt) / pulse.eventInterval)
        )
    }

    private func resolvedPresentations(
        target: [BeatEdgePresentation],
        pulse: BeatPlaybackPulse?,
        eventProgress: Double,
        preset: MetronomePreset
    ) -> [BeatEdgePresentation] {
        guard let pulse,
              let edgeResumeBridge,
              edgeResumeBridge.matches(
                beat: pulse.beat,
                subdivision: pulse.subdivision,
                cycle: pulse.cycle,
                sequence: pulse.sequence
              )
        else { return target }

        let geometry = BeatPolygonPresentationModel.intervalGeometry(
            lifecycle: lifecycle,
            beat: pulse.beat,
            subdivision: pulse.subdivision,
            cycle: pulse.cycle,
            pulsesPerBeat: preset.pulsesPerBeat,
            reduceMotion: reduceMotion
        )
        let destination = BeatPolygonPresentationModel.edgePresentations(
            placements: geometry.placements,
            transition: geometry.transition,
            eventProgress: 1,
            strongBeatIndices: preset.strongBeatIndices,
            secondaryAccentIndices: preset.secondaryAccentIndices,
            startsFromOrigin: false,
            reduceMotion: reduceMotion
        )
        return BeatPolygonPresentationModel.resumePresentations(
            from: edgeResumeBridge.sourcePresentations,
            toward: destination,
            beatCount: preset.beats,
            eventProgress: eventProgress,
            reduceMotion: reduceMotion
        )
    }

    private func presentedEdges(
        at date: Date,
        preset: MetronomePreset
    ) -> [BeatEdgePresentation] {
        let normalizedPreset = preset.normalized
        let renderedPulse = acceptedPulse
        let geometry = renderedPulse.map {
            BeatPolygonPresentationModel.intervalGeometry(
                lifecycle: lifecycle,
                beat: $0.beat,
                subdivision: $0.subdivision,
                cycle: $0.cycle,
                pulsesPerBeat: normalizedPreset.pulsesPerBeat,
                reduceMotion: reduceMotion
            )
        } ?? BeatVisualIntervalGeometry(
            placements: lifecycle.visibleEdgePlacements,
            transition: nil
        )
        let transition = geometry.transition
        let progress = eventProgress(for: renderedPulse, at: date)
        let target = BeatPolygonPresentationModel.edgePresentations(
            placements: geometry.placements,
            transition: transition,
            eventProgress: progress,
            strongBeatIndices: normalizedPreset.strongBeatIndices,
            secondaryAccentIndices: normalizedPreset.secondaryAccentIndices,
            startsFromOrigin: false,
            reduceMotion: reduceMotion
        )
        return resolvedPresentations(
            target: target,
            pulse: renderedPulse,
            eventProgress: progress,
            preset: normalizedPreset
        )
    }

    private func resolvedBallNormalizedHeight(
        targetHeight: Double,
        pulse: BeatPlaybackPulse?,
        eventProgress: Double
    ) -> Double {
        guard let pulse,
              let edgeResumeBridge,
              edgeResumeBridge.matches(
                beat: pulse.beat,
                subdivision: pulse.subdivision,
                cycle: pulse.cycle,
                sequence: pulse.sequence
              )
        else { return targetHeight }

        return BeatBounceMotionModel.resumeNormalizedHeight(
            from: edgeResumeBridge.sourceBallNormalizedHeight,
            toward: targetHeight,
            eventProgress: eventProgress,
            reduceMotion: reduceMotion
        )
    }

    private func presentedBallNormalizedHeight(
        at date: Date,
        preset: MetronomePreset
    ) -> Double {
        let normalizedPreset = preset.normalized
        let renderedPulse = acceptedPulse
        let beat = min(
            normalizedPreset.beats - 1,
            max(0, renderedPulse?.beat ?? 0)
        )
        let subdivision = min(
            normalizedPreset.pulsesPerBeat - 1,
            max(0, renderedPulse?.subdivision ?? 0)
        )
        let progress = eventProgress(for: renderedPulse, at: date)
        var targetHeight = lifecycle.ballIsAtOrigin ? 1.0 : 0.0
        if let target = BeatBounceMotionModel.nextTarget(
            afterBeat: beat,
            subdivision: subdivision,
            beats: normalizedPreset.beats,
            pulsesPerBeat: normalizedPreset.pulsesPerBeat,
            strongBeatIndices: normalizedPreset.strongBeatIndices,
            secondaryAccentIndices: normalizedPreset.secondaryAccentIndices
        ) {
            targetHeight = BeatBounceMotionModel.normalizedAudibleEventHeight(
                eventProgress: progress,
                toward: target.heightTier,
                motionScale: reduceMotion ? 0.30 : 1
            )
        }
        return resolvedBallNormalizedHeight(
            targetHeight: targetHeight,
            pulse: renderedPulse,
            eventProgress: progress
        )
    }

    private func freezePresentation(at date: Date) {
        let presentationDate = frozenAt ?? date
        let presentations = presentedEdges(
            at: presentationDate,
            preset: visualPreset
        )
        let ballNormalizedHeight = presentedBallNormalizedHeight(
            at: presentationDate,
            preset: visualPreset
        )
        frozenEdgePresentations = presentations.isEmpty ? nil : presentations
        frozenBallNormalizedHeight = presentations.isEmpty
            ? nil
            : ballNormalizedHeight
        edgeResumeBridge = nil
        frozenAt = date
    }

    private func eventAddress(_ pulse: BeatPlaybackPulse) -> BeatPresentationEventAddress {
        BeatPresentationEventAddress(
            cycle: pulse.cycle,
            beat: pulse.beat,
            subdivision: pulse.subdivision
        )
    }

    private func drawPrototypeEdge(
        slot: CGFloat,
        center: CGPoint,
        baselineY: CGFloat,
        halfEdge: CGFloat,
        step: CGFloat,
        opacity: Double,
        lineWidth: CGFloat,
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
            with: .color(GeoTheme.text.opacity(opacity)),
            style: StrokeStyle(
                lineWidth: max(0.75, lineWidth),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    private func drawPrototypeCollision(
        _ sample: BeatCollisionVisualSample,
        contact: PrototypeStageContactGeometry,
        edgeStrokeWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        guard sample.edgeOpacity > 0 else { return }

        let deltaX = contact.end.x - contact.start.x
        let deltaY = contact.end.y - contact.start.y
        let edgeLength = hypot(deltaX, deltaY)
        guard edgeLength > 0.000_001 else { return }
        let tangent = CGVector(
            dx: deltaX / edgeLength,
            dy: deltaY / edgeLength
        )
        let halfLength = edgeLength * 0.5 * CGFloat(sample.edgeSpread)
        var impulse = Path()
        impulse.move(to: CGPoint(
            x: contact.point.x - tangent.dx * halfLength,
            y: contact.point.y - tangent.dy * halfLength
        ))
        impulse.addLine(to: CGPoint(
            x: contact.point.x + tangent.dx * halfLength,
            y: contact.point.y + tangent.dy * halfLength
        ))
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 1.4))
            layer.stroke(
                impulse,
                with: .color(
                    Color(red: 0.76, green: 0.72, blue: 1)
                        .opacity(sample.edgeOpacity)
                ),
                style: StrokeStyle(
                    lineWidth: edgeStrokeWidth
                        + CGFloat(sample.edgeLineWidthBoost),
                    lineCap: .round
                )
            )
        }
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
            .frame(
                maxWidth: .infinity,
                minHeight: PrototypeMetronomeLayout.controlHeight
            )
            .padding(.horizontal, 8)
            .geoCardSurface(cornerRadius: PrototypeMetronomeLayout.cardCornerRadius)
        }
    }
}

private struct PrototypeLockedParameterTile: View {
    let title: String
    let value: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .frame(
                maxWidth: .infinity,
                minHeight: PrototypeMetronomeLayout.controlHeight
            )
            .padding(.horizontal, 8)
            .geoCardSurface(cornerRadius: PrototypeMetronomeLayout.cardCornerRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(value)")
    }
}

/// Odd meters retain an explicit accent-grouping choice. The audio engine has
/// always supported these presets; this compact selector keeps that choice
/// visible instead of hiding it behind the beat-count menu.
private struct PrototypeBeatGroupingSelector: View {
    let options: [String]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Label("重音分组", systemImage: "waveform.path")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(GeoTheme.muted)
                .lineLimit(1)
                .frame(width: 82, alignment: .leading)
                .padding(.leading, 8)
                .accessibilityHidden(true)

            ForEach(options, id: \.self) { grouping in
                Button {
                    onSelect(grouping)
                } label: {
                    Text(grouping)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(
                            selection == grouping
                                ? GeoTheme.selectionText
                                : GeoTheme.text
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: PrototypeMetronomeLayout.controlHeight
                                - PrototypeMetronomeLayout.selectionInset * 2
                        )
                        .background(
                            selection == grouping
                                ? GeoTheme.selectionFill
                                : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: PrototypeMetronomeLayout.selectionCornerRadius,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重音分组 \(grouping)")
                .accessibilityAddTraits(selection == grouping ? .isSelected : [])
            }
        }
        .padding(PrototypeMetronomeLayout.selectionInset)
        .background {
            RoundedRectangle(
                cornerRadius: PrototypeMetronomeLayout.cardCornerRadius,
                style: .continuous
            )
            .fill(GeoTheme.panel)
            .overlay {
                RoundedRectangle(
                    cornerRadius: PrototypeMetronomeLayout.cardCornerRadius,
                    style: .continuous
                )
                .stroke(GeoTheme.surfaceInk.opacity(0.06), lineWidth: 1)
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
                        .background(.thinMaterial, in: Capsule())
                }
                Text("\(bpm)")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 31)
                Button { bpm = min(240, bpm + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 36)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: PrototypeMetronomeLayout.controlHeight
        )
        .padding(.horizontal, 8)
        .geoCardSurface(cornerRadius: PrototypeMetronomeLayout.cardCornerRadius)
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
    let pieceName: String
    let sectionName: String
    let hand: PrototypePracticeHand
    let completed: Int
    let target: Int?
    let bpm: Int
    let durationMilliseconds: Int64
    let willSaveToLibrary: Bool
    let isSaving: Bool
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GeoBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                        Text(willSaveToLibrary ? "本轮练习完成" : "自由练习结束")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                        Text(willSaveToLibrary
                            ? "确认后会将次数、时长、速度与目标进度保存到当前段落。"
                            : "自由练习不会写入曲目历史或统计；确认后将结束并清除本轮临时数据。")
                            .font(.footnote)
                            .foregroundStyle(GeoTheme.muted)
                            .multilineTextAlignment(.center)

                        GeoCard {
                            VStack(alignment: .leading, spacing: 14) {
                                summaryRow("曲目", pieceName)
                                summaryRow("段落", sectionName)
                                summaryRow("手型", hand.title)
                                summaryRow("速度", "\(bpm) BPM")
                                summaryRow("总时长", practiceDurationString(milliseconds: durationMilliseconds))
                                summaryRow("本轮完成", target.map { "\(completed)/\($0)" } ?? "\(completed) 次")
                                summaryRow("记录方式", willSaveToLibrary ? "保存到当前段落" : "自由练习，不保存")
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        isSaving
                            ? (willSaveToLibrary ? "保存中…" : "结束中…")
                            : (willSaveToLibrary ? "保存并完成" : "结束练习")
                    ) {
                        onComplete()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
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
