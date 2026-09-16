import Combine
import Foundation
import SwiftUI
import UIKit

enum RootTab: Hashable {
    case practice
    case statistics
    case metronome
}

private struct PendingPracticeLaunch {
    let event: PracticeEvent
    let preset: MetronomePreset

    var eventID: UUID { event.id }
    var eventName: String { event.name }
}

private struct PendingDailyGoalSetup: Identifiable {
    let id = UUID()
    let launch: PendingPracticeLaunch
    let date: Date
    let initialTargets: PracticeGoalCounts
}

private struct PracticeSessionDraft: Codable {
    let session: PracticeSession
    let savedAt: Date
    /// The one live metronome configuration for the whole session.
    let preset: MetronomePreset?
    /// Last-used snapshots remain per hand for duration-only history and
    /// statistics. They must never act as UI profiles when the user changes
    /// the hand that receives counts.
    let presetsByHand: [PracticeHand: MetronomePreset]?
}

@MainActor
final class PracticeSessionController: ObservableObject {
    private static let draftKey = "practiceSessionDraft.v1"

    @Published private(set) var session: PracticeSession
    private(set) var sessionPreset: MetronomePreset?
    /// Historical last-used snapshots for summaries/statistics, not profiles
    /// that may be loaded when the selected hand changes.
    private(set) var sessionPresetsByHand: [PracticeHand: MetronomePreset]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var restored = PracticeSession()
        var restoredPreset: MetronomePreset?
        var restoredPresetsByHand: [PracticeHand: MetronomePreset] = [:]
        var restoredSavedAt: Date?
        if let data = defaults.data(forKey: Self.draftKey),
           let draft = try? JSONDecoder().decode(PracticeSessionDraft.self, from: data) {
            restored = draft.session
            restoredPreset = draft.preset?.normalized
            restoredPresetsByHand = (draft.presetsByHand ?? [:]).reduce(into: [:]) {
                result, entry in
                result[entry.key] = entry.value.normalized
            }
            if restoredPreset == nil {
                // Drafts written before the scalar live preset was retained
                // can still recover it from the currently selected hand.
                restoredPreset = restoredPresetsByHand[restored.currentHand]
            }
            if restoredPresetsByHand[restored.currentHand] == nil,
               let restoredPreset {
                // Legacy drafts stored one preset, and a partially written
                // newer draft can also be missing its active-hand entry. In
                // both cases the scalar value represents the current hand.
                restoredPresetsByHand[restored.currentHand] = restoredPreset
            }
            restoredSavedAt = draft.savedAt
            switch restored.phase {
            case .running:
                restored.pause(at: draft.savedAt)
            case .finished:
                // Upgrade a finished legacy draft before it can be confirmed
                // into immutable history.
                _ = restored.finish(
                    at: draft.savedAt,
                    presetsByHand: restoredPresetsByHand
                )
            case .idle, .paused:
                break
            }
        }
        _session = Published(initialValue: restored)
        sessionPreset = restoredPreset
        sessionPresetsByHand = restoredPresetsByHand
        if let restoredSavedAt {
            // Re-encode immediately so legacy drafts that had no sessionID
            // keep the decoder-generated ID across every later relaunch.
            persist(restored, at: restoredSavedAt)
        }
    }

    func begin(
        sourceEventID: UUID? = nil,
        preset: MetronomePreset,
        goalContext: PracticeGoalLaunchContext? = nil,
        initialHand: PracticeHand = .both,
        at date: Date = .now
    ) {
        var next = PracticeSession()
        next.begin(
            sourceEventID: sourceEventID,
            goalContext: goalContext,
            initialHand: initialHand,
            at: date
        )
        let normalizedPreset = preset.normalized
        sessionPreset = normalizedPreset
        sessionPresetsByHand = [initialHand: normalizedPreset]
        commit(next, at: date)
    }

    func startIfNeeded(preset: MetronomePreset, at date: Date = .now) {
        switch session.phase {
        case .idle:
            begin(preset: preset, at: date)
        case .paused:
            if sessionPreset == nil {
                let normalizedPreset = preset.normalized
                sessionPreset = normalizedPreset
                sessionPresetsByHand[session.currentHand] = normalizedPreset
            }
            resume(at: date)
        case .running, .finished:
            break
        }
    }

    func resume(at date: Date = .now) {
        var next = session
        next.resume(at: date)
        commit(next, at: date)
    }

    func pause(at date: Date = .now) {
        var next = session
        next.pause(at: date)
        commit(next, at: date)
    }

    func switchHand(to hand: PracticeHand, at date: Date = .now) {
        var next = session
        next.switchHand(to: hand, at: date)
        if next.currentHand == hand,
           let sessionPreset {
            // A hand selects where time/counts are recorded; it is not a
            // metronome preset profile. Snapshot the unchanged live setting
            // for history without replacing it with this hand's old value.
            sessionPresetsByHand[hand] = sessionPreset
        }
        commit(next, at: date)
    }

    func recordCompletion(
        for hand: PracticeHand,
        preset: MetronomePreset,
        at date: Date = .now
    ) {
        var next = session
        next.recordCompletion(for: hand, preset: preset, at: date)
        let normalizedPreset = preset.normalized
        sessionPresetsByHand[hand] = normalizedPreset
        if next.currentHand == hand {
            sessionPreset = normalizedPreset
        }
        commit(next, at: date)
    }

    /// Compatibility for restoring and exercising legacy count-only drafts.
    /// User-facing `+1` controls always call `recordCompletion` instead.
    func adjustCount(for hand: PracticeHand, by delta: Int) {
        var next = session
        next.adjustCount(for: hand, by: delta)
        commit(next, at: .now)
    }

    @discardableResult
    func undoLastCompletion(
        for hand: PracticeHand,
        at date: Date = .now
    ) -> PracticeCompletionSample? {
        var next = session
        let removed = next.undoLastCompletion(for: hand)
        guard removed != nil else { return nil }
        commit(next, at: date)
        return removed
    }

    /// User-facing undo that also supports pre-history drafts whose counts do
    /// not have corresponding completion samples.
    @discardableResult
    func undoLatestCompletionOrLegacyCount(
        for hand: PracticeHand,
        at date: Date = .now
    ) -> Bool {
        var next = session
        if next.undoLastCompletion(for: hand) == nil {
            guard next.stats(for: hand, at: date).count > 0 else { return false }
            next.adjustCount(for: hand, by: -1)
        }
        commit(next, at: date)
        return true
    }

    func finish(at date: Date = .now) -> PracticeSessionSummary? {
        var next = session
        let summary = next.finish(
            at: date,
            presetsByHand: sessionPresetsByHand
        )
        commit(next, at: date)
        return summary
    }

    func continueAfterReview(at date: Date = .now) {
        var next = session
        next.continueAfterReview(at: date)
        commit(next, at: date)
    }

    func reset() {
        session = PracticeSession()
        sessionPreset = nil
        sessionPresetsByHand = [:]
        defaults.removeObject(forKey: Self.draftKey)
    }

    func updateLivePreset(
        _ preset: MetronomePreset,
        at date: Date = .now
    ) {
        guard session.phase != .idle else { return }
        let normalizedPreset = preset.normalized
        sessionPreset = normalizedPreset
        sessionPresetsByHand[session.currentHand] = normalizedPreset
        persist(session, at: date)
    }

    func persistSnapshot(at date: Date = .now) {
        persist(session, at: date)
    }

    private func commit(_ next: PracticeSession, at date: Date) {
        session = next
        persist(next, at: date)
    }

    private func persist(_ session: PracticeSession, at date: Date) {
        guard session.phase != .idle else {
            defaults.removeObject(forKey: Self.draftKey)
            return
        }
        let draft = PracticeSessionDraft(
            session: session,
            savedAt: date,
            preset: sessionPreset,
            presetsByHand: sessionPresetsByHand
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: Self.draftKey)
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PracticePreferenceKeys.continueAudioInBackground)
    private var continueAudioInBackground = true
    @AppStorage(PracticePreferenceKeys.keepScreenAwake)
    private var keepScreenAwake = false
    @AppStorage(PracticePreferenceKeys.appearanceMode)
    private var appearanceModeRaw = PracticeAppearanceMode.dark.rawValue
    @StateObject private var metronome = MetronomeEngine()
    @StateObject private var practiceSession = PracticeSessionController()
    @State private var selectedTab: RootTab = .practice
    @State private var pendingPracticeLaunch: PendingPracticeLaunch?
    @State private var pendingDailyGoalSetup: PendingDailyGoalSetup?
    @State private var launchError: String?
    private let checkpointTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selectedTab) {
            PracticeEventsView(
                metronome: metronome,
                protectedEventID: protectedPracticeEventID
            ) { event, preset in
                let request = PendingPracticeLaunch(
                    event: event,
                    preset: preset
                )
                if practiceSession.session.phase == .running
                    || practiceSession.session.phase == .paused
                    || practiceSession.session.phase == .finished {
                    pendingPracticeLaunch = request
                } else {
                    preparePracticeLaunch(request)
                }
            }
            .tag(RootTab.practice)
            .tabItem {
                Label("打卡", systemImage: "checkmark.circle")
            }

            StatisticsView()
                .tag(RootTab.statistics)
                .tabItem {
                    Label("统计", systemImage: "chart.bar.xaxis")
                }

            MetronomeView(
                engine: metronome,
                practiceSession: practiceSession,
                leaveMetronome: {
                    selectedTab = .practice
                }
            )
                .tag(RootTab.metronome)
                .tabItem {
                    Label("节拍器", systemImage: "metronome")
                }
        }
        .tint(GeoTheme.controlAccent)
        .preferredColorScheme(preferredColorScheme)
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
            if let request = pendingPracticeLaunch {
                Button("放弃本次并开始“\(request.eventName)”", role: .destructive) {
                    pendingPracticeLaunch = nil
                    practiceSession.reset()
                    preparePracticeLaunch(request)
                }
            }
            Button("取消", role: .cancel) {
                pendingPracticeLaunch = nil
            }
        } message: {
            Text("当前会话的次数和时长尚未保存。你可以返回节拍器完成或确认汇总，也可以明确放弃后开始新的练习。")
        }
        .sheet(item: $pendingDailyGoalSetup) { setup in
            DailyGoalSetupView(
                eventName: setup.launch.eventName,
                date: setup.date,
                initialTargets: setup.initialTargets
            ) { targets in
                confirmDailyGoal(
                    targets,
                    for: setup.launch,
                    at: .now
                )
            }
        }
        .alert("无法开始练习", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("好", role: .cancel) { launchError = nil }
        } message: {
            Text(launchError ?? "请稍后重试。")
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .metronome {
                if let restoredPreset = practiceSession.sessionPreset {
                    metronome.apply(restoredPreset)
                }
                practiceSession.startIfNeeded(preset: metronome.preset)
            } else {
                metronome.pause()
                practiceSession.pause()
            }
            synchronizeIdleTimer()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhaseChange(phase, at: .now)
        }
        .onChange(of: metronome.isPlaying) { wasPlaying, isPlaying in
            handlePlaybackChange(
                wasPlaying: wasPlaying,
                isPlaying: isPlaying,
                at: .now
            )
        }
        .onChange(of: keepScreenAwake) { _, _ in
            synchronizeIdleTimer()
        }
        .onChange(of: continueAudioInBackground) { _, _ in
            guard scenePhase == .background else { return }
            handleBackgroundTransition(at: .now)
        }
        .onAppear {
            if let restoredPreset = practiceSession.sessionPreset {
                metronome.apply(restoredPreset)
            }
            synchronizeIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onReceive(checkpointTimer) { date in
            guard runtimePolicy.shouldPersistCheckpoint(
                sceneState: runtimeSceneState(for: scenePhase),
                isMetronomeSelected: selectedTab == .metronome,
                isMetronomePlaying: metronome.isPlaying,
                isPracticeRunning: practiceSession.session.isRunning
            ) else { return }
            practiceSession.persistSnapshot(at: date)
        }
    }

    private func preparePracticeLaunch(
        _ request: PendingPracticeLaunch,
        at date: Date = .now
    ) {
        guard let plan = request.event.goalPlan else {
            launchPractice(request, goalContext: nil, at: date)
            return
        }

        do {
            if let dailyGoal = try PracticeDailyGoal.today(
                for: request.eventID,
                planID: plan.id,
                at: date,
                timeZone: .autoupdatingCurrent,
                in: modelContext
            ) {
                let context = try PracticeGoalLaunchContext.capture(
                    for: request.event,
                    dailyGoal: dailyGoal,
                    launchedAt: date,
                    timeZone: .autoupdatingCurrent,
                    in: modelContext
                )
                launchPractice(request, goalContext: context, at: date)
                return
            }

            let previous = try PracticeDailyGoal.previous(
                for: request.eventID,
                planID: plan.id,
                before: date,
                timeZone: .autoupdatingCurrent,
                in: modelContext
            )
            pendingDailyGoalSetup = PendingDailyGoalSetup(
                launch: request,
                date: date,
                initialTargets: previous?.targets ?? plan.targets
            )
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func confirmDailyGoal(
        _ targets: PracticeGoalCounts,
        for request: PendingPracticeLaunch,
        at date: Date
    ) -> Bool {
        guard targets.total > 0 else { return false }
        do {
            guard let plan = request.event.goalPlan else {
                launchPractice(request, goalContext: nil, at: date)
                return true
            }
            let goal = try PracticeDailyGoal.create(
                for: request.eventID,
                planID: plan.id,
                targets: targets,
                at: date,
                timeZone: .autoupdatingCurrent,
                in: modelContext
            )
            let context = try PracticeGoalLaunchContext.capture(
                for: request.event,
                dailyGoal: goal,
                launchedAt: date,
                timeZone: .autoupdatingCurrent,
                in: modelContext
            )
            try modelContext.save()
            pendingDailyGoalSetup = nil
            launchPractice(request, goalContext: context, at: date)
            return true
        } catch {
            modelContext.rollback()
            launchError = error.localizedDescription
            return false
        }
    }

    private func launchPractice(
        _ request: PendingPracticeLaunch,
        goalContext: PracticeGoalLaunchContext?,
        at date: Date
    ) {
        metronome.apply(request.preset)
        practiceSession.begin(
            sourceEventID: request.eventID,
            preset: request.preset,
            goalContext: goalContext,
            at: date
        )
        selectedTab = .metronome
    }

    private var runtimePolicy: PracticeRuntimePolicy {
        PracticeRuntimePolicy(
            continueAudioInBackground: continueAudioInBackground,
            keepScreenAwake: keepScreenAwake
        )
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

    private func handleScenePhaseChange(_ phase: ScenePhase, at date: Date) {
        switch phase {
        case .inactive:
            // Locking an iPhone passes through inactive before background. Save
            // immediately, but do not tear down audio during that transition.
            // If an interruption stopped audio just before the phase update,
            // pause timing here so the two states cannot drift apart.
            if runtimePolicy.shouldPauseWhenEnteringInactive(
                isMetronomeSelected: selectedTab == .metronome,
                isMetronomePlaying: metronome.isPlaying,
                isPracticeRunning: practiceSession.session.isRunning
            ) {
                practiceSession.pause(at: date)
            }
            practiceSession.persistSnapshot(at: date)
        case .background:
            handleBackgroundTransition(at: date)
        case .active:
            if selectedTab == .metronome {
                practiceSession.startIfNeeded(preset: metronome.preset, at: date)
            }
        @unknown default:
            practiceSession.persistSnapshot(at: date)
        }
        synchronizeIdleTimer(for: phase)
    }

    private func handleBackgroundTransition(at date: Date) {
        switch runtimePolicy.backgroundAction(
            isMetronomeSelected: selectedTab == .metronome,
            isMetronomePlaying: metronome.isPlaying
        ) {
        case .continueRunning:
            practiceSession.startIfNeeded(preset: metronome.preset, at: date)
            practiceSession.persistSnapshot(at: date)
        case .stopAndPause:
            metronome.pause()
            practiceSession.pause(at: date)
            practiceSession.persistSnapshot(at: date)
        }
        synchronizeIdleTimer(for: .background)
    }

    private func handlePlaybackChange(
        wasPlaying: Bool,
        isPlaying: Bool,
        at date: Date
    ) {
        if runtimePolicy.shouldPauseAfterOffscreenPlaybackStops(
            sceneState: runtimeSceneState(for: scenePhase),
            isMetronomeSelected: selectedTab == .metronome,
            wasPlaying: wasPlaying,
            isPlaying: isPlaying,
            isPracticeRunning: practiceSession.session.isRunning
        ) {
            // Audio interruptions and media-service resets can stop the engine
            // while no UI is visible. Keep the recorded practice duration in
            // step with the audio truth instead of silently counting onward.
            practiceSession.pause(at: date)
            practiceSession.persistSnapshot(at: date)
        }
        synchronizeIdleTimer()
    }

    private func synchronizeIdleTimer(for phase: ScenePhase? = nil) {
        let effectivePhase = phase ?? scenePhase
        let shouldDisable = runtimePolicy.shouldDisableIdleTimer(
            sceneState: runtimeSceneState(for: effectivePhase),
            isMetronomeSelected: selectedTab == .metronome,
            isMetronomePlaying: metronome.isPlaying
        )
        if UIApplication.shared.isIdleTimerDisabled != shouldDisable {
            UIApplication.shared.isIdleTimerDisabled = shouldDisable
        }
    }

    private func runtimeSceneState(
        for phase: ScenePhase
    ) -> PracticeRuntimePolicy.SceneState {
        switch phase {
        case .active:
            .active
        case .inactive:
            .inactive
        case .background:
            .background
        @unknown default:
            .inactive
        }
    }

    private var protectedPracticeEventID: UUID? {
        switch practiceSession.session.phase {
        case .running, .paused, .finished:
            practiceSession.session.sourceEventID
        case .idle:
            nil
        }
    }
}

#Preview {
    RootView()
        .modelContainer(
            for: [
                PracticeEvent.self,
                PracticeAttempt.self,
                PracticeFolder.self,
                PracticeDailyGoal.self
            ],
            inMemory: true
        )
}
