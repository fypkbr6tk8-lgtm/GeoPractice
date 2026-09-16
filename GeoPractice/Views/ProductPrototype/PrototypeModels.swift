import Foundation
import SwiftUI

enum PrototypeSongDeletionCopy {
    static let message = "请确认删除后本曲目和相关的统计数据都将清零"
}

enum PrototypeCompletion {
    static func percentage(completed: Int, target: Int?) -> Int? {
        percentage(entries: [(completed: completed, target: target)])
    }

    /// Calculates weighted progress while capping every individual target.
    /// Extra work in one section must not compensate for an unfinished one.
    static func percentage(entries: [(completed: Int, target: Int?)]) -> Int? {
        var credited = 0.0
        var totalTarget = 0.0

        for entry in entries {
            guard let target = entry.target, target > 0 else { continue }
            let safeCompleted = max(0, entry.completed)
            credited += Double(min(safeCompleted, target))
            totalTarget += Double(target)
        }

        guard totalTarget > 0, credited.isFinite, totalTarget.isFinite else {
            return nil
        }
        return min(100, max(0, Int((credited / totalTarget * 100).rounded())))
    }
}

/// Shared prototype-only glass treatment. It intentionally mirrors the
/// floating tab bar: one translucent surface, a restrained highlight and a
/// clear boundary. Production views continue to use their existing styles.
struct PrototypeGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let emphasized: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    emphasized ? GeoTheme.panel : GeoTheme.panelRaised,
                    in: shape
                )
                .overlay { border }
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content
                    .background(GeoTheme.background.opacity(0.14), in: shape)
                    .glassEffect(
                        .regular.tint(
                            GeoTheme.surfaceInk.opacity(emphasized ? 0.16 : 0.025)
                        ),
                        in: shape
                    )
                    .overlay { border }
            } else {
                material(content)
            }
#else
            material(content)
#endif
        }
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background {
                shape
                    .fill(GeoTheme.background.opacity(emphasized ? 0.02 : 0.14))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                GeoTheme.surfaceInk.opacity(emphasized ? 0.20 : 0.09),
                                GeoTheme.surfaceInk.opacity(0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay { border }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var border: some View {
        shape
            .stroke(
                GeoTheme.surfaceInk.opacity(emphasized ? 0.28 : 0.15),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}

extension View {
    func prototypeGlassSurface(
        cornerRadius: CGFloat = 16,
        emphasized: Bool = false
    ) -> some View {
        modifier(
            PrototypeGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                emphasized: emphasized
            )
        )
    }
}

/// Stable hand-off from the persisted practice library to the live
/// metronome/session pipeline. Names are display snapshots; identity and every
/// mutation use the song/event UUIDs.
struct PrototypePracticeLaunch: Hashable, Sendable {
    var songID: UUID?
    var eventID: UUID?
    var pieceName: String
    var sectionName: String
    var bpm: Int
    var beats: Int
    var trainingNote: String
    var referenceNote: String?
    var completedByHand: [PrototypePracticeHand: Int]
    var targetByHand: [PrototypePracticeHand: Int]
    var presetSnapshot: MetronomePreset?

    init(
        songID: UUID? = nil,
        eventID: UUID? = nil,
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
        ],
        presetSnapshot: MetronomePreset? = nil
    ) {
        self.songID = songID
        self.eventID = eventID
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
        self.presetSnapshot = presetSnapshot?.normalized
    }

    var preset: MetronomePreset {
        if let presetSnapshot { return presetSnapshot.normalized }
        return MetronomePreset(
            bpm: bpm,
            beats: beats,
            subdivision: Self.subdivision(for: trainingNote),
            direction: .clockwise,
            grouping: MetronomePreset.groupings(for: beats).first ?? "",
            referenceNoteRaw: Self.referenceNote(for: referenceNote).rawValue
        ).normalized
    }

    private static func subdivision(for title: String) -> Int {
        if title.contains("十六") { return 4 }
        if title.contains("八") { return 2 }
        if title.contains("二分") { return 0 }
        return 1
    }

    private static func referenceNote(for title: String?) -> TempoReferenceNote {
        guard let title else { return .quarter }
        if title.contains("二分") { return .half }
        if title.contains("八分") { return .eighth }
        if title.contains("十六") { return .sixteenth }
        return .quarter
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

    var practiceHand: PracticeHand {
        switch self {
        case .left: .left
        case .both: .both
        case .right: .right
        }
    }

    init(_ hand: PracticeHand) {
        switch hand {
        case .left: self = .left
        case .both: self = .both
        case .right: self = .right
        }
    }
}

enum ProductPrototypeTab: Hashable {
    case statistics
    case practice
    case metronome
}
