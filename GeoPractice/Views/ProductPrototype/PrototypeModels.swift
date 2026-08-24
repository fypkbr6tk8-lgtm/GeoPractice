import Foundation
import SwiftUI

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
                    .background(Color.black.opacity(0.14), in: shape)
                    .glassEffect(
                        .regular.tint(Color.white.opacity(emphasized ? 0.16 : 0.025)),
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

/// A control-specific Liquid Glass surface. Panels intentionally keep the
/// restrained `regular` treatment above; tappable controls use clear,
/// interactive glass so they retain the refraction and edge highlights of the
/// native Slider thumb instead of reading as opaque gray capsules.
struct PrototypeGlassControlModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(GeoTheme.panelRaised, in: shape)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.clear.interactive(), in: shape)
                    .overlay { prismaticBorder }
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
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .overlay { prismaticBorder }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Clear Liquid Glass needs a changing scene behind it to expose the
    /// system refraction. Navigation bars are deliberately quiet and dark, so
    /// add the same restrained cyan / amber / magenta fringe visible around a
    /// native Slider thumb. The neutral highlight remains dominant; this is a
    /// lens edge, not a decorative rainbow border.
    private var prismaticBorder: some View {
        shape
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: Color.cyan.opacity(0.52), location: 0.00),
                        .init(color: Color.white.opacity(0.30), location: 0.15),
                        .init(color: Color.white.opacity(0.12), location: 0.43),
                        .init(color: Color.yellow.opacity(0.38), location: 0.65),
                        .init(color: Color.pink.opacity(0.42), location: 0.83),
                        .init(color: Color.cyan.opacity(0.52), location: 1.00)
                    ],
                    center: .center,
                    startAngle: .degrees(-155),
                    endAngle: .degrees(205)
                ),
                lineWidth: 1.05
            )
            .blendMode(.plusLighter)
            .opacity(isEnabled ? 1 : 0.26)
            .allowsHitTesting(false)
    }
}

/// Toolbar controls need an exact, single geometry. On iOS 26 the toolbar can
/// otherwise add its own rounded plate outside this lens, producing a visible
/// rounded rectangle around a circular button.
struct PrototypeToolbarGlassLensModifier<LensShape: Shape>: ViewModifier {
    let shape: LensShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(GeoTheme.panelRaised, in: shape)
                .overlay {
                    shape
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(.clear.interactive(), in: shape)
                    .overlay { prismaticBorder }
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
            .overlay {
                shape
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .overlay { prismaticBorder }
    }

    private var prismaticBorder: some View {
        shape
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: Color.cyan.opacity(0.52), location: 0.00),
                        .init(color: Color.white.opacity(0.30), location: 0.15),
                        .init(color: Color.white.opacity(0.12), location: 0.43),
                        .init(color: Color.yellow.opacity(0.38), location: 0.65),
                        .init(color: Color.pink.opacity(0.42), location: 0.83),
                        .init(color: Color.cyan.opacity(0.52), location: 1.00)
                    ],
                    center: .center,
                    startAngle: .degrees(-155),
                    endAngle: .degrees(205)
                ),
                lineWidth: 1.05
            )
            .blendMode(.plusLighter)
            .opacity(isEnabled ? 1 : 0.26)
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

    /// Use on the visible label of Button, Menu and compact selectable
    /// controls. A very large radius produces a capsule/circle.
    func prototypeGlassControl(cornerRadius: CGFloat = 1_000) -> some View {
        modifier(PrototypeGlassControlModifier(cornerRadius: cornerRadius))
    }

    func prototypeToolbarGlassLens<LensShape: Shape>(
        in shape: LensShape
    ) -> some View {
        modifier(PrototypeToolbarGlassLensModifier(shape: shape))
    }

    /// Active items inside a shared glass control remain translucent. This
    /// replaces the old opaque white selection pills while keeping selection
    /// unmistakable through a second, brighter lens edge.
    @ViewBuilder
    func prototypeGlassSelection(
        _ isSelected: Bool,
        cornerRadius: CGFloat = 1_000
    ) -> some View {
        if isSelected {
            background {
                Color.white.opacity(0.055)
                    .prototypeGlassControl(cornerRadius: cornerRadius)
            }
        } else {
            self
        }
    }

    /// iOS 26 needs real content behind clear glass to expose refraction.
    /// Older systems retain the explicit dark material used by the prototype.
    @ViewBuilder
    func prototypeNavigationBarGlassBackground() -> some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            toolbarBackground(.hidden, for: .navigationBar)
        } else {
            toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
#else
        toolbarBackground(GeoTheme.background.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
    }
}

/// Consistent, single-surface labels for navigation-bar actions. The glass is
/// part of the label and the Button itself stays plain, so iOS cannot add a
/// second toolbar plate outside a differently shaped glass lens.
struct PrototypeToolbarIconLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(GeoTheme.text)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .prototypeToolbarGlassLens(in: Circle())
    }
}

struct PrototypeToolbarTextLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GeoTheme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .prototypeToolbarGlassLens(in: Capsule())
    }
}

struct PrototypeGlassControl<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(
        cornerRadius: CGFloat = 1_000,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content.prototypeGlassControl(cornerRadius: cornerRadius)
    }
}

struct PrototypeGlassPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

extension ToolbarContent {
    /// iOS 26 automatically groups toolbar items onto a shared glass plate.
    /// These prototype controls already provide their own exact Circle or
    /// Capsule lens, so the system plate must be hidden to avoid two shapes.
    @ToolbarContentBuilder
    func prototypeHidesSharedToolbarBackground() -> some ToolbarContent {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
#else
        self
#endif
    }
}

struct PrototypeGlassSegmentButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isActive ? GeoTheme.text : GeoTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 5)
                .prototypeGlassSelection(isActive, cornerRadius: 10)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
