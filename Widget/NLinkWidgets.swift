//
//  NLinkWidgets.swift
//  Widget
//
//  The small and medium Home Screen widgets: car status beside a grid
//  of controls, on a dark surface. Orange marks the control that matters
//  right now (unlocked car, climate or charge running).
//

import AppIntents
import SwiftUI
import WidgetKit

/// The app's N Link tokens (`NTheme`, which the widget extension doesn't
/// compile): Luminous Orange on near-black, condensed numerals.
private enum NLinkWidgetStyle {
    static let accent = Color(red: 234 / 255, green: 74 / 255, blue: 42 / 255)
    static let onAccent = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let padding: CGFloat = 16
    static let tileHeight: CGFloat = 44
    /// The app's button corner, rather than following the widget's curve.
    static let tileRadius: CGFloat = 14

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

/// The default widget background: black with a hairline edge, dark in
/// both system appearances.
struct NLinkDarkBackground: View {
    static let color = Color.black

    var body: some View {
        ZStack {
            Self.color
            ContainerRelativeShape().strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

/// Small tracked caps line, e.g. "CHARGING · 7.2 KW" (`NCapsLabel`).
private struct NLinkCapsLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The app's segmented charge bar (`NBlockBar`) with a limit tick.
private struct NLinkBlockBar: View {
    let value: Double
    let limit: Double?
    let textColor: Color
    var blocks = 16
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2.5
            let width = (geo.size.width - spacing * CGFloat(blocks - 1)) / CGFloat(blocks)
            let filled = Int((min(max(value, 0), 1) * Double(blocks)).rounded())
            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    ForEach(0..<blocks, id: \.self) { index in
                        Rectangle()
                            .fill(index < filled ? NLinkWidgetStyle.accent : textColor.opacity(0.16))
                            .widgetAccentable(index < filled)
                            .frame(width: width)
                    }
                }
                .frame(height: height)
                if let limit {
                    Rectangle()
                        .fill(textColor)
                        .frame(width: 2, height: height + 5)
                        .offset(x: geo.size.width * min(max(limit, 0), 1) - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height + 5)
        .accessibilityHidden(true)
    }
}

/// The app's 270° segmented gauge (`NArcGauge`): the orange fill over a
/// track, split by gaps, with a white tick at the charge limit. The gaps
/// are cut in the background's own colour (`gapColor`) so they read as
/// space between segments, not as outlines; with no solid background to
/// match (a custom gradient), the arc is drawn unsegmented.
private struct NLinkArcGauge: View {
    let value: Double
    let marker: Double?
    let size: CGFloat
    let lineWidth: CGFloat
    let textColor: Color
    let gapColor: Color?
    var sweep: Double = 270
    var segments = 36

    var body: some View {
        let fraction = sweep / 360
        let circumference = .pi * (size - lineWidth)
        let segmentLength = circumference * fraction / Double(segments)
        ZStack {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(textColor.opacity(0.16), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            Circle()
                .trim(from: 0, to: fraction * min(max(value, 0), 1))
                .stroke(NLinkWidgetStyle.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .widgetAccentable()
            if let gapColor {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(gapColor, style: StrokeStyle(
                        lineWidth: lineWidth + 2,
                        dash: [2, max(segmentLength - 2, 1)]
                    ))
            }
            if let marker {
                Capsule()
                    .fill(textColor)
                    .frame(width: 2.5, height: lineWidth + 6)
                    .offset(y: -(size - lineWidth) / 2)
                    .rotationEffect(.degrees(90) + .degrees(sweep * min(max(marker, 0), 1)))
            }
        }
        .rotationEffect(.degrees(90 + (360 - sweep) / 2))
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension VehicleEntity {
    /// The caps line under the vehicle name, as the Live Activity and the
    /// app's charging screen phrase it: "CHARGING · 7.2 KW" while
    /// charging, otherwise lock and climate state.
    fileprivate var nStatusLine: (text: String, isLive: Bool) {
        if isCharging == true {
            if let kw = chargeSpeedKilowatts, kw > 0 {
                return (String(format: "Charging · %.1f kW", kw), true)
            }
            return ("Charging", true)
        }
        var parts: [String] = []
        if let locked = isLocked { parts.append(locked ? "Locked" : "Unlocked") }
        if isClimateOn == true { parts.append("Climate on") }
        if parts.isEmpty, isPluggedIn == true { parts.append("Plugged in") }
        return (parts.joined(separator: " · "), isClimateOn == true)
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(vehicle.displayName.uppercased())
                .font(NLinkWidgetStyle.display(20, weight: .bold))
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
                .font(NLinkWidgetStyle.display(15))
                .foregroundStyle(textColor.opacity(0.78))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 20)
    }

    private var chargeBar: some View {
        NLinkBlockBar(
            value: percentage / 100,
            limit: vehicle.targetStateOfCharge.map { Double($0) / 100 },
            textColor: textColor
        )
    }

    @ViewBuilder
    private func tile(_ button: ConfiguredWidgetButton) -> some View {
        if let intent = button.action.makeIntent(for: vehicle) {
            Button(intent: intent) {
                Image(systemName: button.action.displayIcon(for: vehicle))
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityLabel(button.action.kind.defaultTitle)
            }
            .buttonStyle(NLinkTileStyle(emphasis: button.emphasis(for: vehicle), textColor: textColor))
        }
    }
}

extension ConfiguredWidgetButton {
    /// Reflects the last known status only. Every tile stays tappable,
    /// because that status can be out of date.
    func emphasis(for vehicle: VehicleEntity) -> NLinkTileStyle.Emphasis {
        if colorName != nil { return .custom(color(for: vehicle)) }
        switch action.kind {
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
        case .normal: textColor.opacity(0.09)
        case .active: NLinkWidgetStyle.accent
        case .idle: textColor.opacity(0.03)
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

    /// A solid hairline, as the app's buttons and cards have.
    private var rim: Color {
        switch emphasis {
        case .normal: textColor.opacity(0.18)
        case .idle: textColor.opacity(0.1)
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

struct NLinkMediumWidget: View {
    let vehicle: VehicleEntity
    let buttons: [ConfiguredWidgetButton]
    let textColor: Color
    let showPercent: Bool

    /// The default black background, whose colour the gauge's gaps match.
    var isDefaultBackground = true

    private static let ringSize: CGFloat = 112

    private var percentage: Double { vehicle.batteryPercentage ?? 0 }

    var body: some View {
        HStack(spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                header
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                        tile(button)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(NLinkWidgetStyle.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ring

    private var ring: some View {
        let lineWidth = Self.ringSize * 0.1
        return ZStack {
            NLinkArcGauge(
                value: percentage / 100,
                marker: vehicle.targetStateOfCharge.map { Double($0) / 100 },
                size: Self.ringSize,
                lineWidth: lineWidth,
                textColor: textColor,
                gapColor: isDefaultBackground ? NLinkDarkBackground.color : nil
            )
            VStack(spacing: 0) {
                if showPercent, vehicle.batteryPercentage != nil {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(percentage.rounded()))")
                            .font(NLinkWidgetStyle.display(40, weight: .bold))
                            .monospacedDigit()
                        Text("%")
                            .font(NLinkWidgetStyle.display(17))
                            .foregroundStyle(textColor.opacity(0.6))
                    }
                    .foregroundStyle(textColor)
                    Text(vehicle.rangeText)
                        .font(NLinkWidgetStyle.display(15))
                        .foregroundStyle(textColor.opacity(0.78))
                } else {
                    Text(vehicle.rangeText)
                        .font(NLinkWidgetStyle.display(22, weight: .bold))
                        .foregroundStyle(textColor)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, lineWidth + 4)
            // The arc is open at the bottom; sit the number a touch higher.
            .offset(y: -2)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ringAccessibilityLabel)
    }

    private var ringAccessibilityLabel: String {
        var parts: [String] = []
        if vehicle.batteryPercentage != nil { parts.append("\(Int(percentage.rounded())) percent") }
        parts.append(vehicle.rangeText)
        if let target = vehicle.targetStateOfCharge { parts.append("limit \(target) percent") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(vehicle.displayName.uppercased())
                .font(NLinkWidgetStyle.display(22, weight: .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            NLinkCapsLabel(text: statusLine, color: statusIsLive ? NLinkWidgetStyle.accent : textColor.opacity(0.6))
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    /// "CHARGING · 7.2 KW · 6:48 AM", or lock/climate state when not
    /// charging. While a command sent from a widget is waiting on the next
    /// status refresh, that shows instead. Times are absolute because
    /// widget text is frozen between reloads.
    private var statusLine: String {
        if let pending = pendingCommand {
            return "\(pending.command) sent \(pending.date.formatted(date: .omitted, time: .shortened))"
        }
        let status = vehicle.nStatusLine.text
        return status.isEmpty ? updatedTime : "\(status) · \(updatedTime)"
    }

    private var statusIsLive: Bool { pendingCommand == nil && vehicle.nStatusLine.isLive }

    private var pendingCommand: (command: String, date: Date)? {
        guard let latest = WidgetCommandStatus.latest(vin: vehicle.vin) else { return nil }
        let lastUpdated = vehicle.lastUpdated ?? .distantPast
        guard latest.date > lastUpdated,
              Date().timeIntervalSince(latest.date) < 30 * 60 else { return nil }
        return latest
    }

    private var updatedTime: String {
        let date = vehicle.timestamp
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Controls

    @ViewBuilder
    private func tile(_ button: ConfiguredWidgetButton) -> some View {
        if let intent = button.action.makeIntent(for: vehicle) {
            Button(intent: intent) {
                HStack(spacing: 5) {
                    Image(systemName: button.action.displayIcon(for: vehicle))
                        .font(.system(size: 14, weight: .semibold))
                    Text(button.action.kind.tileTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(NLinkTileStyle(emphasis: button.emphasis(for: vehicle), textColor: textColor))
            .accessibilityLabel(button.action.kind.defaultTitle)
        }
    }
}

private extension WidgetActionKind {
    /// Fits a medium-widget tile; the icon says which system it acts on.
    var tileTitle: String {
        switch self {
        case .startClimate: "Start"
        case .startCharge: "Charge"
        case .stopClimate, .stopCharge: "Stop"
        default: defaultTitle
        }
    }
}
