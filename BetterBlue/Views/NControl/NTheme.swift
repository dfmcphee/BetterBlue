//
//  NTheme.swift
//  N Link
//
//  Design tokens and shared building blocks for the N Link
//  "telemetry" design: near-black ground, graphite cards, condensed
//  numerals and a single Luminous Orange accent.
//

import SwiftUI
import UIKit

enum NTheme {
    static let ground = Color(hex: 0x050505)
    static let card = Color(hex: 0x111111)
    static let cardRaised = Color(hex: 0x191919)
    static let track = Color(hex: 0x1A1A1A)
    static let hairline = Color(hex: 0x1F1F1F)
    static let border = Color(hex: 0x262626)
    static let borderStrong = Color(hex: 0x333333)
    static let text = Color(hex: 0xF2F2F2)
    static let textSecondary = Color(hex: 0xA3A3A3)
    /// Luminous Orange — the IONIQ 5 N highlight.
    static let accent = Color(hex: 0xEA4A2A)
    static let onAccent = Color(hex: 0x0A0A0A)
    static let warning = Color(hex: 0xF2B33D)

    /// Room between a screen's content and the status bar above it.
    static let screenTop: CGFloat = 16
    /// Room between a screen's content and the sides of the display.
    static let screenHorizontal: CGFloat = 24

    /// The Car (home) screen sits further in than the others: its big
    /// vehicle name and gauge want more air around them.
    static let homeTop: CGFloat = 32
    static let homeHorizontal: CGFloat = 28
    /// Room between a screen's content and the tab bar (or the bottom of
    /// the screen) below it.
    static let screenBottom: CGFloat = 24

    /// Condensed display numerals (stand-in for Barlow Condensed).
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Small tracked caps label, e.g. "STATE OF CHARGE".
    static let label = Font.system(size: 11, weight: .semibold)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Surfaces

struct NCard: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func nCard(radius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(NCard(radius: radius, padding: padding))
    }
}

struct NCapsLabel: View {
    let text: String
    var color: Color = NTheme.textSecondary
    init(_ text: String, color: Color = NTheme.textSecondary) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(NTheme.label)
            .tracking(1)
            .foregroundStyle(color)
    }
}

// MARK: - Buttons

struct NButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    var height: CGFloat = 50
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 12)
            .foregroundStyle(kind == .primary ? NTheme.onAccent : NTheme.text)
            .background(
                kind == .primary ? NTheme.accent : NTheme.cardRaised,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(NTheme.borderStrong, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NButtonStyle {
    static var nPrimary: NButtonStyle { NButtonStyle(kind: .primary) }
    static var nSecondary: NButtonStyle { NButtonStyle(kind: .secondary) }
}

/// Command button that swaps its title for a spinner + status text
/// while the command is running.
struct NCommandButton: View {
    let title: String
    var systemImage: String?
    var kind: NButtonStyle.Kind = .primary
    var height: CGFloat = 50
    let isBusy: Bool
    var busyText: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(kind == .primary ? NTheme.onAccent : NTheme.text)
                    Text(busyText ?? "Working")
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
            }
        }
        .buttonStyle(NButtonStyle(kind: kind, height: height))
        .disabled(isBusy)
    }
}

/// Round 44pt icon button used for back / refresh / locate.
struct NIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().controlSize(.small).tint(NTheme.text)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(NTheme.text)
            .background(NTheme.card, in: Circle())
            .overlay(Circle().strokeBorder(NTheme.border, lineWidth: 1))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(isBusy)
    }
}

// MARK: - Screen header for pushed screens

struct NScreenHeader: View {
    let title: String
    var subtitle: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nEmbeddedPane) private var isEmbeddedPane

    var body: some View {
        HStack(spacing: 12) {
            if !isEmbeddedPane {
                NIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(NTheme.display(26))
                    .foregroundStyle(NTheme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(NTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Wraps a pushed screen: ground colour, scroll, custom header, and no
/// system navigation bar (swipe-back still works).
struct NPushedScreen<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NScreenHeader(title: title, subtitle: subtitle)
                content()
            }
            .padding(.horizontal, NTheme.screenHorizontal)
            .padding(.top, NTheme.screenTop)
            .padding(.bottom, NTheme.screenBottom + 8)
        }
        .scrollIndicators(.hidden)
        .background(NTheme.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
    }
}

// MARK: - Gauges

/// Segmented arc gauge: a 270° track with a filled portion, tick
/// gaps, and an optional limit marker.
struct NArcGauge: View {
    /// 0...1
    let value: Double
    /// 0...1, drawn as a short white tick across the track.
    var marker: Double?
    var lineWidth: CGFloat = 16
    var sweep: Double = 270
    var segments: Int = 50
    var color: Color = NTheme.accent

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let fraction = sweep / 360
            let start = Angle.degrees(90 + (360 - sweep) / 2)
            ZStack {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(NTheme.track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                Circle()
                    .trim(from: 0, to: fraction * min(max(value, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                // Tick gaps cut through track + fill.
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        NTheme.ground,
                        style: StrokeStyle(
                            lineWidth: lineWidth + 2,
                            dash: tickDash(size: size, fraction: fraction)
                        )
                    )
                if let marker {
                    Capsule()
                        .fill(NTheme.text)
                        .frame(width: 3, height: lineWidth + 10)
                        .offset(y: -(size - lineWidth) / 2)
                        .rotationEffect(.degrees(90) + .degrees(sweep * min(max(marker, 0), 1)))
                        .accessibilityHidden(true)
                }
            }
            .rotationEffect(start)
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tickDash(size: CGFloat, fraction: Double) -> [CGFloat] {
        let circumference = .pi * (size - lineWidth)
        let segmentLength = circumference * fraction / Double(segments)
        return [2.5, max(segmentLength - 2.5, 1)]
    }
}

/// Horizontal block bar (charge level) with an optional limit tick.
struct NBlockBar: View {
    let value: Double
    var limit: Double?
    var blocks: Int = 20
    var height: CGFloat = 34
    var color: Color = NTheme.accent

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let width = (geo.size.width - spacing * CGFloat(blocks - 1)) / CGFloat(blocks)
            let filled = Int((value * Double(blocks)).rounded())
            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(0..<blocks, id: \.self) { index in
                        Rectangle()
                            .fill(index < filled ? color : NTheme.track)
                            .frame(width: width)
                    }
                }
                if let limit {
                    Rectangle()
                        .fill(NTheme.text)
                        .frame(width: 3, height: height + 10)
                        .offset(x: geo.size.width * limit - 1.5)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 10)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

struct NRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var showsDivider = true
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15))
                        .foregroundStyle(NTheme.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(NTheme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                trailing()
                    .font(.system(size: 14))
                    .foregroundStyle(NTheme.textSecondary)
            }
            .frame(minHeight: 50)
            .padding(.horizontal, 14)
            if showsDivider {
                Rectangle().fill(NTheme.hairline).frame(height: 1)
            }
        }
    }
}

extension NRow where Trailing == Text {
    init(_ title: String, value: String, subtitle: String? = nil, showsDivider: Bool = true) {
        self.init(title: title, subtitle: subtitle, showsDivider: showsDivider) { Text(value) }
    }
}

struct NGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .background(NTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Square-ish toggle in the N style.
struct NToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(configuration.isOn ? NTheme.accent : NTheme.track)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(configuration.isOn ? .clear : NTheme.borderStrong)
                        )
                        .frame(width: 48, height: 28)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(configuration.isOn ? NTheme.onAccent : NTheme.textSecondary)
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
                .animation(.snappy(duration: 0.18), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Selectable chip used for durations and presets.
struct NChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 10)
                .foregroundStyle(isSelected ? NTheme.onAccent : NTheme.text)
                .background(
                    isSelected ? NTheme.accent : NTheme.card,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? .clear : NTheme.border)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Swipe back with hidden nav bar

private struct EnableSwipeBack: ViewModifier {
    func body(content: Content) -> some View {
        content.background(SwipeBackEnabler())
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Controller() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

extension View {
    func enableSwipeBack() -> some View { modifier(EnableSwipeBack()) }
}
