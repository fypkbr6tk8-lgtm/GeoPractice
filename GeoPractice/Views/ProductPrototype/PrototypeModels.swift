import Foundation

enum ProductPrototypeGate {
    static var isEnabled: Bool {
#if DEBUG
        // Xcode Run opens the prototype by default. Supplying
        // `-production-ui` keeps the original app available for regression
        // checks without rebuilding a different scheme.
        !ProcessInfo.processInfo.arguments.contains("-production-ui")
#elseif CUSTOMER_PREVIEW
        true
#else
        false
#endif
    }
}

/// The intentionally small hand-off value between the mock practice browser
/// and the mock metronome. It is not persisted and must not be used by the
/// production statistics pipeline.
struct PrototypePracticeLaunch: Hashable, Sendable {
    var pieceName: String
    var sectionName: String
    var bpm: Int
    var beats: Int
    var trainingNote: String
    var referenceNote: String?
    var completedByHand: [PrototypePracticeHand: Int]
    var targetByHand: [PrototypePracticeHand: Int]

    init(
        pieceName: String,
        sectionName: String,
        bpm: Int = 96,
        beats: Int = 4,
        trainingNote: String = "八分音符",
        referenceNote: String? = "四分音符",
        completedByHand: [PrototypePracticeHand: Int] = [:],
        targetByHand: [PrototypePracticeHand: Int] = [
            .left: 10,
            .both: 10,
            .right: 10
        ]
    ) {
        self.pieceName = pieceName
        self.sectionName = sectionName
        self.bpm = bpm
        self.beats = beats
        self.trainingNote = trainingNote
        self.referenceNote = referenceNote
        self.completedByHand = completedByHand.reduce(into: [:]) { result, entry in
            result[entry.key] = max(0, entry.value)
        }
        self.targetByHand = targetByHand.reduce(into: [:]) { result, entry in
            if entry.value > 0 {
                result[entry.key] = entry.value
            }
        }
    }
}

enum PrototypePracticeHand: String, CaseIterable, Identifiable, Sendable {
    case left
    case both
    case right

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .left: "L"
        case .both: "B"
        case .right: "R"
        }
    }

    var title: String {
        switch self {
        case .left: "左手"
        case .both: "合手"
        case .right: "右手"
        }
    }
}

enum ProductPrototypeTab: Hashable {
    case statistics
    case practice
    case metronome
}
