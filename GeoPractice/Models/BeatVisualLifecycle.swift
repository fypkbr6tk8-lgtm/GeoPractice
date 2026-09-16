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

struct BeatCollisionVisualSample: Equatable, Sendable {
    let edgeSpread: Double
    let edgeOpacity: Double
    let edgeLineWidthBoost: Double

    static let empty = BeatCollisionVisualSample(
        edgeSpread: 0,
        edgeOpacity: 0,
        edgeLineWidthBoost: 0
    )
}

/// A short edge impulse for one physical contact. Strong, secondary, weak and
/// subdivision beats share the same motion language; only their energy changes.
enum BeatCollisionVisualModel {
    static func collisionAge(
        eventAge: TimeInterval,
        eventInterval: TimeInterval,
        startsFromOrigin: Bool
    ) -> TimeInterval {
        guard eventAge.isFinite, eventInterval.isFinite else { return -.infinity }
        let impactDelay = startsFromOrigin
            ? max(0, eventInterval) * BeatBounceMotionModel.initialImpactFraction
            : 0
        return eventAge - impactDelay
    }

    /// Keeps the collision language inside the quiet part of the scheduler
    /// interval. The persistent polygon starts rotating at 26%, so an ordinary
    /// impact is fully gone before that motion begins. The launch-only impact
    /// occurs at 62% and finishes by 86% while the first edge is still growing.
    static func effectDuration(
        styleDuration: TimeInterval,
        eventInterval: TimeInterval,
        startsFromOrigin: Bool
    ) -> TimeInterval {
        guard styleDuration.isFinite,
              eventInterval.isFinite,
              styleDuration > 0,
              eventInterval > 0
        else { return 0 }
        let intervalFraction = startsFromOrigin ? 0.24 : 0.22
        return min(styleDuration, eventInterval * intervalFraction)
    }

    static func sample(
        for kind: BeatPulseKind,
        age: TimeInterval,
        duration: TimeInterval,
        reduceMotion: Bool = false,
        dimFlashingLights: Bool = false,
        suppressTransientFeedback: Bool = false
    ) -> BeatCollisionVisualSample {
        guard !suppressTransientFeedback,
              age.isFinite,
              duration.isFinite,
              age >= 0,
              duration > 0,
              age < duration
        else { return .empty }

        let progress = min(1, max(0, age / duration))
        let expansion = 1 - pow(1 - progress, 3)
        let decay = pow(1 - progress, 1.7)
        let flashScale = dimFlashingLights ? 0.55 : 1

        let maximumSpread: Double
        let peakEdgeOpacity: Double
        let peakLineWidthBoost: Double
        switch kind {
        case .strong:
            maximumSpread = 0.62
            peakEdgeOpacity = 0.56
            peakLineWidthBoost = 2.4
        case .secondary:
            maximumSpread = 0.48
            peakEdgeOpacity = 0.40
            peakLineWidthBoost = 1.8
        case .weak:
            maximumSpread = 0.34
            peakEdgeOpacity = 0.25
            peakLineWidthBoost = 1.2
        case .subdivision:
            maximumSpread = 0.24
            peakEdgeOpacity = 0.12
            peakLineWidthBoost = 0.6
        }

        let edgeSpread = reduceMotion
            ? maximumSpread
            : (0.08 + (maximumSpread - 0.08) * expansion)
        let edgeOpacity = peakEdgeOpacity * decay * flashScale
        let edgeLineWidthBoost = peakLineWidthBoost * decay
        return BeatCollisionVisualSample(
            edgeSpread: edgeSpread,
            edgeOpacity: edgeOpacity,
            edgeLineWidthBoost: edgeLineWidthBoost
        )
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
    /// The launch-only entrance uses the first part of the first scheduler
    /// interval for a gravity-led descent. Once this point is reached the ball
    /// remains in contact while the first edge grows out from the impact.
    static let initialImpactFraction = 0.62

    /// A resumed pulse first reconnects the frozen ball to its new musical arc
    /// before polygon rotation begins. Sharing this boundary with the edge
    /// presentation model prevents a contact ball from being left behind while
    /// its supporting edge starts to turn.
    static let resumeBlendCompletionFraction = 0.26

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
        // A sine arc keeps both contacts exact and softens the old parabola's
        // launch velocity while retaining a definite contact velocity. The
        // impact therefore still reads as a hit instead of hovering at the edge.
        guard progress > 0, progress < 1 else { return 0 }
        return tier.normalizedPeakHeight * sin(.pi * progress)
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
        guard motionScale.isFinite else { return 0 }
        let scale = min(1, max(0, motionScale))
        if startsFromOrigin {
            return normalizedInitialDescentHeight(eventProgress: eventProgress)
                * scale
        }
        return normalizedArcHeight(
            eventProgress: eventProgress,
            tier: tier
        ) * scale
    }

    /// Motion owned by an audible scheduler event. At progress zero the sound
    /// has begun and the ball is already touching its matching edge; at progress
    /// one it has landed for the following event. Center-to-edge descent is a
    /// separate silent pre-roll concern and must never delay an audible hit.
    static func normalizedAudibleEventHeight(
        eventProgress: Double,
        toward tier: BeatBounceHeightTier,
        motionScale: Double = 1
    ) -> Double {
        normalizedEventHeight(
            eventProgress: eventProgress,
            toward: tier,
            startsFromOrigin: false,
            motionScale: motionScale
        )
    }

    /// At a visual-session reset the first strong beat starts at the
    /// center/apex and falls to the newly generated horizontal edge. Later
    /// measure boundaries do not use this curve: their first beat starts at
    /// the contact left by the preceding event.
    static func normalizedInitialDescentHeight(eventProgress: Double) -> Double {
        guard !eventProgress.isNaN else { return 0 }
        let progress = min(1, max(0, eventProgress))
        let descentProgress = min(1, progress / initialImpactFraction)
        return BeatBounceHeightTier.strong.normalizedPeakHeight
            * (1 - descentProgress * descentProgress * descentProgress)
    }

    /// Reconnects a ball frozen by pause to the trajectory owned by the next
    /// authoritative audio pulse. The first sampled frame is exactly the
    /// frozen height; by the time edge rotation may start it has joined the new
    /// arc. There is no synthetic landing while a previously frozen polygon is
    /// still between slots.
    static func resumeNormalizedHeight(
        from frozenHeight: Double,
        toward targetHeight: Double,
        eventProgress: Double,
        reduceMotion: Bool = false
    ) -> Double {
        guard frozenHeight.isFinite,
              targetHeight.isFinite,
              eventProgress.isFinite
        else { return 0 }

        let source = min(1, max(0, frozenHeight))
        let target = min(1, max(0, targetHeight))
        guard !reduceMotion else { return target }

        let raw = min(
            1,
            max(0, eventProgress) / resumeBlendCompletionFraction
        )
        let progress = raw * raw * raw * (raw * (raw * 6 - 15) + 10)
        return source + (target - source) * progress
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

/// One generated edge and the polygon slot it currently occupies. The stable
/// generation ID lets renderers track the same line across animation frames;
/// `beatIdentity` carries the musical accent after a scheduler phase resync.
/// Slot zero is the fixed horizontal generation slot and increasing slots
/// rotate clockwise.
struct BeatVisualEdgePlacement: Equatable, Sendable {
    let generationIndex: Int
    let beatIdentity: Int
    let slotIndex: Int

    init(
        generationIndex: Int,
        slotIndex: Int,
        beatIdentity: Int? = nil
    ) {
        self.generationIndex = generationIndex
        self.beatIdentity = beatIdentity ?? generationIndex
        self.slotIndex = slotIndex
    }
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

/// Stable musical emphasis owned by an edge. This follows the edge's current
/// scheduler-aligned beat identity while the complete polygon rotates; it is
/// never inferred from the slot during ordinary playback.
enum BeatEdgeAccentLevel: Equatable, Sendable {
    case strong
    case secondary
    case weak

    var opacity: Double {
        switch self {
        case .strong: 0.96
        case .secondary: 0.68
        case .weak: 0.34
        }
    }

    /// Every edge uses the same heavier stroke. Accent identity is expressed
    /// through stable luminance and collision energy, not a protruding line
    /// which becomes visually distracting while the polygon rotates.
    var lineWidth: Double {
        3.2
    }
}

/// Renderer-neutral facts for one edge at a particular presentation instant.
/// `slot` is deliberately unwrapped during rotation (for example 4 -> 5 in a
/// five-sided polygon) so a wrap can never interpolate backwards through four
/// counterclockwise slots. Renderers may convert it directly to an angle.
struct BeatEdgePresentation: Equatable, Sendable {
    let generationIndex: Int
    let beatIdentity: Int
    let slot: Double
    let drawProgress: Double
    let accentLevel: BeatEdgeAccentLevel
    let opacity: Double
    let lineWidth: Double
}

/// Geometry presented during one audible scheduler interval. The committed
/// lifecycle always describes the beat which has just sounded. When motion is
/// enabled, only the final subdivision previews the following main beat so its
/// edge reaches the contact slot before that following sound begins.
struct BeatVisualIntervalGeometry: Equatable, Sendable {
    let placements: [BeatVisualEdgePlacement]
    let transition: BeatVisualGeometryTransition?
}

/// One shared presentation policy for both metronome canvases. A main-beat
/// pulse supplies its current training-event progress; this model completes the
/// whole transition before the following pulse must land on a stable horizontal
/// edge. Ball motion remains event-based and independent.
enum BeatPolygonPresentationModel {
    static let rotationStartFraction = BeatBounceMotionModel.resumeBlendCompletionFraction
    static let rotationCompletionFraction = 0.90
    /// Compatibility name for the instant at which geometry is fully stable.
    static let activeTransitionFraction = rotationCompletionFraction
    static let insertionDelayFraction = 0.04
    static let insertionCompletionFraction = 0.58
    static let initialInsertionDelayFraction = BeatBounceMotionModel.initialImpactFraction
    static let initialInsertionCompletionFraction = 1.0
    static let uniformLineWidth = BeatEdgeAccentLevel.strong.lineWidth

    /// Keeps the edge under the ball musically aligned with the audible pulse.
    ///
    /// The scheduler pulse identifies the sound occurring *now*. Therefore the
    /// lifecycle's committed placements are already the correct geometry for
    /// `eventProgress == 0`. A transition toward the next main beat is prepared
    /// during the current beat's final subdivision, completing before the next
    /// pulse lands. This avoids the former one-beat lag where the current pulse
    /// started the transition which should already have finished.
    static func intervalGeometry(
        lifecycle: BeatVisualLifecycle,
        beat: Int,
        subdivision: Int,
        cycle: Int,
        pulsesPerBeat: Int,
        reduceMotion: Bool = false
    ) -> BeatVisualIntervalGeometry {
        let stable = BeatVisualIntervalGeometry(
            placements: lifecycle.visibleEdgePlacements,
            transition: nil
        )
        guard !reduceMotion,
              pulsesPerBeat > 0,
              beat >= 0, beat < lifecycle.beatCount,
              subdivision == pulsesPerBeat - 1
        else { return stable }

        let nextBeat = (beat + 1) % lifecycle.beatCount
        let nextCycle: Int
        if nextBeat == 0 {
            guard cycle < Int.max else { return stable }
            nextCycle = cycle + 1
        } else {
            nextCycle = cycle
        }

        var preview = lifecycle
        guard let transition = preview.record(
            beat: nextBeat,
            subdivision: 0,
            cycle: nextCycle,
            beats: lifecycle.beatCount,
            pulsesPerBeat: pulsesPerBeat
        ) else { return stable }

        return BeatVisualIntervalGeometry(
            placements: preview.visibleEdgePlacements,
            transition: transition
        )
    }

    static func contactLineWidth(
        presentations: [BeatEdgePresentation],
        beatCount: Int
    ) -> Double {
        let period = Double(max(1, beatCount))
        let contact = presentations.min { lhs, rhs in
            circularDistanceToContact(slot: lhs.slot, period: period)
                < circularDistanceToContact(slot: rhs.slot, period: period)
        }
        return contact?.lineWidth ?? uniformLineWidth
    }

    private static func circularDistanceToContact(
        slot: Double,
        period: Double
    ) -> Double {
        guard slot.isFinite else { return .infinity }
        let remainder = slot.truncatingRemainder(dividingBy: period)
        let normalized = remainder >= 0 ? remainder : remainder + period
        return min(normalized, period - normalized)
    }

    static func accentLevel(
        forBeatIdentity beatIdentity: Int,
        strongBeatIndices: Set<Int>,
        secondaryAccentIndices: Set<Int>
    ) -> BeatEdgeAccentLevel {
        if strongBeatIndices.contains(beatIdentity) { return .strong }
        if secondaryAccentIndices.contains(beatIdentity) { return .secondary }
        return .weak
    }

    static func transitionProgress(
        eventProgress: Double,
        reduceMotion: Bool = false
    ) -> Double {
        guard !reduceMotion else { return 1 }
        guard eventProgress.isFinite else {
            return eventProgress == .infinity ? 1 : 0
        }
        let duration = rotationCompletionFraction - rotationStartFraction
        let raw = min(1, max(
            0,
            (eventProgress - rotationStartFraction) / duration
        ))
        // Quintic smootherstep has zero first and second derivatives at both
        // endpoints, preventing the visible acceleration kink of smoothstep.
        return raw * raw * raw * (raw * (raw * 6 - 15) + 10)
    }

    static func insertionProgress(
        eventProgress: Double,
        startsFromOrigin: Bool = false,
        reduceMotion: Bool = false
    ) -> Double {
        guard !reduceMotion else { return 1 }
        guard eventProgress.isFinite else {
            return eventProgress == .infinity ? 1 : 0
        }
        let delay = startsFromOrigin
            ? initialInsertionDelayFraction
            : insertionDelayFraction
        let completion = startsFromOrigin
            ? initialInsertionCompletionFraction
            : insertionCompletionFraction
        let duration = completion - delay
        let raw = min(
            1,
            max(0, eventProgress - delay) / duration
        )
        // A short impact hold followed by ease-out growth makes the line emerge
        // from the contact point without sharing the rotation's mechanical pace.
        return 1 - pow(1 - raw, 3)
    }

    static func edgePresentations(
        placements: [BeatVisualEdgePlacement],
        transition: BeatVisualGeometryTransition?,
        eventProgress: Double,
        strongBeatIndices: Set<Int>,
        secondaryAccentIndices: Set<Int>,
        startsFromOrigin: Bool = false,
        reduceMotion: Bool = false
    ) -> [BeatEdgePresentation] {
        let progress = transitionProgress(
            eventProgress: eventProgress,
            reduceMotion: reduceMotion
        )
        let revealProgress = insertionProgress(
            eventProgress: eventProgress,
            startsFromOrigin: startsFromOrigin,
            reduceMotion: reduceMotion
        )
        let rotations = Dictionary(
            uniqueKeysWithValues: (transition?.rotations ?? []).map {
                ($0.generationIndex, $0)
            }
        )
        let inserted = Set(
            (transition?.insertedPlacements ?? []).map(\.generationIndex)
        )

        return placements.map { placement in
            let slot: Double
            if let rotation = rotations[placement.generationIndex] {
                slot = Double(rotation.fromSlotIndex)
                    + Double(rotation.toSlotIndex - rotation.fromSlotIndex) * progress
            } else {
                slot = Double(placement.slotIndex)
            }
            let accent = accentLevel(
                forBeatIdentity: placement.beatIdentity,
                strongBeatIndices: strongBeatIndices,
                secondaryAccentIndices: secondaryAccentIndices
            )
            return BeatEdgePresentation(
                generationIndex: placement.generationIndex,
                beatIdentity: placement.beatIdentity,
                slot: slot,
                drawProgress: inserted.contains(placement.generationIndex) ? revealProgress : 1,
                accentLevel: accent,
                opacity: accent.opacity,
                lineWidth: accent.lineWidth
            )
        }
    }

    /// Re-enters an interrupted visual transition without changing the audio
    /// cursor. Existing edges start at their frozen presentation; a target edge
    /// which did not yet exist starts invisibly at its target slot. Slots are
    /// unwrapped to the nearest nonnegative clockwise equivalent so resuming a
    /// wrap can never reverse direction.
    static func resumePresentations(
        from frozen: [BeatEdgePresentation],
        toward target: [BeatEdgePresentation],
        beatCount: Int,
        eventProgress: Double,
        reduceMotion: Bool = false
    ) -> [BeatEdgePresentation] {
        let progress = transitionProgress(
            eventProgress: eventProgress,
            reduceMotion: reduceMotion
        )
        guard progress > 0 else {
            let frozenByGeneration = Dictionary(
                uniqueKeysWithValues: frozen.map { ($0.generationIndex, $0) }
            )
            return target.map { destination in
                frozenByGeneration[destination.generationIndex]
                    ?? BeatEdgePresentation(
                        generationIndex: destination.generationIndex,
                        beatIdentity: destination.beatIdentity,
                        slot: destination.slot,
                        drawProgress: 0,
                        accentLevel: destination.accentLevel,
                        opacity: destination.opacity,
                        lineWidth: destination.lineWidth
                    )
            }
        }
        guard progress < 1 else { return target }

        let period = Double(max(1, beatCount))
        let frozenByGeneration = Dictionary(
            uniqueKeysWithValues: frozen.map { ($0.generationIndex, $0) }
        )
        return target.map { destination in
            guard let source = frozenByGeneration[destination.generationIndex]
            else {
                return BeatEdgePresentation(
                    generationIndex: destination.generationIndex,
                    beatIdentity: destination.beatIdentity,
                    slot: destination.slot,
                    drawProgress: destination.drawProgress * progress,
                    accentLevel: destination.accentLevel,
                    opacity: destination.opacity,
                    lineWidth: destination.lineWidth
                )
            }

            var unwrappedTargetSlot = destination.slot
            if unwrappedTargetSlot < source.slot {
                unwrappedTargetSlot += ceil(
                    (source.slot - unwrappedTargetSlot) / period
                ) * period
            }
            return BeatEdgePresentation(
                generationIndex: destination.generationIndex,
                beatIdentity: destination.beatIdentity,
                slot: source.slot
                    + (unwrappedTargetSlot - source.slot) * progress,
                drawProgress: source.drawProgress
                    + (destination.drawProgress - source.drawProgress) * progress,
                accentLevel: destination.accentLevel,
                opacity: source.opacity
                    + (destination.opacity - source.opacity) * progress,
                lineWidth: source.lineWidth
                    + (destination.lineWidth - source.lineWidth) * progress
            )
        }
    }
}

/// Playback and visual lifecycle are intentionally separate. The audio engine
/// supplies authoritative event addresses; this value builds one persistent
/// polygon for the visual session and remembers the facts which survive a pause,
/// a measure boundary, or an interval-only tempo change.
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
    /// Oldest-to-newest generated edges for this visual session. Slot zero is
    /// always the fixed horizontal generation slot. Construction happens only
    /// once; after closure every main beat rotates all retained edges one slot.
    private(set) var visibleEdgePlacements: [BeatVisualEdgePlacement] = []
    /// The cycle of the latest accepted scheduler event. Measure boundaries are
    /// timing addresses only and never clear completed geometry.
    private(set) var currentMeasureCycle: Int?
    /// Monotonic token for geometry-only changes.
    private(set) var geometryRevision: UInt64 = 0
    private(set) var lastGeometryTransition: BeatVisualGeometryTransition?
    private var latestEventCursor: EventCursor?
    /// Event-density changes restart the scheduler at cycle zero without
    /// changing the polygon. The first new main beat rebinds musical identities
    /// to the stationary edges, then ordinary one-slot rotation resumes.
    private var awaitsSchedulePhaseRebind = false
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

    /// Compatibility view used by existing renderers. Values are normalized
    /// polygon slots in stable generation/musical-beat order.
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

    /// Accepts a restarted cycle-zero stream after an event-density change.
    /// Training-note changes must not dismantle or rebuild the polygon; only a
    /// different beat count creates a new geometry lifecycle.
    mutating func resetScheduleTopology(beats: Int, isPlaying: Bool) {
        let normalized = Self.normalizedBeatCount(beats)
        if normalized != beatCount {
            self = BeatVisualLifecycle(beats: normalized)
        } else {
            latestEventCursor = nil
            currentMeasureCycle = nil
            currentBeatIndex = nil
            ballPhase = nil
            returnStartBallPhase = nil
            ballIsAtOrigin = visibleEdgePlacements.isEmpty
            lastGeometryTransition = nil
            awaitsSchedulePhaseRebind = !visibleEdgePlacements.isEmpty
            phase = visibleEdgePlacements.isEmpty
                ? .origin
                : visibleEdgePlacements.count == beatCount ? .orbiting : .building
        }
        isPaused = !isPlaying
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
              cycle >= 0,
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

        let previousCursor = latestEventCursor
        let previousPlacements = visibleEdgePlacements
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

        // A subdivision moves/pulses the ball but can never create geometry.
        guard subdivision == 0 else { return nil }

        let isSchedulePhaseRebind = awaitsSchedulePhaseRebind
        let phaseAlignedPlacements = isSchedulePhaseRebind
            ? Self.rebindingBeatIdentities(
                in: previousPlacements,
                toBeat: beat,
                beatCount: beatCount
            )
            : previousPlacements
        let placements = Self.placements(
            from: phaseAlignedPlacements,
            throughBeat: beat,
            cycle: cycle,
            beatCount: beatCount
        )
        let kind: BeatVisualGeometryTransition.Kind = if isSchedulePhaseRebind {
            .gapRecovery
        } else if previousPlacements.isEmpty {
            cycle == 0 && beat == 0 ? .measureStart : .gapRecovery
        } else {
            Self.isSequentialMainBeat(
                from: previousCursor,
                to: cursor,
                beatCount: beatCount
            ) ? .beatAdvance : .gapRecovery
        }
        awaitsSchedulePhaseRebind = false
        return installGeometry(
            placements,
            kind: kind,
            cycle: cycle,
            beat: beat,
            previousPlacements: previousPlacements
        )
    }

    private mutating func installGeometry(
        _ placements: [BeatVisualEdgePlacement],
        kind: BeatVisualGeometryTransition.Kind,
        cycle: Int,
        beat: Int,
        previousPlacements: [BeatVisualEdgePlacement]
    ) -> BeatVisualGeometryTransition {
        let previousByGeneration = Dictionary(
            uniqueKeysWithValues: previousPlacements.map {
                ($0.generationIndex, $0.slotIndex)
            }
        )
        let rotations: [BeatVisualEdgeRotation] = placements.compactMap { placement -> BeatVisualEdgeRotation? in
            guard let oldSlot = previousByGeneration[placement.generationIndex]
            else { return nil }
            let clockwiseDelta = Self.clockwiseSlotDelta(
                from: oldSlot,
                to: placement.slotIndex,
                beatCount: beatCount
            )
            guard clockwiseDelta > 0 else { return nil }
            return BeatVisualEdgeRotation(
                generationIndex: placement.generationIndex,
                fromSlotIndex: oldSlot,
                // Do not normalize this endpoint. A final-slot wrap must animate
                // N-1 -> N (clockwise), never N-1 -> 0 (backwards).
                toSlotIndex: oldSlot + clockwiseDelta
            )
        }
        let inserted = placements.filter {
            previousByGeneration[$0.generationIndex] == nil
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
        awaitsSchedulePhaseRebind = false
        phase = .settled
    }

    private static func placements(
        from placements: [BeatVisualEdgePlacement],
        throughBeat beat: Int,
        cycle: Int,
        beatCount: Int
    ) -> [BeatVisualEdgePlacement] {
        // A scheduler address is authoritative even if one or more UI callbacks
        // were missed. Cycle zero builds through the current beat; reaching any
        // later cycle proves the first polygon has already closed. A topology
        // resync may restart at cycle zero, so existing edges are never removed.
        let requiredIdentities = cycle > 0
            ? Array(0..<beatCount)
            : Array(0...beat)
        var result = placements
        var existingIdentities = Set(result.map(\.beatIdentity))
        var nextGeneration = (result.map(\.generationIndex).max() ?? -1) + 1

        for identity in requiredIdentities where !existingIdentities.contains(identity) {
            result.append(BeatVisualEdgePlacement(
                generationIndex: nextGeneration,
                slotIndex: 0,
                beatIdentity: identity
            ))
            existingIdentities.insert(identity)
            nextGeneration += 1
        }

        return result.map { placement in
            BeatVisualEdgePlacement(
                generationIndex: placement.generationIndex,
                slotIndex: positiveModulo(
                    beat - placement.beatIdentity,
                    modulus: beatCount
                ),
                beatIdentity: placement.beatIdentity
            )
        }
    }

    /// Keeps every line at its current slot while assigning the restarted
    /// scheduler's musical phase. This avoids a visually backwards N-1-slot
    /// correction when, for example, beat one restarts at beat zero.
    private static func rebindingBeatIdentities(
        in placements: [BeatVisualEdgePlacement],
        toBeat beat: Int,
        beatCount: Int
    ) -> [BeatVisualEdgePlacement] {
        placements.map { placement in
            BeatVisualEdgePlacement(
                generationIndex: placement.generationIndex,
                slotIndex: placement.slotIndex,
                beatIdentity: positiveModulo(
                    beat - placement.slotIndex,
                    modulus: beatCount
                )
            )
        }
    }

    private static func isSequentialMainBeat(
        from previous: EventCursor?,
        to current: EventCursor,
        beatCount: Int
    ) -> Bool {
        guard let previous else { return false }
        let expectedBeat = (previous.beat + 1) % beatCount
        let expectedCycle: Int
        if previous.beat == beatCount - 1 {
            guard previous.cycle < Int.max else { return false }
            expectedCycle = previous.cycle + 1
        } else {
            expectedCycle = previous.cycle
        }
        return current.beat == expectedBeat && current.cycle == expectedCycle
    }

    private static func positiveModulo(_ value: Int, modulus: Int) -> Int {
        let remainder = value % modulus
        return remainder >= 0 ? remainder : remainder + modulus
    }

    private static func clockwiseSlotDelta(
        from oldSlot: Int,
        to newSlot: Int,
        beatCount: Int
    ) -> Int {
        let delta = (newSlot - oldSlot) % beatCount
        return delta >= 0 ? delta : delta + beatCount
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
