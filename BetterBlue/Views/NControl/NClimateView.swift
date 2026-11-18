//
//  NClimateView.swift
//  N Link
//
//  Pre-conditioning: target temperature dial, seats, steering wheel,
//  defrost, run time and presets. Only exposes what the Hyundai/Kia
//  start-climate command accepts.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NClimateView: View {
    let vehicle: BBVehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner
    @Environment(VehicleSheetPresentation.self) private var sheetPresentation

    @State private var options = ClimateOptions()
    @State private var loadedPresetID: UUID?

    private var unit: Temperature.Units { NFormat.temperatureUnit }
    private var isOn: Bool { vehicle.climateStatus?.airControlOn == true }
    private var showsSeats: Bool { vehicle.generation >= 3 || vehicle.enableSeatHeatControls }
    private var presets: [ClimatePreset] { vehicle.sortedClimatePresets }
    private var activePreset: ClimatePreset? { presets.first { $0.id == loadedPresetID } }

    var body: some View {
        NPushedScreen(title: "Climate", subtitle: subtitle) {
            dial
            if showsSeats { seats }
            toggles
            if vehicle.showClimateDuration { duration }
            presetChips
            NCommandButton(
                title: isOn ? "Stop climate" : startTitle,
                kind: isOn ? .secondary : .primary,
                height: 56,
                isBusy: runner.isBusy(.climate),
                busyText: runner.statusText[.climate]
            ) {
                Task {
                    if isOn {
                        await runner.stopClimate(modelContext: modelContext)
                    } else {
                        await runner.startClimate(
                            options: options,
                            presetName: activePreset?.name,
                            presetIcon: activePreset?.iconName,
                            modelContext: modelContext
                        )
                    }
                }
            }
        }
        .onAppear(perform: loadInitialOptions)
        .onChange(of: options) { _, newValue in
            // Edits stick to the selected preset, like the old editor.
            if let activePreset, activePreset.climateOptions != newValue {
                activePreset.climateOptions = newValue
                try? modelContext.save()
            }
        }
    }

    private var subtitle: String {
        if isOn, let temp = vehicle.climateStatus?.temperature {
            return "Running · set to \(NFormat.temperature(temp))"
        }
        return "Off · \(NFormat.updated(vehicle.lastUpdated).lowercased())"
    }

    private var startTitle: String {
        vehicle.showClimateDuration ? "Start climate · \(options.duration) min" : "Start climate"
    }

    private func loadInitialOptions() {
        guard loadedPresetID == nil else { return }
        if let preset = vehicle.activeClimatePreset {
            loadedPresetID = preset.id
            options = preset.climateOptions
        } else {
            options = ClimateOptions(preferredUnits: unit)
        }
    }

    // MARK: - Dial

    private var displayTemperature: Double {
        let value = options.temperature.units.convert(options.temperature.value, to: unit)
        return unit == .celsius ? (value * 2).rounded() / 2 : value.rounded()
    }

    private var dial: some View {
        let range = unit.hvacRange
        let step = unit == .celsius ? 0.5 : 1.0
        let fraction = (displayTemperature - range.lowerBound) / (range.upperBound - range.lowerBound)
        return ZStack {
            NArcGauge(value: fraction, lineWidth: 14, sweep: 240, segments: 40)
                .frame(width: 230, height: 230)
            VStack(spacing: 0) {
                NCapsLabel("Target")
                Text(unit.format(displayTemperature, to: unit).replacingOccurrences(of: unit.symbol, with: "°"))
                    .font(NTheme.display(72, weight: .bold))
                    .foregroundStyle(NTheme.text)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: displayTemperature))
                Text(isOn ? "Running" : (options.climate ? "Ready to start" : "Fan off"))
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? NTheme.accent : NTheme.textSecondary)
            }
            HStack {
                stepButton("minus", label: "Lower temperature") {
                    setTemperature(max(range.lowerBound, displayTemperature - step))
                }
                Spacer()
                stepButton("plus", label: "Raise temperature") {
                    setTemperature(min(range.upperBound, displayTemperature + step))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 250)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func setTemperature(_ value: Double) {
        withAnimation(.snappy) {
            options.temperature = Temperature(value: value, units: unit)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .frame(width: 56, height: 56)
                .foregroundStyle(NTheme.text)
                .background(NTheme.cardRaised, in: Circle())
                .overlay(Circle().strokeBorder(NTheme.borderStrong))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Seats

    private var seats: some View {
        HStack(spacing: 10) {
            NSeatControl(
                title: "Driver seat",
                level: $options.frontLeftSeat,
                ventilated: $options.frontLeftVentilationEnabled
            )
            NSeatControl(
                title: "Passenger seat",
                level: $options.frontRightSeat,
                ventilated: $options.frontRightVentilationEnabled
            )
        }
    }

    // MARK: - Toggles

    private var toggles: some View {
        NGroup {
            toggleRow("Heated steering wheel", isOn: Binding(
                get: { options.steeringWheel > 0 },
                set: { options.steeringWheel = $0 ? 1 : 0 }
            ))
            toggleRow("Front defrost", isOn: $options.defrost)
            toggleRow("Rear defrost", isOn: $options.rearDefrostEnabled, divider: false)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: isOn) {
                Text(title).font(.system(size: 15)).foregroundStyle(NTheme.text)
            }
            .toggleStyle(NToggleStyle())
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            if divider { Rectangle().fill(NTheme.hairline).frame(height: 1) }
        }
    }

    // MARK: - Duration

    private var duration: some View {
        VStack(alignment: .leading, spacing: 8) {
            NCapsLabel("Run for")
            HStack(spacing: 8) {
                ForEach([10, 15, 20, 30], id: \.self) { minutes in
                    NChip(title: "\(minutes) min", isSelected: options.duration == minutes) {
                        options.duration = minutes
                    }
                }
            }
        }
    }

    // MARK: - Presets

    private var presetChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            NCapsLabel("Presets")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(presets) { preset in
                        NChip(
                            title: "\(preset.name) \(NFormat.temperature(preset.climateOptions.temperature))",
                            isSelected: preset.id == loadedPresetID
                        ) {
                            select(preset)
                        }
                        .fixedSize()
                    }
                    NChip(title: "Edit presets", isSelected: false) {
                        sheetPresentation.show(.climateSettings(vehicle: vehicle))
                    }
                    .fixedSize()
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func select(_ preset: ClimatePreset) {
        for item in presets { item.isSelected = item.id == preset.id }
        loadedPresetID = preset.id
        options = preset.climateOptions
        try? modelContext.save()
    }
}

/// Seat heat / ventilation control: tap the card to cycle
/// Off → Heat 1–3 (→ Cool 1–3), or use the menu for a direct pick.
struct NSeatControl: View {
    let title: String
    @Binding var level: Int
    @Binding var ventilated: Bool

    private var stateText: String {
        guard level > 0 else { return "Off" }
        return ventilated ? "Cool \(level)" : "Heat \(level)"
    }

    var body: some View {
        Menu {
            Button("Off") { set(0, vent: false) }
            Section("Heat") {
                ForEach(1...3, id: \.self) { value in
                    Button("Heat \(value)") { set(value, vent: false) }
                }
            }
            Section("Cool") {
                ForEach(1...3, id: \.self) { value in
                    Button("Cool \(value)") { set(value, vent: true) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(NTheme.textSecondary)
                HStack {
                    Text(stateText)
                        .font(NTheme.display(22))
                        .foregroundStyle(level > 0 ? NTheme.text : NTheme.textSecondary)
                    Spacer()
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
            .nCard(radius: 16, padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(stateText)")
    }

    private func set(_ value: Int, vent: Bool) {
        level = value
        ventilated = value > 0 && vent
    }
}
