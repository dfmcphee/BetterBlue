//
//  NClimateView.swift
//  N Link
//
//  Pre-conditioning. While climate is off: the target temperature, the
//  preset to start with and a read-only list of what it turns on (edited
//  in the preset editor). While it runs: what the car is doing, as live
//  controls that re-send start with the change.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NClimateView: View {
    let vehicle: BBVehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(VehicleCommandRunner.self) private var runner

    /// Start settings when the vehicle has no preset to hold them.
    @State private var localOptions: ClimateOptions?
    @State private var showingPresets = false

    private var unit: Temperature.Units { NFormat.temperatureUnit }
    private var isOn: Bool { vehicle.isClimateOn }
    private var presets: [ClimatePreset] { vehicle.sortedClimatePresets }
    private var activePreset: ClimatePreset? { vehicle.activeClimatePreset }

    /// What the next start will use: the selected preset.
    private var startOptions: ClimateOptions {
        activePreset?.climateOptions ?? localOptions ?? ClimateOptions(preferredUnits: unit)
    }

    /// What climate is doing now, or what a live change is driving toward.
    private var liveOptions: ClimateOptions {
        runner.pendingClimate?.options ?? vehicle.runningClimateOptions
    }

    private var isSending: Bool { runner.isBusy(.climate) || runner.isBusy(.climateAdjust) }

    var body: some View {
        NPushedScreen(title: "Climate", subtitle: subtitle) {
            dial
            if isOn { runningNow } else { startsWith }
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
                            options: startOptions,
                            presetName: activePreset?.name,
                            presetIcon: activePreset?.iconName,
                            modelContext: modelContext
                        )
                    }
                }
            }
            .disabled(runner.isBusy(.climateAdjust))
        }
        .navigationDestination(isPresented: $showingPresets) {
            NClimatePresetsView(vehicle: vehicle)
        }
    }

    private var subtitle: String {
        if isOn, let temp = vehicle.climateStatus?.temperature {
            return "Running · set to \(NFormat.temperature(temp))"
        }
        return "Off · \(NFormat.updated(vehicle.lastUpdated).lowercased())"
    }

    private var startTitle: String {
        vehicle.showClimateDuration ? "Start climate · \(startOptions.duration) min" : "Start climate"
    }

    // MARK: - Dial

    @ViewBuilder
    private var dial: some View {
        if isOn, let temp = vehicle.climateStatus?.temperature {
            let value = temp.units.convert(temp.value, to: unit)
            NClimateDial(
                temperature: unit == .celsius ? (value * 2).rounded() / 2 : value.rounded(),
                unit: unit,
                statusText: "Running",
                statusIsLive: true,
                isLocked: true,
                label: "Set to"
            ) { _ in }
        } else {
            NClimateDial(
                temperature: startOptions.displayTemperature(in: unit),
                unit: unit,
                statusText: startOptions.climate ? "Ready to start" : "Fan off"
            ) { steps in
                editStartOptions { $0.stepTemperature(by: steps, unit: unit) }
            }
        }
    }

    /// The dial edits the selected preset's temperature, as the preset
    /// chips show it.
    private func editStartOptions(_ change: (inout ClimateOptions) -> Void) {
        var updated = startOptions
        change(&updated)
        if let activePreset {
            activePreset.climateOptions = updated
            try? modelContext.save()
        } else {
            localOptions = updated
        }
    }

    // MARK: - Off: starts with

    private var startsWith: some View {
        VStack(alignment: .leading, spacing: 10) {
            NCapsLabel("Starts with")
            if presets.count > 1 { presetChips }
            NClimateStartsWith(
                options: startOptions,
                showsSeats: vehicle.showsSeatControls,
                showsDuration: vehicle.showClimateDuration
            ) {
                Button {
                    showingPresets = true
                } label: {
                    NRow(title: presets.isEmpty ? "Set up presets" : "Edit presets", showsDivider: false) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var presetChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    NChip(
                        title: "\(preset.name) \(NFormat.temperature(preset.climateOptions.temperature))",
                        isSelected: preset.id == activePreset?.id
                    ) {
                        for item in presets { item.isSelected = item.id == preset.id }
                        try? modelContext.save()
                    }
                    .fixedSize()
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - On: running now

    private var runningNow: some View {
        VStack(alignment: .leading, spacing: 10) {
            NCapsLabel("Running now", color: NTheme.accent)
            if vehicle.showsSeatControls {
                HStack(spacing: 10) {
                    seat(.driverSeat, level: liveOptions.frontLeftSeat, ventilated: liveOptions.frontLeftVentilationEnabled)
                    seat(.passengerSeat, level: liveOptions.frontRightSeat, ventilated: liveOptions.frontRightVentilationEnabled)
                }
            }
            NGroup {
                toggle(.steeringWheel)
                toggle(.frontDefrost)
                toggle(.rearDefrost, divider: false)
            }
            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(NTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        if let pending = runner.pendingClimate {
            return "\(runner.statusText[.climateAdjust] ?? "Sending to car") · \(pending.item.title.lowercased())"
        }
        return "Changes are sent to the car and can take a minute to reach it."
    }

    private func toggle(_ item: NClimateItem, divider: Bool = true) -> some View {
        NClimateToggleRow(
            title: item.title,
            isOn: Binding(
                get: { liveOptions.isOn(item) },
                set: { on in adjust(item) { $0.setOn(item, on) } }
            ),
            isBusy: runner.pendingClimate?.item == item,
            divider: divider
        )
        .disabled(isSending)
    }

    private func seat(_ item: NClimateItem, level: Int, ventilated: Bool) -> some View {
        NSeatControl(
            title: item.title,
            level: level,
            ventilated: ventilated,
            isBusy: runner.pendingClimate?.item == item
        ) { newLevel, newVentilated in
            adjust(item) { options in
                if item == .driverSeat {
                    options.frontLeftSeat = newLevel
                    options.frontLeftVentilationEnabled = newVentilated
                } else {
                    options.frontRightSeat = newLevel
                    options.frontRightVentilationEnabled = newVentilated
                }
            }
        }
        .disabled(isSending)
    }

    private func adjust(_ item: NClimateItem, _ change: (inout ClimateOptions) -> Void) {
        var updated = liveOptions
        change(&updated)
        guard updated != liveOptions else { return }
        Task { await runner.adjustClimate(item, to: updated, modelContext: modelContext) }
    }
}
