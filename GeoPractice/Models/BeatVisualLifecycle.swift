import Foundation

enum BeatPulseKind: Equatable, Sendable {
    case strong
    case secondary
    case weak
    case subdivision
}

struct BeatPulseAddress: Equatable, Sendable {
    let beat: Int
    let subdivision: Int
    /// Position around the N-point geometry. Integer values are main-beat
    /// vertices; fractional values are fixed subdivision positions.
    let phase: Double
}

struct BeatPulseStyle: Equatable, Sendable {
    let peakRadius: Double
    let peakOpacity: Double
    let duration: TimeInterval
}

enum BeatPulseVisualModel {
    static func address(
        beat: Int,
        subdivision: Int,
        beats: Int,
        pulsesPerBeat: Int
    ) -> BeatPulseAddress? {
        guard beats > 0,
              pulsesPerBeat > 0,
              beat >= 0, beat < beats,
              subdivision >= 0, subdivision < pulsesPerBeat
        else { return nil }

        return BeatPulseAddress(
            beat: beat,
            subdivision: subdivision,
            phase: Double(beat) + Double(subdivision) / Double(pulsesPerBeat)
        )
    }

    static func kind(
        beat: Int,
        subdivision: Int,
        strongBeatIndices: Set<Int>,
        secondaryAccentIndices: Set<Int>
    ) -> BeatPulseKind {
        if subdivision > 0 { return .subdivision }
        if strongBeatIndices.contains(beat) { return .strong }
        if secondaryAccentIndices.contains(beat) { return .secondary }
        return .weak
    }

    static func style(
        for kind: BeatPulseKind,
        eventInterval: TimeInterval,
        dimFlashingLights: Bool = false
    ) -> BeatPulseStyle {
        let nominal: (radius: Double, opacity: Double, duration: Double, intervalCap: Double)
        switch kind {
        case .strong:
            nominal = (10.6, 0.96, 0.165, 0.78)
        case .secondary:
            nominal = (8.8, 0.84, 0.140, 0.68)
        case .weak:
            nominal = (7.2, 0.70, 0.115, 0.58)
        case .subdivision:
            nominal = (5.0, 0.48, 0.075, 0.42)
        }

        let safeInterval = max(0.001, eventInterval)
        let intensity = dimFlashingLights ? 0.72 : 1
        let intervalDuration = max(0.04, safeInterval * nominal.intervalCap)
        return BeatPulseStyle(
            peakRadius: nominal.radius * intensity,
            peakOpacity: nominal.opacity * (dimFlashingLights ? 0.68 : 1),
            duration: min(nominal.duration, min(safeInterval * 0.82, intervalDuration))
        )
    }

    /// A Hit starts at full intensity and only decays. There is deliberately no
    /// attack or breathing phase while the metronome is playing.
    static func envelope(age: TimeInterval, duration: TimeInterval) -> Double {
        guard age >= 0, duration > 0, age < duration else { return 0 }
        let peakHold = min(0.014, duration * 0.28)
        if age <= peakHold { return 1 }
        let decayDuration = max(0.001, duration - peakHold)
        return pow(1 - (age - peakHold) / decayDuration, 2.2)
    }
}

/// Renderer-neutral position authored from the scheduler's current event.
/// `perimeterPhase` is measured in main-beat units while `measurePhase` is a
/// normalized turn. Both are wrapped half-open values, so the end of the final
/// event is exactly the beginning of the next measure rather than a duplicate
/// terminal position.
struct BeatVisualMotionSample: Equatable, Sendable {
    let eventProgress: Double
    let perimeterPhase: Double
    let measurePhase: Double
}

enum BeatVisualMotionModel {
    static func sample(
        beat: Int,
        subdivision: Int,
        elapsed: TimeInterval,
        eventInterval: TimeInterval,
        pulsesPerBeat: Int,
        eventsPerMeasure: Int,
        beats: Int
    ) -> BeatVisualMotionSample? {
        guard beats > 0,
              pulsesPerBeat > 0,
              beats <= Int.max / pulsesPerBeat,
              eventsPerMeasure == beats * pulsesPerBeat,
              beat >= 0, beat < beats,
              subdivision >= 0, subdivision < pulsesPerBeat,
              eventInterval.isFinite, eventInterval > 0,
              !elapsed.isNaN
        else { return nil }

        let eventProgress: Double
        if elapsed == .infinity {
            eventProgress = 1
        } else {
            eventProgress = min(1, max(0, elapsed / eventInterval))
        }

        let eventIndex = beat * pulsesPerBeat + subdivision
        let unwrappedMeasurePhase = (
            Double(eventIndex) + eventProgress
        ) / Double(eventsPerMeasure)
        let measurePhase = wrapped(unwrappedMeasurePhase, period: 1)
        let perimeterPhase = wrapped(measurePhase * Double(beats), period: Double(beats))

        return BeatVisualMotionSample(
            eventProgress: eventProgress,
            perimeterPhase: perimeterPhase,
            measurePhase: measurePhase
        )
    }

    private static func wrapped(_ value: Double, period: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: period)
        return remainder >= 0 ? remainder : remainder + period
    }
}

/// The four visually distinct launch heights used by the bouncing beat ball.
/// Values are normalized so renderers can scale them to their own geometry.
enum BeatBounceHeightTier: Equatable, Sendable {
    case strong
    case secondary
    case main
    case subdivision

    var normalizedPeakHeight: Double {
        switch self {
        case .strong: 1
        case .secondary: 0.72
        case .main: 0.46
        case .subdivision: 0.20
        }
    }

    init(pulseKind: BeatPulseKind) {
        switch pulseKind {
        case .strong: self = .strong
        case .secondary: self = .secondary
        case .weak: self = .main
        case .subdivision: self = .subdivision
        }
    }
}

/// The scheduler address and height hierarchy of the event following a hit.
/// A renderer uses this target to make the just-landed ball bounce toward the
/// strength of the *next* sound instead of lagging one event behind the audio.
struct BeatBounceTarget: Equatable, Sendable {
    let beat: Int
    let subdivision: Int
    let kind: BeatPulseKind
    let heightTier: BeatBounceHeightTier
    let wrapsToNextMeasure: Bool
}

/// Renderer-neutral bounce math. Geometry supplies the baseline and inward
/// normal; this model supplies only the musical target and normalized height.
enum BeatBounceMotionModel {
    static func nextTarget(
        afterBeat beat: Int,
        subdivision: Int,
        beats: Int,
        pulsesPerBeat: Int,
        strongBeatIndices: Set<Int>,
        secondaryAccentIndices: Set<Int>
    ) -> BeatBounceTarget? {
        guard beats > 0,
              pulsesPerBeat > 0,
              beat >= 0, beat < beats,
              subdivision >= 0, subdivision < pulsesPerBeat
        else { return nil }

        let isLastSubdivision = subdivision == pulsesPerBeat - 1
        let nextBeat = isLastSubdivision ? (beat + 1) % beats : beat
        let nextSubdivision = isLastSubdivision ? 0 : subdivision + 1
        let kind = BeatPulseVisualModel.kind(
            beat: nextBeat,
            subdivision: nextSubdivision,
            strongBeatIndices: strongBeatIndices,
            secondaryAccentIndices: secondaryAccentIndices
        )
        return BeatBounceTarget(
            beat: nextBeat,
            subdivision: nextSubdivision,
            kind: kind,
            heightTier: BeatBounceHeightTier(pulseKind: kind),
            wrapsToNextMeasure: isLastSubdivision && beat == beats - 1
        )
    }

    /// A physical-looking baseline-to-baseline arc for ordinary transitions.
    /// `eventProgress == 0.5` is the requested tier's apex.
    static func normalizedArcHeight(
        eventProgress: Double,
        tier: BeatBounceHeightTier
    ) -> Double {
        guard !eventProgress.isNaN else { return 0 }
        let progress = min(1, max(0, eventProgress))
        return tier.normalizedPeakHeight * 4 * progress * (1 - progress)
    }

    /// One scheduler event owns exactly one visible movement interval.
    /// Only the first event after a visual reset starts at the center; every
    /// later event — including the event that crosses a measure boundary —
    /// starts and ends in contact with the horizontal edge. Keeping this rule
    /// in the shared model prevents the prototype and production renderers
    /// from accidentally stretching a landing across two training pulses.
    static func normalizedEventHeight(
        eventProgress: Double,
        toward tier: BeatBounceHeightTier,
        startsFromOrigin: Bool,
        motionScale: Double = 1
    ) -> Double {
        if startsFromOrigin {
            return normalizedInitialDescentHeight(eventProgress: eventProgress)
        }
        guard motionScale.isFinite else { return 0 }
        let scale = min(1, max(0, motionScale))
        return normalizedArcHeight(
            eventProgress: eventProgress,
            tier: tier
        ) * scale
    }

    /// At a visual-session reset the first strong beat starts at the
    /// center/apex and falls to the newly generated horizontal edge. A normal
    /// measure reset does not use this curve: its first beat starts at the
    /// contact left by the preceding event.
    static func normalizedInitialDescentHeight(eventProgress: Double) -> Double {
        guard !eventProgress.isNaN else { return 0 }
        let progress = min(1, max(0, eventProgress))
        return BeatBounceHeightTier.strong.normalizedPeakHeight
            * (1 - progress * progress)
    }
}

/// Contact geometry shared by the production and prototype renderers. The
/// returned offset is measured inward from the edge's centerline, so height
/// zero places the ball's outer circumference tangent to the visible stroke
/// instead of putting the ball's center on the line.
enum BeatBounceContactGeometry {
    static func inwardOffset(
        edgeToCenterDistance: Double,
        ballRadius: Double,
        edgeStrokeWidth: Double,
        normalizedHeight: Double
    ) -> Double {
        guard edgeToCenterDistance.isFinite,
              ballRadius.isFinite,
              edgeStrokeWidth.isFinite,
              normalizedHeight.isFinite
        else { return 0 }

        let distance = max(0, edgeToCenterDistance)
        let clearance = max(0, ballRadius) + max(0, edgeStrokeWidth) / 2
        let height = min(1, max(0, normalizedHeight))
        // If a renderer ever makes the ball larger than the polygon inradius,
        // preserving contact is more important than forcing the center to the
        // origin. This keeps the solid ball outside the stroke for every size.
        return clearance + max(0, distance - clearance) * height
    }

    /// Largest circular feedback footprint that can be drawn around the same
    /// center without crossing the visible edge stroke.
    static func maximumNonPenetratingRadius(
        inwardCenterOffset: Double,
        edgeStrokeWidth: Double
    ) -> Double {
        guard inwardCenterOffset.isFinite, edgeStrokeWidth.isFinite else { return 0 }
        return max(0, inwardCenterOffset - max(0, edgeStrokeWidth) / 2)
    }
}

/// One generated edge and the polygon slot it currently occupies. Slot zero
/// is the fixed horizontal generation slot; increasing slots rotate clockwise.
struct BeatVisualEdgePlacement: Equatable, Sendable {
    let generationIndex: Int
    let slotIndex: Int
}

struct BeatVisualEdgeRotation: Equatable, Sendable {
    let generationIndex: Int
    let fromSlotIndex: Int
    let toSlotIndex: Int
}

/// One authoritative geometry mutation. Renderers may animate the rotations
/// and insertions, but this value never owns presentation time.
struct BeatVisualGeometryTransition: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case measureStart
        case beatAdvance
        case gapRecovery
        case measureReset
    }

    let revision: UInt64
    let kind: Kind
    let cycle: Int
    let beat: Int
    let previousPlacements: [BeatVisualEdgePlacement]
    let placements: [BeatVisualEdgePlacement]
    let rotations: [BeatVisualEdgeRotation]
    let insertedPlacements: [BeatVisualEdgePlacement]
}

/// Playback and visual lifecycle are intentionally separate. The audio engine
/// supplies authoritative event addresses; this value derives one measure's
/// edge placements and remembers the visual facts which survive a pause or an
/// interval-only tempo change.
struct BeatVisualLifecycle: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Idle: only the origin ball is visible.
        case origin
        /// Main beats are adding one polygon edge at a time.
        case building
        /// The final main beat is active and the polygon is complete.
        case orbiting
        /// Audio has stopped and the ball is returning to the origin.
        case finishing
        /// The ball is at the origin and edges are removed in reverse order.
        case dismantling
        /// The practice has ended and the completed stage has been cleared.
        case settled
    }

    private struct EventCursor: Equatable, Comparable, Sendable {
        let cycle: Int
        let beat: Int
        let subdivision: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.cycle != rhs.cycle { return lhs.cycle < rhs.cycle }
            if lhs.beat != rhs.beat { return lhs.beat < rhs.beat }
            return lhs.subdivision < rhs.subdivision
        }
    }

    private(set) var phase: Phase = .origin
    private(set) var beatCount: Int
    /// Oldest-to-newest generated edges for the current measure. Slot zero is
    /// always the fixed horizontal generation slot; older edges rotate one
    /// clockwise slot whenever the next main beat begins.
    private(set) var visibleEdgePlacements: [BeatVisualEdgePlacement] = []
    /// The cycle of the latest accepted scheduler event. A newer cycle clears
    /// the previous measure before any subdivision handling occurs.
    private(set) var currentMeasureCycle: Int?
    /// Monotonic token for geometry-only changes. Subdivisions and tempo-only
    /// revisions deliberately leave it unchanged.
    private(set) var geometryRevision: UInt64 = 0
    private(set) var lastGeometryTransition: BeatVisualGeometryTransition?
    private var latestEventCursor: EventCursor?
    /// The main-beat vertex which owns the most recent valid pulse. It
    /// deliberately survives pauses and interval-only tempo changes so
    /// peripheral vision can still locate the current beat after the short Hit
    /// has decayed. Subdivision pulses select their containing main beat.
    private(set) var currentBeatIndex: Int?
    /// Last engine-authored position around the polygon, measured in main-beat
    /// units. This is a snapshot rather than a visual clock. Renderers may
    /// interpolate from it but must never feed a derived value back into BPM.
    private(set) var ballPhase: Double?
    /// Immutable start position for the return-to-origin animation.
    private(set) var returnStartBallPhase: Double?
    private(set) var ballIsAtOrigin = true
    private(set) var isPaused = true

    init(beats: Int = 4) {
        beatCount = Self.normalizedBeatCount(beats)
    }

    /// Compatibility view used by existing renderers. Values are polygon slot
    /// indices in generation order, not musical beat numbers. During beat `n`
    /// they are `[n, n-1, ... 0]`.
    var visibleEdgeIndices: [Int] {
        visibleEdgePlacements.map(\.slotIndex)
    }

    var hasEstablishedStructure: Bool {
        visibleEdgePlacements.count == beatCount
            && phase != .origin
            && phase != .settled
    }

    var builtEdgeCount: Int { visibleEdgePlacements.count }

    var latestBuiltEdgeIndex: Int? { visibleEdgePlacements.last?.slotIndex }

    /// Snapshot used by a renderer to schedule reverse teardown without
    /// mutating this model on every animation frame.
    var dismantlingOrder: [Int] {
        visibleEdgePlacements.reversed().map(\.slotIndex)
    }

    var nextEdgeToDismantle: Int? {
        phase == .dismantling ? visibleEdgePlacements.last?.slotIndex : nil
    }

    /// Compatibility view for renderers which still draw vertex anchors.
    /// Unlike `visibleEdgeIndices`, this is a set of visible edge endpoints and
    /// deliberately carries no construction-order semantics.
    var visibleBeatIndices: [Int] {
        switch phase {
        case .origin, .settled:
            return []
        case .building, .orbiting, .finishing, .dismantling:
            guard !visibleEdgePlacements.isEmpty else { return [] }
            return Set(visibleEdgeIndices.flatMap { edge in
                [edge, (edge + 1) % beatCount]
            }).sorted()
        }
    }

    mutating func reset(beats: Int) {
        self = BeatVisualLifecycle(beats: beats)
    }

    /// Replaces an event topology (for example quarter → sixteenth training
    /// pulses) without allowing the previous scheduler cursor to reject the
    /// restarted cycle-zero stream as stale.
    mutating func resetScheduleTopology(beats: Int, isPlaying: Bool) {
        self = BeatVisualLifecycle(beats: beats)
        if isPlaying {
            resume()
        }
    }

    mutating func reconfigure(beats: Int) {
        let normalized = Self.normalizedBeatCount(beats)
        guard normalized != beatCount else { return }

        // A changed time signature is a new topology and therefore starts a
        // new construction lifecycle. Preserve only whether playback was live;
        // same-topology tempo changes never enter this branch.
        let wasPlaying = !isPaused
            && phase != .finishing
            && phase != .dismantling
            && phase != .settled
        self = BeatVisualLifecycle(beats: normalized)
        isPaused = !wasPlaying
    }

    mutating func resume() {
        guard phase != .finishing,
              phase != .dismantling,
              phase != .settled
        else { return }
        isPaused = false
    }

    mutating func pause() {
        guard phase != .finishing,
              phase != .dismantling,
              phase != .settled
        else { return }
        isPaused = true
    }

    /// Clears only the persistent main-beat locator while preserving the
    /// established geometry. Used when the event topology is replaced and the
    /// old vertex can no longer describe the pending scheduler cursor.
    mutating func clearCurrentBeatLocation() {
        currentBeatIndex = nil
    }

    @discardableResult
    mutating func record(
        beat: Int,
        subdivision: Int,
        cycle: Int,
        beats: Int
    ) -> BeatVisualGeometryTransition? {
        record(
            beat: beat,
            subdivision: subdivision,
            cycle: cycle,
            beats: beats,
            pulsesPerBeat: nil
        )
    }

    /// Records one event from the authoritative scheduler. The legacy overload
    /// above remains source-compatible; new call sites should provide
    /// `pulsesPerBeat` so subdivision positions are exact.
    @discardableResult
    mutating func record(
        beat: Int,
        subdivision: Int,
        cycle: Int,
        beats: Int,
        pulsesPerBeat: Int
    ) -> BeatVisualGeometryTransition? {
        record(
            beat: beat,
            subdivision: subdivision,
            cycle: cycle,
            beats: beats,
            pulsesPerBeat: Optional(pulsesPerBeat)
        )
    }

    private mutating func record(
        beat: Int,
        subdivision: Int,
        cycle: Int,
        beats: Int,
        pulsesPerBeat: Int?
    ) -> BeatVisualGeometryTransition? {
        reconfigure(beats: beats)
        guard phase != .finishing,
              phase != .dismantling,
              phase != .settled,
              beat >= 0, beat < beatCount,
              subdivision >= 0,
              pulsesPerBeat.map({ $0 > 0 && subdivision < $0 }) ?? true
        else { return nil }

        let cursor = EventCursor(
            cycle: cycle,
            beat: beat,
            subdivision: subdivision
        )
        // Duplicate or late callbacks cannot rewind a measure, fabricate an
        // edge, move the glance locator backward, or implicitly resume pause.
        guard latestEventCursor.map({ $0 < cursor }) ?? true else { return nil }

        let previousCycle = currentMeasureCycle
        let previousPlacements = visibleEdgePlacements
        let startsNewCycle = previousCycle.map { $0 != cycle } ?? false
        latestEventCursor = cursor
        currentMeasureCycle = cycle

        isPaused = false
        currentBeatIndex = beat
        ballIsAtOrigin = false

        let inferredPulsesPerBeat = pulsesPerBeat ?? max(1, subdivision + 1)
        ballPhase = Self.normalizedBallPhase(
            Double(beat) + Double(subdivision) / Double(inferredPulsesPerBeat),
            beats: beatCount
        )

        // Seeing any event in a newer cycle retires the complete previous
        // polygon. A missed first main-beat callback may therefore leave the
        // new measure empty until another authoritative main beat arrives;
        // subdivisions still never construct an edge.
        if startsNewCycle, subdivision != 0 {
            guard !previousPlacements.isEmpty else { return nil }
            return installGeometry(
                [],
                kind: .measureReset,
                cycle: cycle,
                beat: beat,
                previousPlacements: previousPlacements,
                rotateRetainedEdges: false
            )
        }

        // A subdivision moves/pulses the ball but can never create geometry.
        guard subdivision == 0 else { return nil }

        let placements = Self.placements(duringBeat: beat)
        let kind: BeatVisualGeometryTransition.Kind
        let rotatesRetainedEdges: Bool
        if startsNewCycle {
            kind = .measureReset
            rotatesRetainedEdges = false
        } else if previousPlacements.isEmpty {
            kind = beat == 0 ? .measureStart : .gapRecovery
            rotatesRetainedEdges = false
        } else {
            let expectedPreviousBeat = previousPlacements.count - 1
            kind = beat == expectedPreviousBeat + 1
                ? .beatAdvance
                : .gapRecovery
            rotatesRetainedEdges = true
        }

        guard placements != previousPlacements || startsNewCycle else {
            return nil
        }
        return installGeometry(
            placements,
            kind: kind,
            cycle: cycle,
            beat: beat,
            previousPlacements: previousPlacements,
            rotateRetainedEdges: rotatesRetainedEdges
        )
    }

    private mutating func installGeometry(
        _ placements: [BeatVisualEdgePlacement],
        kind: BeatVisualGeometryTransition.Kind,
        cycle: Int,
        beat: Int,
        previousPlacements: [BeatVisualEdgePlacement],
        rotateRetainedEdges: Bool
    ) -> BeatVisualGeometryTransition {
        let previousByGeneration = Dictionary(
            uniqueKeysWithValues: previousPlacements.map {
                ($0.generationIndex, $0.slotIndex)
            }
        )
        let rotations: [BeatVisualEdgeRotation]
        if rotateRetainedEdges {
            rotations = placements.compactMap { placement in
                guard let oldSlot = previousByGeneration[placement.generationIndex],
                      oldSlot != placement.slotIndex
                else { return nil }
                return BeatVisualEdgeRotation(
                    generationIndex: placement.generationIndex,
                    fromSlotIndex: oldSlot,
                    toSlotIndex: placement.slotIndex
                )
            }
        } else {
            rotations = []
        }
        let inserted: [BeatVisualEdgePlacement]
        if kind == .measureReset || kind == .measureStart {
            inserted = placements
        } else {
            inserted = placements.filter {
                previousByGeneration[$0.generationIndex] == nil
            }
        }

        geometryRevision &+= 1
        visibleEdgePlacements = placements
        phase = placements.isEmpty
            ? .origin
            : placements.count == beatCount ? .orbiting : .building
        let transition = BeatVisualGeometryTransition(
            revision: geometryRevision,
            kind: kind,
            cycle: cycle,
            beat: beat,
            previousPlacements: previousPlacements,
            placements: placements,
            rotations: rotations,
            insertedPlacements: inserted
        )
        lastGeometryTransition = transition
        return transition
    }

    mutating func beginFinishing() {
        guard phase != .finishing,
              phase != .dismantling,
              phase != .settled
        else { return }
        isPaused = true
        currentBeatIndex = nil
        returnStartBallPhase = ballPhase
        phase = .finishing
    }

    /// Marks completion of the ball's return. Edge teardown cannot begin
    /// before this transition, including under Reduce Motion; accessibility
    /// settings shorten presentation duration, not lifecycle semantics.
    mutating func completeCenterReturn() {
        guard phase == .finishing else { return }
        ballPhase = nil
        ballIsAtOrigin = true
        if visibleEdgePlacements.isEmpty {
            settle()
        } else {
            phase = .dismantling
        }
    }

    /// Removes exactly the most recently constructed remaining edge.
    /// Returning the edge index lets a renderer verify that its animation and
    /// the model committed the same reverse-order step.
    @discardableResult
    mutating func removeNextDismantlingEdge() -> Int? {
        guard phase == .dismantling,
              let removed = visibleEdgePlacements.popLast()
        else { return nil }

        if visibleEdgePlacements.isEmpty {
            settle()
        }
        return removed.slotIndex
    }

    mutating func settle() {
        isPaused = true
        currentBeatIndex = nil
        ballPhase = nil
        returnStartBallPhase = nil
        ballIsAtOrigin = true
        visibleEdgePlacements.removeAll(keepingCapacity: false)
        currentMeasureCycle = nil
        latestEventCursor = nil
        lastGeometryTransition = nil
        phase = .settled
    }

    private static func placements(duringBeat beat: Int) -> [BeatVisualEdgePlacement] {
        (0...beat).map { generation in
            BeatVisualEdgePlacement(
                generationIndex: generation,
                slotIndex: beat - generation
            )
        }
    }

    private static func normalizedBeatCount(_ beats: Int) -> Int {
        min(max(beats, 3), 9)
    }

    private static func normalizedBallPhase(_ phase: Double, beats: Int) -> Double {
        let period = Double(beats)
        let remainder = phase.truncatingRemainder(dividingBy: period)
        return remainder >= 0 ? remainder : remainder + period
    }
}

/// Presentation-neutral tokens for a persistent geometry anchor. The canvas
/// owns drawing and animation; this model only defines the visual hierarchy
/// that must survive the short pulse envelope.
struct BeatAnchorVisualStyle: Equatable, Sendable {
    let radius: Double
    let opacity: Double

    /// A stable comparison value for tests and alternate renderers. It is not
    /// intended to be interpreted as a physical luminance measurement.
    var prominence: Double {
        radius * opacity
    }
}

/// Keeps the current main-beat locator visually dominant without coupling the
/// rhythm model to SwiftUI, Canvas, or a particular screen size.
enum BeatVisualHierarchyModel {
    static let inactiveAnchorStyle = BeatAnchorVisualStyle(
        radius: 3.8,
        opacity: 0.30
    )

    static let currentPlayingAnchorStyle = BeatAnchorVisualStyle(
        radius: 6.4,
        opacity: 0.88
    )

    static let currentPausedAnchorStyle = BeatAnchorVisualStyle(
        radius: 6.0,
        opacity: 0.70
    )

    static func anchorStyle(
        for beatIndex: Int,
        lifecycle: BeatVisualLifecycle
    ) -> BeatAnchorVisualStyle {
        guard (lifecycle.phase == .building || lifecycle.phase == .orbiting),
              lifecycle.currentBeatIndex == beatIndex
        else { return inactiveAnchorStyle }

        return lifecycle.isPaused
            ? currentPausedAnchorStyle
            : currentPlayingAnchorStyle
    }

    static func pulseStyle(
        for kind: BeatPulseKind,
        eventInterval: TimeInterval,
        dimFlashingLights: Bool = false
    ) -> BeatPulseStyle {
        BeatPulseVisualModel.style(
            for: kind,
            eventInterval: eventInterval,
            dimFlashingLights: dimFlashingLights
        )
    }
}

/// The small set of facts a musician should be able to obtain at a glance
/// while the controls remain secondary. This value is renderer-agnostic so
/// the compact iPhone and spacious iPad layouts can present the same truth.
struct MetronomeGlanceStatus: Equatable, Sendable {
    enum State: String, Equatable, Sendable {
        case ready
        case playing
        case paused
        case finishing
        case finished

        var title: String {
            switch self {
            case .ready: "准备"
            case .playing: "演奏中"
            case .paused: "已暂停"
            case .finishing: "正在结束"
            case .finished: "已结束"
            }
        }
    }

    let state: State
    let bpm: Int
    let referenceNote: TempoReferenceNote
    let trainingNote: TempoReferenceNote
    let beats: Int
    let grouping: String
    let hand: PracticeHand
    /// Human-facing beat number. Unlike `BeatVisualLifecycle.currentBeatIndex`,
    /// this value is one-based so it can be displayed or spoken directly.
    let currentMainBeat: Int?

    init(
        preset: MetronomePreset,
        hand: PracticeHand,
        lifecycle: BeatVisualLifecycle,
        isPlaying: Bool,
        isFinishing: Bool = false,
        isFinished: Bool = false,
        effectiveReferenceNote: TempoReferenceNote? = nil
    ) {
        let preset = preset.normalized
        self.state = Self.resolveState(
            lifecycle: lifecycle,
            isPlaying: isPlaying,
            isFinishing: isFinishing,
            isFinished: isFinished
        )
        bpm = preset.bpm
        referenceNote = effectiveReferenceNote ?? preset.referenceNote
        trainingNote = TempoReferenceNote.trainingNote(for: preset.subdivision)
        beats = preset.beats
        grouping = preset.grouping
        self.hand = hand
        currentMainBeat = lifecycle.currentBeatIndex.flatMap { index in
            (0..<preset.beats).contains(index) ? index + 1 : nil
        }
    }

    var stateTitle: String { state.title }

    var bpmText: String { "\(bpm) BPM" }

    var referenceTempoText: String {
        "\(referenceNote.symbol) = \(bpm)"
    }

    var trainingNoteText: String { trainingNote.symbol }

    var beatStructureText: String {
        grouping == "标准"
            ? "\(beats) 拍"
            : "\(beats) 拍 · \(grouping)"
    }

    var currentBeatText: String {
        guard let currentMainBeat else {
            return state == .playing ? "等待首拍" : "尚无当前拍"
        }
        return "第 \(currentMainBeat) / \(beats) 拍"
    }

    var statusText: String {
        "\(stateTitle) · \(currentBeatText) · \(bpmText)"
    }

    /// VoiceOver and other non-visual clients should receive the same status
    /// hierarchy without having to pronounce SMuFL private-use glyphs.
    var accessibilitySummary: String {
        let beatDescription = currentMainBeat.map {
            "当前第 \($0) 拍，共 \(beats) 拍"
        } ?? "共 \(beats) 拍，尚无当前拍"
        let groupingDescription = grouping == "标准"
            ? "标准分组"
            : "分组 \(grouping)"
        let tempoDescription = "速度基准，\(referenceNote.title)等于每分钟 \(bpm) 拍"
        return [
            stateTitle,
            beatDescription,
            tempoDescription,
            groupingDescription,
            "训练音符\(trainingNote.title)",
            hand.title
        ].joined(separator: "，")
    }

    private static func resolveState(
        lifecycle: BeatVisualLifecycle,
        isPlaying: Bool,
        isFinishing: Bool,
        isFinished: Bool
    ) -> State {
        if isFinished || lifecycle.phase == .settled { return .finished }
        if isFinishing
            || lifecycle.phase == .finishing
            || lifecycle.phase == .dismantling {
            return .finishing
        }
        if isPlaying { return .playing }
        if lifecycle.phase == .building || lifecycle.phase == .orbiting {
            return .paused
        }
        return .ready
    }
}
