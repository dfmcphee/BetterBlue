//
//  NLinkSmallWidget.swift
//  Widget
//
//  The small Home Screen widget: name, range and charge above a grid of
//  controls, on a dark surface. Orange marks the control that matters
//  right now (unlocked car, climate or charge running).
//

import AppIntents
import SwiftUI
import WidgetKit

private enum NLinkWidgetStyle {
    static let accent = Color(red: 234 / 255, green: 74 / 255, blue: 42 / 255)
    static let onAccent = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let padding: CGFloat = 16
    static let tileHeight: CGFloat = 44
    /// Widget corner (36) minus the padding, so the curves run parallel.
    static let tileRadius: CGFloat = 20
}

/// The default widget background, dark in both system appearances.
/// Widgets can't show the wallpaper through their background, so this
/// is an opaque dark sheen with a light rim.
struct NLinkDarkBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 34 / 255, green: 34 / 255, blue: 40 / 255),
                    Color(red: 13 / 255, green: 13 / 255, blue: 17 / 255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            ContainerRelativeShape().strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

struct NLinkSmallWidget: View {
    let vehicle: VehicleEntity
    let buttons: [ConfiguredWidgetButton]
    let textColor: Color
    let showPercent: Bool

    private var percentage: Double { vehicle.batteryPercentage ?? 0 }

    private var statusText: String {
        guard showPercent, vehicle.batteryPercentage != nil else { return vehicle.rangeText }
        return "\(vehicle.rangeText) · \(Int(percentage.rounded()))%"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chargeBar.padding(.top, 5)
            Spacer(minLength: 8)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    tile(button)
                }
            }
        }
        .padding(NLinkWidgetStyle.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(vehicle.displayName.uppercased())
                .font(.system(size: 20, weight: .bold).width(.condensed))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            if vehicle.isCharging == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NLinkWidgetStyle.accent)
                    .widgetAccentable()
                    .accessibilityLabel("Charging")
            }
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(textColor.opacity(0.78))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 20)
    }

    private var chargeBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(textColor.opacity(0.16))
                Capsule()
                    .fill(NLinkWidgetStyle.accent)
                    .widgetAccentable()
                    .frame(width: geo.size.width * min(max(percentage / 100, 0), 1))
                if let target = vehicle.targetStateOfCharge {
                    Rectangle()
                        .fill(textColor)
                        .frame(width: 2, height: 7)
                        .offset(x: geo.size.width * CGFloat(target) / 100 - 1)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func tile(_ button: ConfiguredWidgetButton) -> some View {
        if let intent = button.action.makeIntent(for: vehicle) {
            Button(intent: intent) {
                Image(systemName: button.action.displayIcon(for: vehicle))
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityLabel(button.action.kind.defaultTitle)
            }
            .buttonStyle(NLinkTileStyle(emphasis: emphasis(for: button), textColor: textColor))
        }
    }

    /// Reflects the last known status only. Every tile stays tappable,
    /// because that status can be out of date.
    private func emphasis(for button: ConfiguredWidgetButton) -> NLinkTileStyle.Emphasis {
        if button.colorName != nil { return .custom(button.color(for: vehicle)) }
        switch button.action.kind {
        case .lock: return state(active: vehicle.isLocked.map { !$0 }, idle: vehicle.isLocked)
        case .unlock: return state(active: nil, idle: vehicle.isLocked.map { !$0 })
        case .startClimate: return state(active: nil, idle: vehicle.isClimateOn)
        case .stopClimate: return state(active: vehicle.isClimateOn, idle: vehicle.isClimateOn.map { !$0 })
        case .startCharge: return state(active: nil, idle: vehicle.isCharging)
        case .stopCharge: return state(active: vehicle.isCharging, idle: vehicle.isCharging.map { !$0 })
        case .none: return .normal
        }
    }

    private func state(active: Bool?, idle: Bool?) -> NLinkTileStyle.Emphasis {
        if active == true { return .active }
        if idle == true { return .idle }
        return .normal
    }
}

struct NLinkTileStyle: ButtonStyle {
    enum Emphasis {
        case normal, active, idle
        case custom(Color)
    }

    let emphasis: Emphasis
    let textColor: Color

    private var fill: Color {
        switch emphasis {
        case .normal: textColor.opacity(0.13)
        case .active: NLinkWidgetStyle.accent
        case .idle: textColor.opacity(0.05)
        case let .custom(color): color.opacity(0.6)
        }
    }

    private var foreground: Color {
        switch emphasis {
        case .normal: textColor
        case .active: NLinkWidgetStyle.onAccent
        case .idle: textColor.opacity(0.62)
        case .custom: .white
        }
    }

    private var rim: Color {
        switch emphasis {
        case .normal: textColor.opacity(0.12)
        case .idle: textColor.opacity(0.07)
        case .active, .custom: .clear
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: NLinkWidgetStyle.tileRadius, style: .continuous)
        return configuration.label
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: NLinkWidgetStyle.tileHeight)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(rim, lineWidth: 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
