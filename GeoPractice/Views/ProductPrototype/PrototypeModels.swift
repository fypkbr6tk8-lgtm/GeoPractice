import Foundation
import SwiftUI
import UIKit

/// Real Liquid Glass panel background built from an explicitly-constructed
/// `_UIViewGlass` at variant 13 — found by enumerating `_UIViewGlass` via the
/// Objective-C runtime and sweeping its `variant` values in
/// ExperimentalGlassLab (see PrototypeStatisticsSettingsViews.swift). Public
/// `.glassEffect(.regular)` only produces flat blur+tint (confirmed against
/// a striped test backdrop — no edge refraction); this explicit-glass path
/// is what actually reads as "liquid" rather than "frosted". Falls back to a
/// plain effect-less view (fully transparent) if these private symbols ever
/// disappear in a future OS — safe because callers already layer their own
/// background/overlay/border on top.
@available(iOS 26.0, *)
private struct PrototypeGlassPanelBackground: UIViewRepresentable {
    let cornerRadius: CGFloat
    let tint: UIColor?

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: buildEffect())
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.effect = buildEffect()
        view.layer.cornerRadius = cornerRadius
    }

    private func buildEffect() -> UIVisualEffect? {
        guard let glassObj = makeViewGlass(variant: 13, size: 0, smoothness: 0, subdued: false) else {
            return nil
        }
        glassObj.setValue(true, forKey: "contentLensing")
        glassObj.setValue(false, forKey: "excludingControlLensing")
        glassObj.setValue(false, forKey: "excludingControlDisplacement")
        glassObj.setValue(true, forKey: "flexible")
        if let tint {
            glassObj.setValue(tint, forKey: "tintColor")
        }

        let sel = NSSelectorFromString("effectWithGlass:")
        guard (UIGlassEffect.self as AnyObject).responds(to: sel) else { return nil }
        return (UIGlassEffect.self as AnyObject).perform(sel, with: glassObj)?
            .takeUnretainedValue() as? UIVisualEffect
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
                    emphasized ? Color(white: 0.13) : GeoTheme.panelRaised,
                    in: shape
                )
                .overlay { border }
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content
                    .background {
                        PrototypeGlassPanelBackground(
                            cornerRadius: cornerRadius,
                            tint: UIColor.white.withAlphaComponent(emphasized ? 0.10 : 0.035)
                        )
                    }
                    .overlay {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(emphasized ? 0.20 : 0.10),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .allowsHitTesting(false)
                    }
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
                    .fill(Color.black.opacity(emphasized ? 0.02 : 0.14))
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(emphasized ? 0.20 : 0.09),
                                Color.white.opacity(0.015)
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
            .stroke(Color.white.opacity(emphasized ? 0.28 : 0.15), lineWidth: 1)
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
