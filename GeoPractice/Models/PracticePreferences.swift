import Foundation

enum TempoScrubDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .horizontal:
            "左右滑动"
        case .vertical:
            "上下滑动"
        }
    }

    var detail: String {
        switch self {
        case .horizontal:
            "向右加速，向左减速"
        case .vertical:
            "向上加速，向下减速"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .horizontal:
            "向右拖动提高速度，向左拖动降低速度"
        case .vertical:
            "向上拖动提高速度，向下拖动降低速度"
        }
    }

    /// Returns a signed distance with positive values always meaning a tempo
    /// increase. UIKit's vertical translation grows downwards, so the vertical
    /// option deliberately reverses that axis.
    func primaryTranslation(horizontal: Double, vertical: Double) -> Double {
        switch self {
        case .horizontal:
            horizontal
        case .vertical:
            -vertical
        }
    }
}

enum PracticePreferenceKeys {
    static let tempoScrubDirection = "practice.tempoScrubDirection.v1"
    static let continueAudioInBackground = "practice.continueAudioInBackground.v1"
    static let keepScreenAwake = "practice.keepScreenAwake.v1"
    static let defaultBPM = "practice.defaultBPM.v1"
    static let defaultBeats = "practice.defaultBeats.v1"
    static let metronomeSound = "practice.metronomeSound.v1"
    static let restReminderEnabled = "practice.restReminderEnabled.v1"
    static let restReminderMinutes = "practice.restReminderMinutes.v1"
    static let dailyReminderEnabled = "practice.dailyReminderEnabled.v1"
    static let dailyReminderHour = "practice.dailyReminderHour.v1"
    static let dailyReminderMinute = "practice.dailyReminderMinute.v1"
    static let appearanceMode = "practice.appearanceMode.v1"
    static let buttonHapticsEnabled = "practice.buttonHapticsEnabled.v1"
    static let beatVibrationEnabled = "practice.beatVibrationEnabled.v1"
}

/// Persisted sound choice shared by Settings and the metronome engine.
///
/// Raw values are stable storage identifiers. User-facing names deliberately
/// live in `title` so copy can evolve without invalidating existing defaults.
enum PracticeMetronomeSound: String, CaseIterable, Codable, Identifiable, Sendable {
    case penetratingWoodblock
    case classicClick
    case electronicPulse
    case softBlock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .penetratingWoodblock: "高穿透木鱼"
        case .classicClick: "经典节拍"
        case .electronicPulse: "电子脉冲"
        case .softBlock: "柔和木块"
        }
    }
}

enum PracticeAppearanceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case followSystem
    case light
    case dark

    var id: String { rawValue }

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

/// Validation and timing rules for values persisted by the settings screen.
/// Keeping these rules independent from SwiftUI/UserDefaults allows both the
/// settings UI and runtime consumers to defend against legacy or corrupt data.
enum PracticePreferencePolicy {
    static let defaultBPM = 120
    static let defaultBeats = 4
    static let defaultRestReminderMinutes = 30
    static let defaultDailyReminderHour = 9
    static let defaultDailyReminderMinute = 0

    static func normalizedBPM(_ value: Int) -> Int {
        min(240, max(30, value))
    }

    static func normalizedBeats(_ value: Int) -> Int {
        min(9, max(3, value))
    }

    static func normalizedRestReminderMinutes(_ value: Int) -> Int {
        let clamped = min(120, max(10, value))
        return max(10, (clamped / 5) * 5)
    }

    static func normalizedReminderHour(_ value: Int) -> Int {
        min(23, max(0, value))
    }

    static func normalizedReminderMinute(_ value: Int) -> Int {
        let clamped = min(55, max(0, value))
        return (clamped / 5) * 5
    }
}

struct PracticeRestReminderPolicy: Equatable, Sendable {
    let isEnabled: Bool
    let intervalMinutes: Int

    init(isEnabled: Bool, intervalMinutes: Int) {
        self.isEnabled = isEnabled
        self.intervalMinutes = PracticePreferencePolicy
            .normalizedRestReminderMinutes(intervalMinutes)
    }

    var intervalMilliseconds: Int64 {
        Int64(intervalMinutes) * 60 * 1_000
    }

    /// True only when elapsed practice crosses a new reminder boundary.
    func shouldRemind(
        previousElapsedMilliseconds: Int64,
        currentElapsedMilliseconds: Int64
    ) -> Bool {
        guard isEnabled, currentElapsedMilliseconds > 0 else { return false }
        let safePrevious = max(0, previousElapsedMilliseconds)
        let safeCurrent = max(0, currentElapsedMilliseconds)
        return safeCurrent / intervalMilliseconds > safePrevious / intervalMilliseconds
    }
}

/// Pure policy for lifecycle behavior. Keeping this independent from SwiftUI,
/// UIApplication and the audio engine makes lock-screen decisions deterministic
/// and directly testable.
struct PracticeRuntimePolicy: Equatable, Sendable {
    enum SceneState: Equatable, Sendable {
        case active
        case inactive
        case background
    }

    enum BackgroundAction: Equatable, Sendable {
        case continueRunning
        case stopAndPause
    }

    let continueAudioInBackground: Bool
    let keepScreenAwake: Bool

    init(
        continueAudioInBackground: Bool = true,
        keepScreenAwake: Bool = false
    ) {
        self.continueAudioInBackground = continueAudioInBackground
        self.keepScreenAwake = keepScreenAwake
    }

    func backgroundAction(
        isMetronomeSelected: Bool,
        isMetronomePlaying: Bool
    ) -> BackgroundAction {
        continueAudioInBackground && isMetronomeSelected && isMetronomePlaying
            ? .continueRunning
            : .stopAndPause
    }

    func shouldDisableIdleTimer(
        sceneState: SceneState,
        isMetronomeSelected: Bool,
        isMetronomePlaying: Bool
    ) -> Bool {
        sceneState == .active
            && keepScreenAwake
            && isMetronomeSelected
            && isMetronomePlaying
    }

    func shouldPersistCheckpoint(
        sceneState: SceneState,
        isMetronomeSelected: Bool,
        isMetronomePlaying: Bool,
        isPracticeRunning: Bool
    ) -> Bool {
        guard isMetronomeSelected, isPracticeRunning else { return false }

        switch sceneState {
        case .active:
            return true
        case .inactive:
            return false
        case .background:
            return backgroundAction(
                isMetronomeSelected: isMetronomeSelected,
                isMetronomePlaying: isMetronomePlaying
            ) == .continueRunning
        }
    }

    func shouldPauseWhenEnteringInactive(
        isMetronomeSelected: Bool,
        isMetronomePlaying: Bool,
        isPracticeRunning: Bool
    ) -> Bool {
        isMetronomeSelected
            && !isMetronomePlaying
            && isPracticeRunning
    }

    func shouldPauseAfterOffscreenPlaybackStops(
        sceneState: SceneState,
        isMetronomeSelected: Bool,
        wasPlaying: Bool,
        isPlaying: Bool,
        isPracticeRunning: Bool
    ) -> Bool {
        sceneState != .active
            && isMetronomeSelected
            && wasPlaying
            && !isPlaying
            && isPracticeRunning
    }
}
