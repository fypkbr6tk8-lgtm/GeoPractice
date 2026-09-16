import XCTest
@testable import GeoPractice

final class SubscriptionStoreTests: XCTestCase {
    private let productID = SubscriptionProductCatalog.monthlyProductID
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidSupportedSubscriptionGrantsAccess() {
        XCTAssertTrue(
            grantsAccess(
                snapshot(
                    expirationDate: now.addingTimeInterval(60)
                )
            )
        )
    }

    func testLifetimeEntitlementForSupportedProductGrantsAccess() {
        XCTAssertTrue(grantsAccess(snapshot(expirationDate: nil)))
    }

    func testExpiredSubscriptionDoesNotGrantAccess() {
        XCTAssertFalse(
            grantsAccess(
                snapshot(
                    expirationDate: now.addingTimeInterval(-1)
                )
            )
        )
    }

    func testRevokedSubscriptionDoesNotGrantAccess() {
        XCTAssertFalse(
            grantsAccess(
                snapshot(
                    expirationDate: now.addingTimeInterval(60),
                    revocationDate: now
                )
            )
        )
    }

    func testUpgradedSubscriptionDoesNotGrantAccess() {
        XCTAssertFalse(
            grantsAccess(
                snapshot(
                    expirationDate: now.addingTimeInterval(60),
                    isUpgraded: true
                )
            )
        )
    }

    func testUnrelatedProductDoesNotGrantAccess() {
        XCTAssertFalse(
            grantsAccess(
                snapshot(
                    productID: "com.example.unrelated",
                    expirationDate: now.addingTimeInterval(60)
                )
            )
        )
    }

    func testAnyValidSupportedEntitlementGrantsAccess() {
        let expired = snapshot(expirationDate: now.addingTimeInterval(-60))
        let valid = snapshot(expirationDate: now.addingTimeInterval(60))

        XCTAssertTrue(
            SubscriptionEntitlementResolver.grantsAccess(
                snapshots: [expired, valid],
                supportedProductIDs: SubscriptionProductCatalog.supportedProductIDs,
                now: now
            )
        )
    }

    func testConfiguredYearlySubscriptionAlsoGrantsAccess() {
        XCTAssertTrue(
            grantsAccess(
                snapshot(
                    productID: SubscriptionProductCatalog.yearlyProductID,
                    expirationDate: now.addingTimeInterval(60)
                )
            )
        )
    }

    @MainActor
    func testLockedReferenceNoteUsesQuarterNoteWithoutDestroyingSavedChoice() {
        var preset = MetronomePreset.standard
        preset.referenceNote = .half
        let engine = MetronomeEngine(preset: preset)

        engine.setPremiumReferenceNoteAccess(false)

        XCTAssertEqual(engine.preset.referenceNote, .half)
        XCTAssertEqual(engine.playbackPlan.referenceNote, .quarter)
        XCTAssertEqual(engine.effectivePlaybackPreset.referenceNote, .quarter)
    }

    @MainActor
    func testRestoringReferenceNoteAccessReappliesSavedChoice() {
        var preset = MetronomePreset.standard
        preset.referenceNote = .eighth
        let engine = MetronomeEngine(preset: preset)
        engine.setPremiumReferenceNoteAccess(false)

        engine.setPremiumReferenceNoteAccess(true)

        XCTAssertEqual(engine.preset.referenceNote, .eighth)
        XCTAssertEqual(engine.playbackPlan.referenceNote, .eighth)
        XCTAssertEqual(engine.effectivePlaybackPreset.referenceNote, .eighth)
    }

    private func grantsAccess(_ snapshot: SubscriptionEntitlementSnapshot) -> Bool {
        SubscriptionEntitlementResolver.grantsAccess(
            snapshots: [snapshot],
            supportedProductIDs: SubscriptionProductCatalog.supportedProductIDs,
            now: now
        )
    }

    private func snapshot(
        productID: String? = nil,
        expirationDate: Date?,
        revocationDate: Date? = nil,
        isUpgraded: Bool = false
    ) -> SubscriptionEntitlementSnapshot {
        SubscriptionEntitlementSnapshot(
            productID: productID ?? self.productID,
            expirationDate: expirationDate,
            revocationDate: revocationDate,
            isUpgraded: isUpgraded
        )
    }
}
