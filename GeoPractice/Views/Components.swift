import Foundation
import ObjectiveC
import SwiftUI
import UIKit

enum GeoTheme {
    static let background = adaptive(light: .white, dark: .black)
    static let backgroundEnd = background
    static let panel = adaptive(
        light: UIColor(white: 0.955, alpha: 1),
        dark: UIColor(white: 0.065, alpha: 1)
    )
    static let panelRaised = adaptive(
        light: UIColor(white: 0.91, alpha: 1),
        dark: UIColor(white: 0.10, alpha: 1)
    )
    static let line = adaptive(
        light: UIColor(white: 0.78, alpha: 1),
        dark: UIColor(white: 0.22, alpha: 1)
    )
    static let text = adaptive(
        light: UIColor(white: 0.03, alpha: 1),
        dark: UIColor(white: 0.97, alpha: 1)
    )
    static let muted = adaptive(
        light: UIColor(white: 0.42, alpha: 1),
        dark: UIColor(white: 0.54, alpha: 1)
    )
    /// A foreground-colored neutral used for strokes and restrained glass tint.
    static let surfaceInk = text
    /// Blue is reserved for binary on/off controls.
    static let controlAccent = Color(red: 0, green: 122.0 / 255.0, blue: 1)
    /// Selection controls keep the original neutral high-contrast treatment.
    static let selectionFill = Color.white.opacity(0.92)
    static let selectionText = Color.black
    /// Navigation alone inverts its selected background in the light theme.
    static let navigationSelectionFill = adaptive(
        light: UIColor.black.withAlphaComponent(0.92),
        dark: UIColor.white.withAlphaComponent(0.92)
    )
    /// The floating navigation keeps its selected label blue in both themes.
    static let navigationSelectionText = controlAccent

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? light : dark
        })
    }
}

struct GeoBackground: View {
    var body: some View {
        GeoTheme.background
            .ignoresSafeArea()
    }
}

struct GeoCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .geoCardSurface(cornerRadius: cornerRadius)
    }
}

/// The exact material selected as “variant 7” in the glass lab.
///
/// Keep this recipe deliberately free of tint, gradients and decorative
/// strokes. Those extra layers were the reason the later experiment no
/// longer matched the texture that was approved in the comparison screen.
@available(iOS 26.0, *)
private struct GeoVariant7CardBackground: UIViewRepresentable {
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: makeEffect())
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        view.layer.cornerRadius = cornerRadius
        if view.effect == nil {
            view.effect = makeEffect()
        }
    }

    private func makeEffect() -> UIVisualEffect {
        makeGeoVariant7Effect() ?? UIBlurEffect(style: .systemUltraThinMaterial)
    }
}

@available(iOS 26.0, *)
private func makeGeoVariant7Effect() -> UIVisualEffect? {
    guard let glassClass = NSClassFromString("_UIViewGlass") as? NSObject.Type else {
        return nil
    }

    let initializer = NSSelectorFromString("initWithVariant:size:smoothness:subdued:")
    guard let method = class_getInstanceMethod(glassClass, initializer) else {
        return nil
    }

    typealias GlassInitializer = @convention(c) (
        AnyObject,
        Selector,
        Int,
        Int,
        Double,
        Bool
    ) -> Unmanaged<AnyObject>?

    let implementation = method_getImplementation(method)
    let initialize = unsafeBitCast(implementation, to: GlassInitializer.self)
    guard let allocated = (glassClass as AnyObject)
        .perform(NSSelectorFromString("alloc"))?
        .takeUnretainedValue(),
          let glass = initialize(
              allocated,
              initializer,
              7,
              0,
              0,
              false
          )?.takeUnretainedValue() as? NSObject else {
        return nil
    }

    glass.setValue(true, forKey: "contentLensing")
    glass.setValue(false, forKey: "excludingControlLensing")
    glass.setValue(false, forKey: "excludingControlDisplacement")
    glass.setValue(true, forKey: "flexible")

    let effectFactory = NSSelectorFromString("effectWithGlass:")
    guard (UIGlassEffect.self as AnyObject).responds(to: effectFactory) else {
        return nil
    }
    return (UIGlassEffect.self as AnyObject)
        .perform(effectFactory, with: glass)?
        .takeUnretainedValue() as? UIVisualEffect
}

private struct GeoCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    GeoTheme.panelRaised,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
#if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content
                    .background {
                        GeoVariant7CardBackground(cornerRadius: cornerRadius)
                            .allowsHitTesting(false)
                    }
                    .shadow(
                        color: .black.opacity(colorScheme == .light ? 0.075 : 0.22),
                        radius: colorScheme == .light ? 14 : 24,
                        y: colorScheme == .light ? 7 : 14
                    )
            } else {
                materialCard(content)
            }
#else
            materialCard(content)
#endif
        }
    }

    private func materialCard(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(.ultraThinMaterial, in: shape)
            .background(GeoTheme.background.opacity(0.12), in: shape)
    }
}

extension View {
    /// Applies the shared card-only surface. Controls intentionally use their
    /// own glass styles so a button never creates a second nested card layer.
    func geoCardSurface(cornerRadius: CGFloat = 22) -> some View {
        modifier(GeoCardSurfaceModifier(cornerRadius: cornerRadius))
    }
}

/// A restrained glass capsule that uses the current Liquid Glass rendering on
/// new systems and an iOS 17 Material fallback. The fallback is intentionally
/// translucent: the dark shapes in the V4 sketch describe glass, not black ink.
struct GeoGlassCapsule<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if reduceTransparency {
                content
                    .background(GeoTheme.panelRaised, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(GeoTheme.surfaceInk.opacity(0.20), lineWidth: 1)
                    }
            } else {
                translucentGlass
            }
        }
        .shadow(
            color: .black.opacity(colorScheme == .light ? 0.08 : 0.22),
            radius: colorScheme == .light ? 11 : 18,
            y: colorScheme == .light ? 5 : 10
        )
    }

    /// Older Swift compilers do not expose Liquid Glass symbols, so they
    /// compile only the Material implementation.
    @ViewBuilder
    private var translucentGlass: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular
                        .tint(GeoTheme.surfaceInk.opacity(0.035))
                        .interactive(),
                    in: Capsule(style: .continuous)
                )
        } else {
            materialGlass
        }
#else
        materialGlass
#endif
    }

    private var materialGlass: some View {
        content
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [GeoTheme.surfaceInk.opacity(0.10), GeoTheme.surfaceInk.opacity(0.025)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [GeoTheme.surfaceInk.opacity(0.28), GeoTheme.surfaceInk.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

/// A toolbar icon label that leaves iOS 26's native toolbar glass as the only
/// rendered surface. Applying `GeoGlassCapsule` inside a toolbar button creates
/// a second glass layer, which is especially visible in the light appearance as
/// square highlights, doubled rims and an oversized shadow. Older systems still
/// receive the existing material fallback because they do not provide native
/// Liquid Glass toolbar backgrounds.
struct GeoToolbarIconLabel: View {
    let symbol: String
    var size: CGFloat = 44

    @ViewBuilder
    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            icon
        } else {
            legacyGlassIcon
        }
#else
        legacyGlassIcon
#endif
    }

    private var icon: some View {
        Image(systemName: symbol)
            .frame(width: size, height: size)
    }

    private var legacyGlassIcon: some View {
        GeoGlassCapsule {
            icon
        }
    }
}

struct CardTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
                .foregroundStyle(GeoTheme.text.opacity(0.88))
            Spacer()
            Text(subtitle)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(GeoTheme.muted)
        }
    }
}

struct ControlLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(GeoTheme.muted)
            Spacer()
            Text(value)
                .fontWeight(.bold)
                .foregroundStyle(GeoTheme.text)
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// A compact SMuFL note value. Bravura Text's augmentation dot is intentionally
/// tiny at selector sizes, so it is kept as a real SMuFL glyph but rendered at
/// a larger size and with explicit spacing from the note.
struct SMuFLNoteGlyph: View {
    let note: TempoReferenceNote
    var size: CGFloat = 28

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: note.isDotted ? 1.5 : 0) {
            Text(note.undottedNote.symbol)
                .font(.custom("BravuraText", fixedSize: size))

            if note.isDotted {
                Text(TempoReferenceNote.augmentationDotSymbol)
                    .font(.custom("BravuraText", fixedSize: size * 1.29))
            }
        }
        .fixedSize()
    }
}

/// A number-first tempo control. The selected primary axis maps to exact BPM
/// steps; the model is committed only when the gesture ends, so a playing
/// metronome is rescheduled once instead of on every drag sample.
struct TempoScrubber: View {
    let bpm: Int
    var compact = false
    var direction: TempoScrubDirection = .horizontal
    var onTap: (() -> Void)?
    var onScrubbingChanged: (Bool) -> Void = { _ in }
    let onCommit: (Int) -> Void

    @State private var draftBPM: Int?
    @State private var dragStartBPM: Int?
    @State private var isScrubbing = false
    @State private var didDrag = false
    @State private var isWaitingForSecondTap = false
    @State private var pendingSingleTapTask: Task<Void, Never>?
    @State private var isShowingDirectEntry = false
    @State private var directEntryText = ""

    private var displayedBPM: Int {
        draftBPM ?? bpm
    }

    private var displayedTempoName: String {
        var preset = MetronomePreset.standard
        preset.bpm = displayedBPM
        return preset.tempoName
    }

    var body: some View {
        Group {
            if compact {
                VStack(spacing: 0) {
                    Text("BPM · \(displayedTempoName)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    scrubTarget(compact: true)
                }
            } else {
                VStack(spacing: 8) {
                    Text(displayedTempoName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(GeoTheme.muted)
                    scrubTarget(compact: false)
                    Text("\(direction.detail) · 双击直接输入")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GeoTheme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 128)
                .background(
                    GeoTheme.panel,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            GeoTheme.surfaceInk.opacity(draftBPM == nil ? 0.08 : 0.26),
                            lineWidth: 1
                        )
                }
            }
        }
        .onDisappear {
            cancelPendingTap()
            cancelDraft()
            isShowingDirectEntry = false
        }
        .alert("输入 BPM", isPresented: $isShowingDirectEntry) {
            TextField("当前 \(bpm)", text: $directEntryText)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) {}
            Button("确定") {
                commitDirectEntry()
            }
            .disabled(validatedDirectEntry == nil)
        } message: {
            Text("请输入 30 至 240 之间的整数。确认后速度只更新一次。")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("速度")
        .accessibilityValue("\(displayedTempoName)，\(displayedBPM) BPM")
        .accessibilityHint("\(direction.accessibilityHint)；VoiceOver 上下轻扫每次调整 1 BPM")
        .accessibilityAction(named: "直接输入 BPM") {
            beginDirectEntry()
        }
        .accessibilityAdjustableAction { direction in
            let delta: Int
            switch direction {
            case .increment: delta = 1
            case .decrement: delta = -1
            @unknown default: return
            }
            let next = clamped(bpm + delta)
            if next != bpm { onCommit(next) }
        }
    }

    private func scrubTarget(compact: Bool) -> some View {
        HStack(spacing: compact ? 2 : 8) {
            tempoStepButton(delta: -1, compact: compact)

            Text("\(displayedBPM)")
                .font(.system(
                    size: compact ? 23 : 58,
                    weight: .bold,
                    design: .rounded
                ))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: compact ? 48 : 96, minHeight: compact ? 44 : 76)
                .contentShape(Rectangle())
                .highPriorityGesture(scrubGesture)

            tempoStepButton(delta: 1, compact: compact)
        }
        .foregroundStyle(GeoTheme.text)
        .frame(minWidth: compact ? 116 : 220, minHeight: compact ? 42 : 76)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if draftBPM != nil {
                Capsule()
                    .fill(GeoTheme.surfaceInk.opacity(0.62))
                    .frame(width: compact ? 26 : 48, height: 1.5)
            }
        }
    }

    private func tempoStepButton(delta: Int, compact: Bool) -> some View {
        let isAvailable = delta < 0
            ? displayedBPM > TempoScrubModel.minimumBPM
            : displayedBPM < TempoScrubModel.maximumBPM

        return Button {
            nudge(by: delta)
        } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: compact ? 10 : 15, weight: .bold))
                .frame(width: compact ? 28 : 44)
                .frame(minHeight: compact ? 44 : 76)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 0.72 : 0.16)
        .disabled(!isAvailable)
        .accessibilityLabel(delta < 0 ? "速度减一" : "速度加一")
    }

    private var scrubGesture: some Gesture {
        // A zero-distance high-priority gesture reserves only the number area
        // from touch-down. The editor can therefore disable its Form before
        // the parent scroll view consumes the first few points of a BPM drag;
        // beginning a scroll anywhere outside the number remains unchanged.
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                setScrubbing(true)
                let travelled = hypot(
                    value.translation.width,
                    value.translation.height
                )
                guard travelled >= 4 else { return }

                didDrag = true
                if dragStartBPM == nil {
                    dragStartBPM = bpm
                    draftBPM = bpm
                }
                guard let dragStartBPM else { return }
                let primaryTranslation = direction.primaryTranslation(
                    horizontal: value.translation.width,
                    vertical: value.translation.height
                )
                draftBPM = TempoScrubModel.bpm(
                    start: dragStartBPM,
                    primaryTranslation: Double(primaryTranslation)
                )
            }
            .onEnded { _ in
                let completedDrag = didDrag
                let committed = draftBPM
                cancelDraft()
                if completedDrag, let committed, committed != bpm {
                    onCommit(committed)
                } else if !completedDrag {
                    registerTap()
                }
            }
    }

    private func registerTap() {
        if isWaitingForSecondTap {
            cancelPendingTap()
            beginDirectEntry()
            return
        }

        isWaitingForSecondTap = true
        pendingSingleTapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            isWaitingForSecondTap = false
            pendingSingleTapTask = nil
            onTap?()
        }
    }

    private func cancelPendingTap() {
        pendingSingleTapTask?.cancel()
        pendingSingleTapTask = nil
        isWaitingForSecondTap = false
    }

    private var validatedDirectEntry: Int? {
        TempoScrubModel.validatedBPMInput(directEntryText)
    }

    private func beginDirectEntry() {
        cancelPendingTap()
        cancelDraft()
        directEntryText = ""
        isShowingDirectEntry = true
    }

    private func commitDirectEntry() {
        guard let enteredBPM = validatedDirectEntry else { return }
        if enteredBPM != bpm {
            onCommit(enteredBPM)
        }
    }

    private func nudge(by delta: Int) {
        cancelDraft()
        let next = clamped(bpm + delta)
        if next != bpm {
            onCommit(next)
        }
    }

    private func clamped(_ value: Int) -> Int {
        min(TempoScrubModel.maximumBPM, max(TempoScrubModel.minimumBPM, value))
    }

    private func cancelDraft() {
        draftBPM = nil
        dragStartBPM = nil
        didDrag = false
        setScrubbing(false)
    }

    private func setScrubbing(_ active: Bool) {
        guard active != isScrubbing else { return }
        isScrubbing = active
        onScrubbingChanged(active)
    }
}
struct GeoSegmentButton: View {
    let title: String
    var symbol: String?
    let isActive: Bool
    var activeForeground: Color? = nil
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(
                isActive ? (activeForeground ?? GeoTheme.text) : GeoTheme.muted
            )
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 5)
            .background { if isActive { activeBackground } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var activeBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
#if compiler(>=6.2)
        if #available(iOS 26.0, *), !reduceTransparency {
            // No shared glassEffectID / GlassEffectContainer here: stacking a
            // morphing glass shape per segment corrupted rendering (the active
            // label went fully opaque and unreadable). A plain per-button
            // glass tint still reads as "liquid glass on selection" without
            // the cross-item morph animation.
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(GeoTheme.surfaceInk.opacity(0.05)), in: shape)
        } else {
            legacyBackground(shape)
        }
#else
        legacyBackground(shape)
#endif
    }

    private func legacyBackground(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(GeoTheme.panelRaised)
            .overlay {
                shape.stroke(GeoTheme.surfaceInk.opacity(0.07), lineWidth: 1)
            }
    }
}

struct GeoSegmentContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) {
            content
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GeoTheme.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(GeoTheme.surfaceInk.opacity(0.06), lineWidth: 1)
                }
        )
    }
}

struct CountBadge: View {
    let title: String
    let count: Int

    var body: some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(GeoTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .geoCardSurface(cornerRadius: 11)
        .foregroundStyle(GeoTheme.text)
    }
}

struct PresetSummary: View {
    let preset: MetronomePreset

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "metronome")
            Text(preset.compactSummary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(GeoTheme.muted)
    }
}

func practiceDurationString(milliseconds: Int64) -> String {
    let totalSeconds = max(0, milliseconds) / 1_000
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%02lld:%02lld:%02lld", hours, minutes, seconds)
    }
    return String(format: "%02lld:%02lld", minutes, seconds)
}
