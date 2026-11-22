//
//  NClimateControls.swift
//  N Link
//
//  Climate pieces shared by the Climate screen, the preset editor and the
//  home screens: what the running session was started with, the seat
//  card, toggle rows and the read-only "Starts with" summary.
//
//  The rule they follow: solid orange means the car is doing it now.
//  While climate is off, the options are a preset's settings for the next
//  start — shown read-only and edited in the preset editor. While it runs,
//  they're live controls that re-send start with the change.
//

import BetterBlueKit
import Foundation
import SwiftUI

// MARK: - Session

/// What the running climate session was started with. The car reports
/// only front defrost and the heated wheel back, so seats and rear
/// defrost come from here. Kept per VIN in UserDefaults so it survives
/// the app being closed while climate runs.
struct NClimateSession: Codable, Equatable {
    var options: ClimateOptions
    var presetName: String?
    var presetIcon: String?

    private static func key(_ vin: String) -> String { "NClimateSession.\(vin)" }

    static func load(vin: String) -> NClimateSession? {
        guard let data = UserDefaults.standard.data(forKey: key(vin)) else { return nil }
        return try? JSONDecoder().decode(NClimateSession.self, from: data)
    }

    static func save(_ session: NClimateSession, vin: String) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: key(vin))
    }

    static func clear(vin: String) {
        UserDefaults.standard.removeObject(forKey: key(vin))
    }
}

/// One adjustable part of a climate session.
enum NClimateItem: Hashable, CaseIterable {
    case driverSeat, passengerSeat, steeringWheel, frontDefrost, rearDefrost

    var title: String {
        switch self {
        case .driverSeat: "Driver seat"
        case .passengerSeat: "Passenger seat"
        case .steeringWheel: "Heated steering wheel"
        case .frontDefrost: "Front defrost"
        case .rearDefrost: "Rear defrost"
        }
    }

    /// Whether the car reports this back, so a change can be confirmed.
    var isReported: Bool { self == .steeringWheel || self == .frontDefrost }

    /// Whether `status` shows this item as `options` sets it.
    func matches(_ status: VehicleStatus, _ options: ClimateOptions) -> Bool {
        switch self {
        case .steeringWheel: status.climateStatus.steeringWheelHeatingOn == (options.steeringWheel > 0)
        case .frontDefrost: status.climateStatus.defrostOn == options.defrost
        default: status.climateStatus.airControlOn
        }
    }
}

extension BBVehicle {
    var isClimateOn: Bool { climateStatus?.airControlOn == true }

    /// What climate is doing now: the session it was started with, with
    /// the car's own report laid over the parts it reports.
    @MainActor
    var runningClimateOptions: ClimateOptions {
        var options = NClimateSession.load(vin: vin)?.options
            ?? activeClimatePreset?.climateOptions
            ?? ClimateOptions(preferredUnits: NFormat.temperatureUnit)
        if let status = climateStatus {
            options.steeringWheel = status.steeringWheelHeatingOn ? max(options.steeringWheel, 1) : 0
            options.defrost = status.defrostOn
        }
        return options
    }

    /// Seat heat/ventilation is only offered where the car supports it.
    var showsSeatControls: Bool { generation >= 3 || enableSeatHeatControls }
}

extension ClimateOptions {
    func isOn(_ item: NClimateItem) -> Bool {
        switch item {
        case .driverSeat: frontLeftSeat > 0
        case .passengerSeat: frontRightSeat > 0
        case .steeringWheel: steeringWheel > 0
        case .frontDefrost: defrost
        case .rearDefrost: rearDefrostEnabled
        }
    }

    func valueText(_ item: NClimateItem) -> String {
        switch item {
        case .driverSeat: NSeatControl.stateText(level: frontLeftSeat, ventilated: frontLeftVentilationEnabled)
        case .passengerSeat: NSeatControl.stateText(level: frontRightSeat, ventilated: frontRightVentilationEnabled)
        default: isOn(item) ? "On" : "Off"
        }
    }

    mutating func setOn(_ item: NClimateItem, _ on: Bool) {
        switch item {
        case .steeringWheel: steeringWheel = on ? 1 : 0
        case .frontDefrost: defrost = on
        case .rearDefrost: rearDefrostEnabled = on
        case .driverSeat: frontLeftSeat = on ? max(frontLeftSeat, 1) : 0
        case .passengerSeat: frontRightSeat = on ? max(frontRightSeat, 1) : 0
        }
    }

    /// "Driver heat 2 · Steering wheel · Front defrost" — what's on.
    func summary(includeSeats: Bool) -> String {
        var parts: [String] = []
        if includeSeats {
            if frontLeftSeat > 0 { parts.append("Driver \(valueText(.driverSeat).lowercased())") }
            if frontRightSeat > 0 { parts.append("Passenger \(valueText(.passengerSeat).lowercased())") }
        }
        if steeringWheel > 0 { parts.append("Wheel") }
        if defrost { parts.append("Front defrost") }
        if rearDefrostEnabled { parts.append("Rear defrost") }
        return parts.isEmpty ? "Air only" : parts.joined(separator: " · ")
    }
}

// MARK: - Seat card

/// Seat heat / ventilation control. Tap for a menu: Off, Heat 1–3,
/// Cool 1–3. Orange bars for heat, blue for cooling. Reports level and
/// cooling together in one `onSet`, so a live change sends one command.
struct NSeatControl: View {
    let title: String
    let level: Int
    let ventilated: Bool
    var isBusy = false
    let onSet: (_ level: Int, _ ventilated: Bool) -> Void

    static func stateText(level: Int, ventilated: Bool) -> String {
        guard level > 0 else { return "Off" }
        return ventilated ? "Cool \(level)" : "Heat \(level)"
    }

    private var stateText: String { Self.stateText(level: level, ventilated: ventilated) }

    var body: some View {
        Menu {
            Button("Off") { onSet(0, false) }
            Section("Heat") {
                ForEach(1...3, id: \.self) { value in
                    Button("Heat \(value)") { onSet(value, false) }
                }
            }
            Section("Cool") {
                ForEach(1...3, id: \.self) { value in
                    Button("Cool \(value)") { onSet(value, true) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(NTheme.textSecondary)
                HStack {
                    if isBusy {
                        ProgressView().controlSize(.small).tint(NTheme.text)
                    } else {
                        Text(stateText)
                            .font(NTheme.display(22))
                            .foregroundStyle(level > 0 ? NTheme.text : NTheme.textSecondary)
                    }
                    Spacer()
                    NSeatBars(level: level, ventilated: ventilated)
                }
            }
            .nCard(radius: 16, padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(stateText)")
    }
}

struct NSeatBars: View {
    let level: Int
    let ventilated: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...3, id: \.self) { bar in
                Rectangle()
                    .fill(bar <= level ? (ventilated ? Color(hex: 0x4FA3E0) : NTheme.accent) : NTheme.track)
                    .frame(width: 6, height: CGFloat(6 + bar * 5))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Rows

/// A toggle row in the N style, with a spinner while its change is sent.
struct NClimateToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var isBusy = false
    var divider = true

    var body: some View {
        VStack(spacing: 0) {
            // NToggleStyle lays out the label, a spacer and the switch, and
            // draws the label itself — so the title goes in once, here.
            Toggle(isOn: $isOn) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15)).foregroundStyle(NTheme.text)
                    if isBusy {
                        ProgressView().controlSize(.small).tint(NTheme.text)
                    }
                }
            }
            .toggleStyle(NToggleStyle())
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            if divider { Rectangle().fill(NTheme.hairline).frame(height: 1) }
        }
    }
}

/// Read-only "Starts with" list: what the selected preset will turn on
/// when climate starts, with a way into the preset editor. Nothing here is
/// orange, because nothing here is running yet.
struct NClimateStartsWith<EditLink: View>: View {
    let options: ClimateOptions
    let showsSeats: Bool
    let showsDuration: Bool
    @ViewBuilder let editLink: () -> EditLink

    private var items: [NClimateItem] {
        (showsSeats ? [.driverSeat, .passengerSeat] : []) + [.steeringWheel, .frontDefrost, .rearDefrost]
    }

    var body: some View {
        NGroup {
            ForEach(items, id: \.self) { item in
                NRow(title: item.title) {
                    Text(options.valueText(item))
                        .foregroundStyle(options.isOn(item) ? NTheme.text : NTheme.textSecondary)
                }
            }
            if showsDuration {
                NRow("Run for", value: "\(options.duration) min")
            }
            editLink()
        }
    }
}

// MARK: - Dial

/// Target temperature arc with − / + steppers. Locked while climate
/// runs: the car's set temperature can't be changed mid-session here.
struct NClimateDial: View {
    let temperature: Double
    let unit: Temperature.Units
    let statusText: String
    var statusIsLive = false
    var isLocked = false
    var label = "Target"
    let onStep: (_ steps: Int) -> Void

    var body: some View {
        let range = unit.hvacRange
        let fraction = (temperature - range.lowerBound) / (range.upperBound - range.lowerBound)
        ZStack {
            NArcGauge(value: fraction, lineWidth: 14, sweep: 240, segments: 40)
                .frame(width: 230, height: 230)
            VStack(spacing: 0) {
                NCapsLabel(label)
                Text(unit.format(temperature, to: unit).replacingOccurrences(of: unit.symbol, with: "°"))
                    .font(NTheme.display(72, weight: .bold))
                    .foregroundStyle(NTheme.text)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: temperature))
                Text(statusText)
                    .font(.system(size: 13))
                    .foregroundStyle(statusIsLive ? NTheme.accent : NTheme.textSecondary)
            }
            HStack {
                stepButton("minus", label: "Lower temperature") { onStep(-1) }
                Spacer()
                stepButton("plus", label: "Raise temperature") { onStep(1) }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 56, height: 56)
                .foregroundStyle(isLocked ? NTheme.textSecondary.opacity(0.4) : NTheme.text)
                .background(NTheme.cardRaised, in: Circle())
                .overlay(Circle().strokeBorder(NTheme.borderStrong))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel(label)
    }
}
