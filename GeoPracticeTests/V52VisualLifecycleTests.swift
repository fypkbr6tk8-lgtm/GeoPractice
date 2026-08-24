import XCTest
@testable import GeoPractice

final class V52VisualLifecycleTests: XCTestCase {
    func testMotionModelCompletesExactlyOneTurnForQuarterEighthAndSixteenth() throws {
        let beats = 4

        for pulsesPerBeat in [1, 2, 4] {
            let eventsPerMeasure = beats * pulsesPerBeat
            for beat in 0..<beats {
                for subdivision in 0..<pulsesPerBeat {
                    let sample = try XCTUnwrap(BeatVisualMotionModel.sample(
                        beat: beat,
                        subdivision: subdivision,
                        elapsed: 0,
                        eventInterval: 0.125,
                        pulsesPerBeat: pulsesPerBeat,
                        eventsPerMeasure: eventsPerMeasure,
                        beats: beats
                    ))
                    let eventIndex = beat * pulsesPerBeat + subdivision
                    XCTAssertEqual(
                        sample.measurePhase,
                        Double(eventIndex) / Double(eventsPerMeasure),
                        accuracy: 0.000_001
                    )
                    XCTAssertEqual(
                        sample.perimeterPhase,
                        Double(beat) + Double(subdivision) / Double(pulsesPerBeat),
                        accuracy: 0.000_001
                    )
                }
            }

            let wrapped = try XCTUnwrap(BeatVisualMotionModel.sample(
                beat: beats - 1,
                subdivision: pulsesPerBeat - 1,
                elapsed: 0.125,
                eventInterval: 0.125,
                pulsesPerBeat: pulsesPerBeat,
                eventsPerMeasure: eventsPerMeasure,
                beats: beats
            ))
            XCTAssertEqual(wrapped.eventProgress, 1, accuracy: 0.000_001)
            XCTAssertEqual(wrapped.measurePhase, 0, accuracy: 0.000_001)
            XCTAssertEqual(wrapped.perimeterPhase, 0, accuracy: 0.000_001)
        }
    }

    func testMotionModelClampsNegativeAndOverlongElapsedTime() throws {
        let negative = try XCTUnwrap(BeatVisualMotionModel.sample(
            beat: 1,
            subdivision: 2,
            elapsed: -4,
            eventInterval: 0.25,
            pulsesPerBeat: 4,
            eventsPerMeasure: 16,
            beats: 4
        ))
        XCTAssertEqual(negative.eventProgress, 0)
        XCTAssertEqual(negative.perimeterPhase, 1.5, accuracy: 0.000_001)

        let overlong = try XCTUnwrap(BeatVisualMotionModel.sample(
            beat: 1,
            subdivision: 2,
            elapsed: 40,
            eventInterval: 0.25,
            pulsesPerBeat: 4,
            eventsPerMeasure: 16,
            beats: 4
        ))
        XCTAssertEqual(overlong.eventProgress, 1)
        XCTAssertEqual(overlong.perimeterPhase, 1.75, accuracy: 0.000_001)

        let infinite = try XCTUnwrap(BeatVisualMotionModel.sample(
            beat: 1,
            subdivision: 2,
            elapsed: .infinity,
            eventInterval: 0.25,
            pulsesPerBeat: 4,
            eventsPerMeasure: 16,
            beats: 4
        ))
        XCTAssertEqual(infinite, overlong)
    }

    func testMotionModelRejectsInconsistentSchedulerAddresses() {
        XCTAssertNil(BeatVisualMotionModel.sample(
            beat: 4,
            subdivision: 0,
            elapsed: 0,
            eventInterval: 1,
            pulsesPerBeat: 1,
            eventsPerMeasure: 4,
            beats: 4
        ))
        XCTAssertNil(BeatVisualMotionModel.sample(
            beat: 0,
            subdivision: 2,
            elapsed: 0,
            eventInterval: 1,
            pulsesPerBeat: 2,
            eventsPerMeasure: 8,
            beats: 4
        ))
        XCTAssertNil(BeatVisualMotionModel.sample(
            beat: 0,
            subdivision: 0,
            elapsed: 0,
            eventInterval: 1,
            pulsesPerBeat: 2,
            eventsPerMeasure: 7,
            beats: 4
        ))
    }

    func testSubdivisionMotionDoesNotChangeConstructedEdges() throws {
        var lifecycle = BeatVisualLifecycle(beats: 4)
        lifecycle.record(beat: 0, subdivision: 0, cycle: 0, beats: 4)
        let initialEdges = lifecycle.visibleEdgeIndices
        let initialRevision = lifecycle.geometryRevision

        var phases: [Double] = []
        for subdivision in 1..<4 {
            lifecycle.record(
                beat: 0,
                subdivision: subdivision,
                cycle: 0,
                beats: 4,
                pulsesPerBeat: 4
            )
            let sample = try XCTUnwrap(BeatVisualMotionModel.sample(
                beat: 0,
                subdivision: subdivision,
                elapsed: 0,
                eventInterval: 0.125,
                pulsesPerBeat: 4,
                eventsPerMeasure: 16,
                beats: 4
            ))
            phases.append(sample.perimeterPhase)
        }

        XCTAssertEqual(lifecycle.visibleEdgeIndices, initialEdges)
        XCTAssertEqual(lifecycle.geometryRevision, initialRevision)
        XCTAssertEqual(phases, [0.25, 0.5, 0.75])
    }

    func testBounceTargetsUseTheStrengthOfTheNextEvent() throws {
        let strong = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
            afterBeat: 3,
            subdivision: 3,
            beats: 4,
            pulsesPerBeat: 4,
            strongBeatIndices: [0],
            secondaryAccentIndices: [2]
        ))
        XCTAssertEqual(strong.beat, 0)
        XCTAssertEqual(strong.subdivision, 0)
        XCTAssertEqual(strong.kind, .strong)
        XCTAssertEqual(strong.heightTier, .strong)
        XCTAssertTrue(strong.wrapsToNextMeasure)

        let ordinaryMainBeat = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
            afterBeat: 0,
            subdivision: 3,
            beats: 4,
            pulsesPerBeat: 4,
            strongBeatIndices: [0],
            secondaryAccentIndices: [2]
        ))
        XCTAssertEqual(ordinaryMainBeat.beat, 1)
        XCTAssertEqual(ordinaryMainBeat.heightTier, .main)

        let secondary = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
            afterBeat: 1,
            subdivision: 3,
            beats: 4,
            pulsesPerBeat: 4,
            strongBeatIndices: [0],
            secondaryAccentIndices: [2]
        ))
        XCTAssertEqual(secondary.beat, 2)
        XCTAssertEqual(secondary.heightTier, .secondary)

        let subdivision = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
            afterBeat: 0,
            subdivision: 0,
            beats: 4,
            pulsesPerBeat: 4,
            strongBeatIndices: [0],
            secondaryAccentIndices: [2]
        ))
        XCTAssertEqual(subdivision.subdivision, 1)
        XCTAssertEqual(subdivision.heightTier, .subdivision)
    }

    func testBounceHeightHierarchyAndBoundaryConditions() {
        let tiers: [BeatBounceHeightTier] = [
            .strong, .secondary, .main, .subdivision
        ]
        let peaks = tiers.map {
            BeatBounceMotionModel.normalizedArcHeight(
                eventProgress: 0.5,
                tier: $0
            )
        }
        for pair in zip(peaks, peaks.dropFirst()) {
            XCTAssertGreaterThan(pair.0, pair.1)
        }
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedArcHeight(
                eventProgress: -1,
                tier: .strong
            ),
            0
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedArcHeight(
                eventProgress: 2,
                tier: .strong
            ),
            0
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedInitialDescentHeight(
                eventProgress: 0
            ),
            1
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedInitialDescentHeight(
                eventProgress: 1
            ),
            0
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 0,
                toward: .strong,
                startsFromOrigin: false
            ),
            0
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 0.5,
                toward: .strong,
                startsFromOrigin: false
            ),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 1,
                toward: .strong,
                startsFromOrigin: false
            ),
            0
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 0.5,
                toward: .strong,
                startsFromOrigin: false,
                motionScale: 0.32
            ),
            0.32,
            accuracy: 0.000_001
        )
    }

    func testEveryPostLaunchTrainingPulseLandsIncludingMeasureBoundary() throws {
        let initialTarget = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
            afterBeat: 0,
            subdivision: 0,
            beats: 4,
            pulsesPerBeat: 4,
            strongBeatIndices: [0],
            secondaryAccentIndices: [2]
        ))
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 0,
                toward: initialTarget.heightTier,
                startsFromOrigin: true
            ),
            1
        )
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 1,
                toward: initialTarget.heightTier,
                startsFromOrigin: true
            ),
            0
        )

        for event in 1..<32 {
            let eventInMeasure = event % 16
            let beat = eventInMeasure / 4
            let subdivision = eventInMeasure % 4
            let target = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
                afterBeat: beat,
                subdivision: subdivision,
                beats: 4,
                pulsesPerBeat: 4,
                strongBeatIndices: [0],
                secondaryAccentIndices: [2]
            ))
            for progress in [0.0, 1.0] {
                XCTAssertEqual(
                    BeatBounceMotionModel.normalizedEventHeight(
                        eventProgress: progress,
                        toward: target.heightTier,
                        startsFromOrigin: false
                    ),
                    0,
                    accuracy: 0.000_001,
                    "event \(event) must contact once per training interval"
                )
            }
        }

        let wrapTarget = try XCTUnwrap(BeatBounceMotionModel.nextTarget(
            afterBeat: 3,
            subdivision: 3,
            beats: 4,
            pulsesPerBeat: 4,
            strongBeatIndices: [0],
            secondaryAccentIndices: [2]
        ))
        XCTAssertTrue(wrapTarget.wrapsToNextMeasure)
        XCTAssertEqual(
            BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 0.5,
                toward: wrapTarget.heightTier,
                startsFromOrigin: false
            ),
            1,
            accuracy: 0.000_001
        )
    }

    func testScheduleTopologyResetAcceptsRestartedCycleZeroImmediately() {
        var lifecycle = BeatVisualLifecycle(beats: 4)
        lifecycle.resume()
        lifecycle.record(
            beat: 3,
            subdivision: 3,
            cycle: 7,
            beats: 4,
            pulsesPerBeat: 4
        )
        XCTAssertEqual(lifecycle.currentMeasureCycle, 7)

        lifecycle.resetScheduleTopology(beats: 4, isPlaying: true)
        XCTAssertFalse(lifecycle.isPaused)
        XCTAssertNil(lifecycle.currentMeasureCycle)
        XCTAssertTrue(lifecycle.visibleEdgePlacements.isEmpty)

        let transition = lifecycle.record(
            beat: 0,
            subdivision: 0,
            cycle: 0,
            beats: 4,
            pulsesPerBeat: 2
        )
        XCTAssertEqual(transition?.kind, .measureStart)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [0])
        XCTAssertEqual(lifecycle.currentMeasureCycle, 0)
    }

    func testBounceContactPlacesTheBallOutsideTheEdgeStroke() {
        let distance = 80.0
        let radius = 7.0
        let stroke = 2.0
        let contact = BeatBounceContactGeometry.inwardOffset(
            edgeToCenterDistance: distance,
            ballRadius: radius,
            edgeStrokeWidth: stroke,
            normalizedHeight: 0
        )
        XCTAssertEqual(contact, radius + stroke / 2, accuracy: 0.000_001)
        XCTAssertEqual(
            BeatBounceContactGeometry.inwardOffset(
                edgeToCenterDistance: distance,
                ballRadius: radius,
                edgeStrokeWidth: stroke,
                normalizedHeight: 1
            ),
            distance,
            accuracy: 0.000_001
        )

        for height in [0.0, 0.01, 0.20, 0.46, 0.72, 0.99, 1.0] {
            let offset = BeatBounceContactGeometry.inwardOffset(
                edgeToCenterDistance: distance,
                ballRadius: radius,
                edgeStrokeWidth: stroke,
                normalizedHeight: height
            )
            XCTAssertGreaterThanOrEqual(
                offset,
                radius + stroke / 2,
                "The rendered ball must stay outside the visible stroke"
            )
        }

        // An impossible visual profile still prefers no penetration over
        // forcing an oversized ball's center inside the polygon.
        XCTAssertEqual(
            BeatBounceContactGeometry.inwardOffset(
                edgeToCenterDistance: 4,
                ballRadius: 7,
                edgeStrokeWidth: 2,
                normalizedHeight: 0
            ),
            8,
            accuracy: 0.000_001
        )
    }

    func testBounceContactAcrossRendererProfilesAndScales() {
        let profiles: [(distance: Double, radius: Double, stroke: Double)] = [
            (80, 6.4, 2.0),   // compact prototype contact
            (80, 8.2, 2.0),   // prototype at maximum visible height
            (72, 5.8, 1.45),  // production base frame
            (72, 7.2, 1.85)   // production strong-feedback frame
        ]
        let heights = [0.0, 0.01, 0.20, 0.46, 0.72, 0.99, 1.0]

        for scale in [0.5, 1.0, 2.0, 3.0] {
            for profile in profiles {
                let distance = profile.distance * scale
                let radius = profile.radius * scale
                let stroke = profile.stroke * scale
                let clearance = radius + stroke / 2

                for height in heights {
                    let offset = BeatBounceContactGeometry.inwardOffset(
                        edgeToCenterDistance: distance,
                        ballRadius: radius,
                        edgeStrokeWidth: stroke,
                        normalizedHeight: height
                    )
                    XCTAssertTrue(offset.isFinite)
                    XCTAssertGreaterThanOrEqual(offset, clearance - 0.000_001)
                    if height == 0 {
                        XCTAssertEqual(offset, clearance, accuracy: 0.000_001)
                    } else if height == 1 {
                        XCTAssertEqual(offset, distance, accuracy: 0.000_001)
                    }
                }
            }
        }
    }

    func testVisibleFeedbackFootprintCannotCrossTheEdge() {
        let ballRadius = 6.8
        let stroke = 1.85
        let centerOffset = BeatBounceContactGeometry.inwardOffset(
            edgeToCenterDistance: 72,
            ballRadius: ballRadius,
            edgeStrokeWidth: stroke,
            normalizedHeight: 0
        )
        let maximumEffectRadius = BeatBounceContactGeometry.maximumNonPenetratingRadius(
            inwardCenterOffset: centerOffset,
            edgeStrokeWidth: stroke
        )

        XCTAssertEqual(maximumEffectRadius, ballRadius, accuracy: 0.000_001)
        XCTAssertEqual(
            centerOffset - maximumEffectRadius,
            stroke / 2,
            accuracy: 0.000_001
        )
        XCTAssertLessThan(maximumEffectRadius, 10.6)
    }

    func testBounceCurveEndpointsResolveToTangentContact() {
        let distance = 80.0
        let radius = 7.0
        let stroke = 2.0
        let tiers: [BeatBounceHeightTier] = [
            .strong,
            .secondary,
            .main,
            .subdivision
        ]

        for tier in tiers {
            for progress in [0.0, 1.0] {
                let height = BeatBounceMotionModel.normalizedArcHeight(
                    eventProgress: progress,
                    tier: tier
                )
                let offset = BeatBounceContactGeometry.inwardOffset(
                    edgeToCenterDistance: distance,
                    ballRadius: radius,
                    edgeStrokeWidth: stroke,
                    normalizedHeight: height
                )
                XCTAssertEqual(offset, radius + stroke / 2, accuracy: 0.000_001)
            }
        }

        let descentContact = BeatBounceContactGeometry.inwardOffset(
            edgeToCenterDistance: distance,
            ballRadius: radius,
            edgeStrokeWidth: stroke,
            normalizedHeight: BeatBounceMotionModel.normalizedInitialDescentHeight(
                eventProgress: 1
            )
        )
        XCTAssertEqual(descentContact, radius + stroke / 2, accuracy: 0.000_001)

        let measureBoundaryContact = BeatBounceContactGeometry.inwardOffset(
            edgeToCenterDistance: distance,
            ballRadius: radius,
            edgeStrokeWidth: stroke,
            normalizedHeight: BeatBounceMotionModel.normalizedEventHeight(
                eventProgress: 1,
                toward: .strong,
                startsFromOrigin: false
            )
        )
        XCTAssertEqual(
            measureBoundaryContact,
            radius + stroke / 2,
            accuracy: 0.000_001
        )
    }

    func testPauseContinuationAdvancesToTheNextSubdivision() {
        var preset = MetronomePreset.standard
        preset.beats = 4
        preset.subdivision = 2
        let plan = preset.playbackPlan()

        let continuation = BeatPlaybackContinuation(
            afterBeat: 2,
            subdivision: 0,
            cycle: 7,
            plan: plan
        )

        XCTAssertEqual(continuation.eventIndex, 5)
        XCTAssertEqual(continuation.cycle, 7)
        var frontier = continuation.frontier
        let event = frontier.takeNext(plan: plan, sampleRate: 44_100)
        XCTAssertEqual(event.beat, 2)
        XCTAssertEqual(event.subdivision, 1)
        XCTAssertEqual(event.cycle, 7)
    }

    func testPauseContinuationWrapsOnlyAfterTheFinalEvent() {
        var preset = MetronomePreset.standard
        preset.beats = 4
        preset.subdivision = 2
        let plan = preset.playbackPlan()

        let continuation = BeatPlaybackContinuation(
            afterBeat: 3,
            subdivision: 1,
            cycle: 9,
            plan: plan
        )

        XCTAssertEqual(continuation.eventIndex, 0)
        XCTAssertEqual(continuation.cycle, 10)
        var frontier = continuation.frontier
        let event = frontier.takeNext(plan: plan, sampleRate: 44_100)
        XCTAssertEqual(event.beat, 0)
        XCTAssertEqual(event.subdivision, 0)
        XCTAssertEqual(event.cycle, 10)
    }

    func testBeatCountIsNormalizedAcrossSupportedPolygonRange() {
        XCTAssertEqual(BeatVisualLifecycle(beats: 1).beatCount, 3)
        XCTAssertEqual(BeatVisualLifecycle(beats: 3).beatCount, 3)
        XCTAssertEqual(BeatVisualLifecycle(beats: 9).beatCount, 9)
        XCTAssertEqual(BeatVisualLifecycle(beats: 24).beatCount, 9)
    }

    func testSubdivisionMovesBallButNeverBuildsAnEdge() throws {
        var lifecycle = BeatVisualLifecycle(beats: 4)
        lifecycle.resume()

        lifecycle.record(
            beat: 1,
            subdivision: 1,
            cycle: 0,
            beats: 4,
            pulsesPerBeat: 2
        )

        XCTAssertEqual(lifecycle.phase, .origin)
        XCTAssertEqual(lifecycle.builtEdgeCount, 0)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [])
        XCTAssertEqual(lifecycle.visibleBeatIndices, [])
        XCTAssertEqual(lifecycle.currentBeatIndex, 1)
        XCTAssertEqual(
            try XCTUnwrap(lifecycle.ballPhase),
            1.5,
            accuracy: 0.000_001
        )
        XCTAssertFalse(lifecycle.ballIsAtOrigin)
    }

    func testEachMainBeatRotatesExistingEdgesAndGeneratesAtHorizontalSlot() throws {
        var lifecycle = BeatVisualLifecycle(beats: 4)

        let start = try XCTUnwrap(lifecycle.record(
            beat: 0,
            subdivision: 0,
            cycle: 0,
            beats: 4
        ))
        XCTAssertEqual(start.kind, .measureStart)
        XCTAssertEqual(lifecycle.phase, .building)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [0])
        XCTAssertEqual(
            lifecycle.visibleEdgePlacements,
            [BeatVisualEdgePlacement(generationIndex: 0, slotIndex: 0)]
        )
        XCTAssertEqual(lifecycle.visibleBeatIndices, [0, 1])

        let second = try XCTUnwrap(lifecycle.record(
            beat: 1,
            subdivision: 0,
            cycle: 0,
            beats: 4
        ))
        XCTAssertEqual(second.kind, .beatAdvance)
        XCTAssertEqual(
            second.rotations,
            [BeatVisualEdgeRotation(
                generationIndex: 0,
                fromSlotIndex: 0,
                toSlotIndex: 1
            )]
        )
        XCTAssertEqual(
            second.insertedPlacements,
            [BeatVisualEdgePlacement(generationIndex: 1, slotIndex: 0)]
        )
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [1, 0])

        _ = lifecycle.record(beat: 2, subdivision: 0, cycle: 0, beats: 4)
        _ = lifecycle.record(beat: 3, subdivision: 0, cycle: 0, beats: 4)

        XCTAssertEqual(lifecycle.phase, .orbiting)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [3, 2, 1, 0])
        XCTAssertEqual(lifecycle.builtEdgeCount, 4)
        XCTAssertEqual(lifecycle.latestBuiltEdgeIndex, 0)
        XCTAssertTrue(lifecycle.hasEstablishedStructure)
    }

    func testAllSupportedPolygonsHaveNVisibleEdgesDuringBeatN() {
        for beats in 3...9 {
            var lifecycle = BeatVisualLifecycle(beats: beats)
            for beat in 0..<beats {
                lifecycle.record(
                    beat: beat,
                    subdivision: 0,
                    cycle: 0,
                    beats: beats
                )
                XCTAssertEqual(
                    lifecycle.builtEdgeCount,
                    beat + 1,
                    "Failed during beat \(beat + 1) of \(beats)"
                )
                XCTAssertEqual(
                    lifecycle.visibleEdgeIndices,
                    Array((0...beat).reversed())
                )
            }

            XCTAssertEqual(lifecycle.phase, .orbiting, "Failed for \(beats) beats")
            XCTAssertEqual(lifecycle.builtEdgeCount, beats)
            XCTAssertEqual(
                lifecycle.visibleEdgeIndices,
                Array((0..<beats).reversed())
            )
        }
    }

    func testNextCycleReplacesCompletePolygonWithOneHorizontalEdge() throws {
        var lifecycle = completedLifecycle(beats: 5)
        let previousRevision = lifecycle.geometryRevision

        let reset = try XCTUnwrap(lifecycle.record(
            beat: 0,
            subdivision: 0,
            cycle: 1,
            beats: 5,
            pulsesPerBeat: 4
        ))

        XCTAssertEqual(reset.kind, .measureReset)
        XCTAssertEqual(reset.previousPlacements.count, 5)
        XCTAssertEqual(
            reset.placements,
            [BeatVisualEdgePlacement(generationIndex: 0, slotIndex: 0)]
        )
        XCTAssertEqual(reset.rotations, [])
        XCTAssertEqual(reset.insertedPlacements, reset.placements)
        XCTAssertEqual(lifecycle.geometryRevision, previousRevision + 1)
        XCTAssertEqual(lifecycle.currentMeasureCycle, 1)
        XCTAssertEqual(lifecycle.phase, .building)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [0])
    }

    func testSubdivisionAtNewCycleClearsOldMeasureButNeverAddsAnEdge() throws {
        var lifecycle = completedLifecycle(beats: 4)
        let reset = try XCTUnwrap(lifecycle.record(
            beat: 0,
            subdivision: 1,
            cycle: 1,
            beats: 4,
            pulsesPerBeat: 4
        ))

        XCTAssertEqual(reset.kind, .measureReset)
        XCTAssertTrue(reset.placements.isEmpty)
        XCTAssertTrue(reset.insertedPlacements.isEmpty)
        XCTAssertEqual(lifecycle.phase, .origin)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [])
        XCTAssertEqual(lifecycle.currentBeatIndex, 0)
    }

    func testMissingMainBeatCallbackRecoversAddressDerivedGeometry() throws {
        var lifecycle = BeatVisualLifecycle(beats: 7)
        lifecycle.record(beat: 0, subdivision: 0, cycle: 4, beats: 7)

        let recovery = try XCTUnwrap(lifecycle.record(
            beat: 3,
            subdivision: 0,
            cycle: 4,
            beats: 7
        ))

        XCTAssertEqual(recovery.kind, .gapRecovery)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [3, 2, 1, 0])
        XCTAssertEqual(
            recovery.rotations,
            [BeatVisualEdgeRotation(
                generationIndex: 0,
                fromSlotIndex: 0,
                toSlotIndex: 3
            )]
        )
        XCTAssertEqual(
            recovery.insertedPlacements.map(\.generationIndex),
            [1, 2, 3]
        )
    }

    func testDuplicateAndLateCallbacksAreStrictlyIdempotent() {
        var lifecycle = BeatVisualLifecycle(beats: 4)
        lifecycle.record(beat: 0, subdivision: 0, cycle: 2, beats: 4)
        lifecycle.record(
            beat: 0,
            subdivision: 1,
            cycle: 2,
            beats: 4,
            pulsesPerBeat: 4
        )
        lifecycle.pause()
        let paused = lifecycle

        XCTAssertNil(lifecycle.record(
            beat: 0,
            subdivision: 1,
            cycle: 2,
            beats: 4,
            pulsesPerBeat: 4
        ))
        XCTAssertNil(lifecycle.record(
            beat: 0,
            subdivision: 0,
            cycle: 2,
            beats: 4,
            pulsesPerBeat: 4
        ))
        XCTAssertNil(lifecycle.record(
            beat: 3,
            subdivision: 0,
            cycle: 1,
            beats: 4,
            pulsesPerBeat: 4
        ))
        XCTAssertEqual(lifecycle, paused)
    }

    func testPauseFreezesGeometryBallAndCurrentBeat() {
        var lifecycle = BeatVisualLifecycle(beats: 5)
        lifecycle.record(beat: 0, subdivision: 0, cycle: 0, beats: 5)
        lifecycle.record(
            beat: 0,
            subdivision: 1,
            cycle: 0,
            beats: 5,
            pulsesPerBeat: 4
        )
        let beforePause = lifecycle

        lifecycle.pause()

        XCTAssertTrue(lifecycle.isPaused)
        XCTAssertEqual(lifecycle.phase, beforePause.phase)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, beforePause.visibleEdgeIndices)
        XCTAssertEqual(lifecycle.ballPhase, beforePause.ballPhase)
        XCTAssertEqual(lifecycle.currentBeatIndex, beforePause.currentBeatIndex)

        lifecycle.resume()
        XCTAssertFalse(lifecycle.isPaused)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, beforePause.visibleEdgeIndices)
    }

    func testSameTopologyRevisionDoesNotResetConstructionOrBall() {
        var lifecycle = BeatVisualLifecycle(beats: 7)
        lifecycle.record(beat: 3, subdivision: 0, cycle: 8, beats: 7)
        lifecycle.record(
            beat: 3,
            subdivision: 1,
            cycle: 8,
            beats: 7,
            pulsesPerBeat: 2
        )
        let beforeRevision = lifecycle

        // BPM is deliberately absent from this model. A tempo-only revision
        // therefore presents the same topology and is a strict no-op here.
        lifecycle.reconfigure(beats: 7)

        XCTAssertEqual(lifecycle, beforeRevision)
    }

    func testContinuousTempoChangesKeepMeasureAndEventAddressesContinuous() throws {
        var lifecycle = BeatVisualLifecycle(beats: 4)
        lifecycle.record(
            beat: 0,
            subdivision: 0,
            cycle: 12,
            beats: 4,
            pulsesPerBeat: 4
        )
        let firstRevision = lifecycle.geometryRevision

        for (subdivision, interval) in zip(1..<4, [0.30, 0.11, 0.42]) {
            lifecycle.reconfigure(beats: 4)
            lifecycle.record(
                beat: 0,
                subdivision: subdivision,
                cycle: 12,
                beats: 4,
                pulsesPerBeat: 4
            )
            let sample = try XCTUnwrap(BeatVisualMotionModel.sample(
                beat: 0,
                subdivision: subdivision,
                elapsed: interval / 2,
                eventInterval: interval,
                pulsesPerBeat: 4,
                eventsPerMeasure: 16,
                beats: 4
            ))
            XCTAssertEqual(sample.eventProgress, 0.5, accuracy: 0.000_001)
            XCTAssertEqual(lifecycle.geometryRevision, firstRevision)
            XCTAssertEqual(lifecycle.visibleEdgeIndices, [0])
        }

        lifecycle.record(
            beat: 1,
            subdivision: 0,
            cycle: 12,
            beats: 4,
            pulsesPerBeat: 4
        )
        XCTAssertEqual(lifecycle.currentMeasureCycle, 12)
        XCTAssertEqual(lifecycle.currentBeatIndex, 1)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [1, 0])
        XCTAssertEqual(lifecycle.geometryRevision, firstRevision + 1)
    }

    func testChangedTopologyStartsANewBuildLifecycleWithoutStoppingPlayback() {
        var lifecycle = BeatVisualLifecycle(beats: 4)
        lifecycle.record(beat: 0, subdivision: 0, cycle: 0, beats: 4)
        XCTAssertFalse(lifecycle.isPaused)

        lifecycle.reconfigure(beats: 7)

        XCTAssertEqual(lifecycle.phase, .origin)
        XCTAssertEqual(lifecycle.beatCount, 7)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [])
        XCTAssertNil(lifecycle.currentBeatIndex)
        XCTAssertNil(lifecycle.ballPhase)
        XCTAssertFalse(lifecycle.isPaused)
    }

    func testFinishReturnsBallBeforeReverseDismantling() throws {
        var lifecycle = completedLifecycle(beats: 4)
        lifecycle.record(
            beat: 3,
            subdivision: 1,
            cycle: 0,
            beats: 4,
            pulsesPerBeat: 2
        )

        lifecycle.beginFinishing()

        XCTAssertEqual(lifecycle.phase, .finishing)
        XCTAssertEqual(
            try XCTUnwrap(lifecycle.returnStartBallPhase),
            3.5,
            accuracy: 0.000_001
        )
        XCTAssertFalse(lifecycle.ballIsAtOrigin)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [3, 2, 1, 0])
        XCTAssertEqual(lifecycle.dismantlingOrder, [0, 1, 2, 3])
        XCTAssertNil(lifecycle.removeNextDismantlingEdge())

        lifecycle.completeCenterReturn()
        XCTAssertEqual(lifecycle.phase, .dismantling)
        XCTAssertTrue(lifecycle.ballIsAtOrigin)
        XCTAssertNil(lifecycle.ballPhase)
        XCTAssertEqual(lifecycle.nextEdgeToDismantle, 0)

        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 0)
        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 1)
        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 2)
        XCTAssertEqual(lifecycle.phase, .dismantling)
        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 3)

        XCTAssertEqual(lifecycle.phase, .settled)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [])
        XCTAssertTrue(lifecycle.ballIsAtOrigin)
    }

    func testStoppingDuringBuildDismantlesOnlyConstructedEdges() {
        var lifecycle = BeatVisualLifecycle(beats: 6)
        lifecycle.record(beat: 2, subdivision: 0, cycle: 4, beats: 6)
        lifecycle.record(beat: 3, subdivision: 0, cycle: 4, beats: 6)
        lifecycle.record(beat: 4, subdivision: 1, cycle: 4, beats: 6)
        XCTAssertEqual(lifecycle.visibleEdgeIndices, [3, 2, 1, 0])

        lifecycle.beginFinishing()
        XCTAssertEqual(lifecycle.dismantlingOrder, [0, 1, 2, 3])
        lifecycle.completeCenterReturn()

        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 0)
        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 1)
        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 2)
        XCTAssertEqual(lifecycle.removeNextDismantlingEdge(), 3)
        XCTAssertEqual(lifecycle.phase, .settled)
        XCTAssertNil(lifecycle.removeNextDismantlingEdge())
    }

    func testReducedMotionKeepsTheSameSemanticOutroStages() {
        var standard = completedLifecycle(beats: 3)
        var reducedMotion = standard

        // Presentation code may wait different durations before these calls;
        // neither path is allowed to skip the return-before-teardown contract.
        standard.beginFinishing()
        reducedMotion.beginFinishing()
        XCTAssertEqual(standard, reducedMotion)

        standard.completeCenterReturn()
        reducedMotion.completeCenterReturn()
        XCTAssertEqual(standard.phase, .dismantling)
        XCTAssertEqual(reducedMotion.phase, .dismantling)

        while standard.phase == .dismantling {
            XCTAssertEqual(
                standard.removeNextDismantlingEdge(),
                reducedMotion.removeNextDismantlingEdge()
            )
        }

        XCTAssertEqual(standard, reducedMotion)
        XCTAssertEqual(reducedMotion.phase, .settled)
    }

    func testGlanceStatusRemainsFinishingDuringDismantling() {
        var lifecycle = completedLifecycle(beats: 4)
        lifecycle.beginFinishing()
        lifecycle.completeCenterReturn()

        let status = MetronomeGlanceStatus(
            preset: .standard,
            hand: .both,
            lifecycle: lifecycle,
            isPlaying: false
        )

        XCTAssertEqual(status.state, .finishing)
    }

    private func completedLifecycle(beats: Int) -> BeatVisualLifecycle {
        var lifecycle = BeatVisualLifecycle(beats: beats)
        for beat in 0..<beats {
            lifecycle.record(
                beat: beat,
                subdivision: 0,
                cycle: 0,
                beats: beats
            )
        }
        return lifecycle
    }
}
