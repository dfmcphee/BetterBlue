//
//  NGlanceHomeView.swift
//  N Link
//
//  Car tab for short, wide windows — the iPhone Duo's outer display.
//  Everything for a quick "pre-condition and go" fits without
//  scrolling: charge, lock, and climate with its common toggles.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NGlanceHomeView: View {
    let vehicle: BBVehicle
    let vehicles: [BBVehicle]
    @Binding var selectedIndex: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner

    /// Climate edits when the vehicle has no preset to hold them.
    @State private var localOptions: ClimateOptions?

    private var unit: Temperature.Units { NFormat.temperatureUnit }
    private var showsSeats: Bool { vehicle.generation >= 3 || vehicle.enableSeatHeatControls }
    private var climateOn: Bool { vehicle.climateStatus?.airControlOn == true }

    var body: some View {
        VStack(spacing: 18) {
            header
            HStack(spacing: 12) {
                gauge
                VStack(spacing: 10) {
                    if vehicle.isEV { chargeButton }
                    lockButton
                }
            }
            .frame(height: 236)
            climatePanel
            statusStrip
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .background(NTheme.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: NDestination.self) { destination in
            switch destination {
            case .climate: NClimateView(vehicle: vehicle)
            case .charging: NChargingView(vehicle: vehicle)
            case .security: NSecurityView(vehicle: vehicle)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                NCapsLabel("N Link", color: NTheme.accent)
                Text(vehicle.displayName.uppercased())
                    .font(NTheme.display(26, weight: .bold))
                    .foregroundStyle(NTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(runner.isBusy(.refresh) ? "Refreshing…" : NFormat.updated(vehicle.lastUpdated, now: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(NTheme.textSecondary)
                }
            }
            Spacer()
            NIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Refresh status",
                        isBusy: runner.isBusy(.refresh)) {
                Task { await runner.refresh(modelContext: modelContext) }
            }
        }
    }

    // MARK: - Gauge

    private var gauge: some View {
        let ev = vehicle.evStatus
        let percentage = ev?.evRange.percentage ?? vehicle.gasRange?.percentage ?? 0
        let limit = ev?.currentTargetSOC ?? ev?.targetSocAC
        return NavigationLink(value: NDestination.charging) {
            ZStack {
                NArcGauge(value: percentage / 100, marker: limit.map { $0 / 100 }, lineWidth: 14, segments: 40)
                    .padding(12)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(percentage.rounded()))")
                            .font(NTheme.display(50, weight: .bold))
                            .monospacedDigit()
                        Text("%").font(NTheme.display(18)).foregroundStyle(NTheme.textSecondary)
                    }
                    .foregroundStyle(NTheme.text)
                    if let range = NFormat.distance(ev?.evRange.range ?? vehicle.gasRange?.range) {
                        Text(range).font(NTheme.display(17)).foregroundStyle(NTheme.text)
                    }
                    if let limit {
                        Text("limit \(Int(limit))%").font(.system(size: 10)).foregroundStyle(NTheme.textSecondary)
                    }
                }
            }
            .frame(width: 176)
            .frame(maxHeight: .infinity)
            .background(Color(hex: 0x0C0C0C), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(NTheme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Battery \(Int(percentage.rounded())) percent. Open charging")
    }

    // MARK: - Charge / lock

    private var chargeButton: some View {
        let ev = vehicle.evStatus
        let charging = ev?.charging == true
        let label: String = {
            if let status = runner.statusText[.charge] { return status }
            guard let ev else { return "—" }
            if ev.charging {
                return ev.chargeSpeed > 0 ? String(format: "Charging · %.0f kW", ev.chargeSpeed) : "Charging"
            }
            return ev.pluggedIn ? "Plugged in · ready" : "Not plugged in"
        }()
        return quickButton(
            label: label,
            action: charging ? "Stop charge" : "Start charge",
            icon: "bolt.fill",
            primary: false,
            isBusy: runner.isBusy(.charge)
        ) {
            Task { await runner.setCharging(!charging, modelContext: modelContext) }
        }
        .disabled(ev?.pluggedIn != true)
    }

    private var lockButton: some View {
        let locked = vehicle.lockStatus == .locked
        let label = runner.statusText[.lock]
            ?? (locked ? "Locked · \(NFormat.openingsSummary(vehicle).text.lowercased())" : "Unlocked")
        return quickButton(
            label: label,
            action: locked ? "Unlock" : "Lock",
            icon: locked ? "lock.fill" : "lock.open.fill",
            primary: !locked,
            isBusy: runner.isBusy(.lock)
        ) {
            Task { await runner.setLocked(!locked, modelContext: modelContext) }
        }
    }

    private func quickButton(
        label: String, action: String, icon: String, primary: Bool, isBusy: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(primary ? NTheme.onAccent.opacity(0.7) : NTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(action)
                        .font(NTheme.display(22))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                if isBusy {
                    ProgressView().controlSize(.small).tint(primary ? NTheme.onAccent : NTheme.text)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primary ? NTheme.onAccent : NTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(primary ? NTheme.onAccent : NTheme.text)
            .background(primary ? NTheme.accent : NTheme.cardRaised,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if !primary {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(NTheme.borderStrong)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: - Climate

    private var options: ClimateOptions {
        vehicle.activeClimatePreset?.climateOptions ?? localOptions ?? ClimateOptions(preferredUnits: unit)
    }

    /// Edits stick to the selected preset, like the full Climate screen.
    private func edit(_ change: (inout ClimateOptions) -> Void) {
        var updated = options
        change(&updated)
        if let preset = vehicle.activeClimatePreset {
            preset.climateOptions = updated
            try? modelContext.save()
        } else {
            localOptions = updated
        }
    }

    private var climatePanel: some View {
        // While running, show what the car is set to; the stepper edits
        // the preset for the next start, so it's locked until climate stops.
        let temperature = runningTemperature ?? options.displayTemperature(in: unit)
        let stepperLocked = runningTemperature != nil
        return VStack(spacing: 10) {
            HStack {
                NavigationLink(value: NDestination.climate) {
                    VStack(alignment: .leading, spacing: 1) {
                        NCapsLabel("Climate ›")
                        Text(runner.statusText[.climate] ?? climateSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(climateOn ? NTheme.accent : NTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) {
                    stepButton("minus", label: "Lower temperature", enabled: !stepperLocked) {
                        edit { $0.stepTemperature(by: -1, unit: unit) }
                    }
                    // Sized for the widest value ("21.5°") so the steppers
                    // hold still and the number never truncates.
                    Text(temperature.formatted(.number.precision(.fractionLength(0...1))) + "°")
                        .font(NTheme.display(40, weight: .bold))
                        .foregroundStyle(NTheme.text)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: unit == .celsius ? 84 : 66)
                        .contentTransition(.numericText(value: temperature))
                        .accessibilityLabel(stepperLocked ? "Running at \(NFormat.temperature(Temperature(value: temperature, units: unit)))" : "Target \(NFormat.temperature(Temperature(value: temperature, units: unit)))")
                    stepButton("plus", label: "Raise temperature", enabled: !stepperLocked) {
                        edit { $0.stepTemperature(by: 1, unit: unit) }
                    }
                }
            }
            HStack(spacing: 6) {
                if showsSeats {
                    let level = options.frontLeftSeat
                    chip("Seat", level > 0 ? "Heat \(level)" : "Off", isOn: level > 0) {
                        edit {
                            $0.frontLeftSeat = ($0.frontLeftSeat + 1) % 4
                            $0.frontLeftVentilationEnabled = false
                        }
                    }
                }
                chip("Wheel", options.steeringWheel > 0 ? "On" : "Off", isOn: options.steeringWheel > 0) {
                    edit { $0.steeringWheel = $0.steeringWheel > 0 ? 0 : 1 }
                }
                chip("Front", options.defrost ? "Defrost" : "Off", isOn: options.defrost) {
                    edit { $0.defrost.toggle() }
                }
                chip("Rear", options.rearDefrostEnabled ? "Defrost" : "Off", isOn: options.rearDefrostEnabled) {
                    edit { $0.rearDefrostEnabled.toggle() }
                }
            }
            NCommandButton(
                title: climateOn ? "Stop climate" : startTitle,
                kind: climateOn ? .secondary : .primary,
                isBusy: runner.isBusy(.climate),
                busyText: runner.statusText[.climate]
            ) {
                Task {
                    if climateOn {
                        await runner.stopClimate(modelContext: modelContext)
                    } else {
                        let preset = vehicle.activeClimatePreset
                        await runner.startClimate(
                            options: options,
                            presetName: preset?.name,
                            presetIcon: preset?.iconName,
                            modelContext: modelContext
                        )
                    }
                }
            }
        }
        .nCard(radius: 20, padding: 14)
    }

    /// The car's set temperature while climate runs, snapped like the stepper.
    private var runningTemperature: Double? {
        guard climateOn, let temp = vehicle.climateStatus?.temperature else { return nil }
        let value = temp.units.convert(temp.value, to: unit)
        return unit == .celsius ? (value * 2).rounded() / 2 : value.rounded()
    }

    private var climateSubtitle: String {
        if climateOn { return "Running" }
        if let preset = vehicle.activeClimatePreset { return "Off · preset \(preset.name)" }
        return "Off"
    }

    private var startTitle: String {
        vehicle.showClimateDuration ? "Start climate · \(options.duration) min" : "Start climate"
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? NTheme.text : NTheme.textSecondary.opacity(0.4))
                .background(NTheme.cardRaised, in: Circle())
                .overlay(Circle().strokeBorder(NTheme.borderStrong))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityHint(enabled ? "" : "Stop climate to change the temperature")
    }

    private func chip(_ title: String, _ value: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(isOn ? NTheme.onAccent.opacity(0.7) : NTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(isOn ? NTheme.onAccent : NTheme.text)
            .background(isOn ? NTheme.accent : NTheme.cardRaised,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if !isOn {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NTheme.border)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        NavigationLink(value: NDestination.security) {
            HStack {
                Text(NFormat.openingsSummary(vehicle).text)
                Spacer()
                Text("12V \(vehicle.battery12V.map { "\($0)%" } ?? "—")")
                Spacer()
                Text("Tires \(vehicle.tirePressureWarning.map { $0.hasWarning ? "check" : "OK" } ?? "—")")
                Spacer()
                Text(NFormat.distance(vehicle.odometer) ?? "—")
            }
            .font(.system(size: 12))
            .foregroundStyle(NTheme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(NTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(NTheme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension ClimateOptions {
    /// Target temperature in `unit`, snapped to what the HVAC accepts.
    func displayTemperature(in unit: Temperature.Units) -> Double {
        let value = temperature.units.convert(temperature.value, to: unit)
        return unit == .celsius ? (value * 2).rounded() / 2 : value.rounded()
    }

    /// One HVAC step (1°F or 0.5°C) up or down, clamped to the HVAC range.
    mutating func stepTemperature(by steps: Int, unit: Temperature.Units) {
        let step = unit == .celsius ? 0.5 : 1.0
        let range = unit.hvacRange
        let next = min(range.upperBound, max(range.lowerBound, displayTemperature(in: unit) + Double(steps) * step))
        temperature = Temperature(value: next, units: unit)
    }
}
