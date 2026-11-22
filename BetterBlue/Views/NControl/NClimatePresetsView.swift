//
//  NClimatePresetsView.swift
//  N Link
//
//  Climate presets, in the N Link style: pick a preset along the top and
//  edit what climate starts with — name, icon, temperature, seats,
//  steering wheel, defrost and run time. The only place those start
//  settings change; the Climate screen shows them read-only.
//

import BetterBlueKit
import SwiftData
import SwiftUI

struct NClimatePresetsView: View {
    let vehicle: BBVehicle

    @Environment(\.modelContext) private var modelContext
    @State private var editingID: UUID?
    @State private var confirmingDelete = false

    private var unit: Temperature.Units { NFormat.temperatureUnit }
    private var presets: [ClimatePreset] { vehicle.sortedClimatePresets }
    private var preset: ClimatePreset? {
        presets.first { $0.id == editingID } ?? vehicle.activeClimatePreset
    }

    var body: some View {
        NPushedScreen(title: "Presets", subtitle: "What climate starts with") {
            presetChips
            if let preset {
                editor(for: preset)
            }
        }
        .onAppear(perform: createDefaultPresetIfNeeded)
    }

    // MARK: - Preset picker

    private var presetChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(presets) { item in
                    NChip(title: item.name, isSelected: item.id == preset?.id) {
                        withAnimation(.snappy) { editingID = item.id }
                    }
                    .fixedSize()
                }
                Button(action: createPreset) {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                        .foregroundStyle(NTheme.accent)
                        .background(NTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(NTheme.border)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New preset")
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(for preset: ClimatePreset) -> some View {
        let options = preset.climateOptions

        NGroup {
            NRow(title: "Name") {
                TextField("Name", text: Binding(
                    get: { preset.name },
                    set: { preset.name = $0; save() }
                ))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(NTheme.text)
                .submitLabel(.done)
            }
            NRow(title: "Icon", showsDivider: false) {
                HStack(spacing: 6) {
                    ForEach(ClimatePreset.availableIcons, id: \.icon) { option in
                        iconButton(option.icon, name: option.name, selected: preset.iconName == option.icon) {
                            preset.iconName = option.icon
                            save()
                        }
                    }
                }
            }
        }

        NClimateDial(
            temperature: options.displayTemperature(in: unit),
            unit: unit,
            statusText: preset.isSelected ? "Next start" : preset.name
        ) { steps in
            edit(preset) { $0.stepTemperature(by: steps, unit: unit) }
        }

        if vehicle.showsSeatControls {
            NCapsLabel("Front seats")
            HStack(spacing: 10) {
                NSeatControl(title: "Driver", level: options.frontLeftSeat,
                             ventilated: options.frontLeftVentilationEnabled) { level, vent in
                    edit(preset) { $0.frontLeftSeat = level; $0.frontLeftVentilationEnabled = vent }
                }
                NSeatControl(title: "Passenger", level: options.frontRightSeat,
                             ventilated: options.frontRightVentilationEnabled) { level, vent in
                    edit(preset) { $0.frontRightSeat = level; $0.frontRightVentilationEnabled = vent }
                }
            }
            NCapsLabel("Rear seats")
            HStack(spacing: 10) {
                NSeatControl(title: "Left", level: options.rearLeftSeat,
                             ventilated: options.rearLeftVentilationEnabled) { level, vent in
                    edit(preset) { $0.rearLeftSeat = level; $0.rearLeftVentilationEnabled = vent }
                }
                NSeatControl(title: "Right", level: options.rearRightSeat,
                             ventilated: options.rearRightVentilationEnabled) { level, vent in
                    edit(preset) { $0.rearRightSeat = level; $0.rearRightVentilationEnabled = vent }
                }
            }
        }

        NGroup {
            ForEach([NClimateItem.steeringWheel, .frontDefrost, .rearDefrost], id: \.self) { item in
                NClimateToggleRow(
                    title: item.title,
                    isOn: Binding(
                        get: { preset.climateOptions.isOn(item) },
                        set: { on in edit(preset) { $0.setOn(item, on) } }
                    ),
                    divider: item != .rearDefrost || showsDuration
                )
            }
            if showsDuration {
                NRow(title: "Run for", showsDivider: false) {
                    Menu {
                        Picker("Run for", selection: Binding(
                            get: { preset.climateOptions.duration },
                            set: { minutes in edit(preset) { $0.duration = minutes } }
                        )) {
                            ForEach([5, 10, 15, 20, 25, 30], id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                    } label: {
                        Text("\(options.duration) min ›")
                            .foregroundStyle(NTheme.textSecondary)
                            .frame(minHeight: 44)
                    }
                }
            }
        }

        if preset.isSelected {
            NCapsLabel("Climate starts with this preset")
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            Button("Use for next start") { select(preset) }
                .buttonStyle(.nPrimary)
        }

        if presets.count > 1 {
            Button("Delete preset", role: .destructive) { confirmingDelete = true }
                .buttonStyle(.nSecondary)
                .confirmationDialog(
                    "Delete \(preset.name)?",
                    isPresented: $confirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) { delete(preset) }
                    Button("Cancel", role: .cancel) {}
                }
        }
    }

    private var showsDuration: Bool { vehicle.showClimateDuration || vehicle.generation >= 3 }

    private func iconButton(_ icon: String, name: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(selected ? NTheme.onAccent : NTheme.text)
                .background(selected ? NTheme.accent : NTheme.cardRaised,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Changes

    private func edit(_ preset: ClimatePreset, _ change: (inout ClimateOptions) -> Void) {
        var options = preset.climateOptions
        change(&options)
        preset.climateOptions = options
        save()
    }

    private func save() {
        try? modelContext.save()
    }

    private func select(_ preset: ClimatePreset) {
        for item in presets { item.isSelected = item.id == preset.id }
        save()
    }

    private func createPreset() {
        let preset = ClimatePreset(
            name: "Preset \(presets.count + 1)",
            iconName: ClimatePreset.availableIcons.randomElement()?.icon ?? "fan",
            climateOptions: ClimateOptions(preferredUnits: unit),
            isSelected: false,
            vehicle: vehicle
        )
        preset.sortOrder = (presets.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(preset)
        save()
        withAnimation(.snappy) { editingID = preset.id }
    }

    private func delete(_ preset: ClimatePreset) {
        guard presets.count > 1 else { return }
        let wasSelected = preset.isSelected
        let remaining = presets.filter { $0.id != preset.id }
        editingID = remaining.first?.id
        modelContext.delete(preset)
        if wasSelected { remaining.first?.isSelected = true }
        save()
    }

    private func createDefaultPresetIfNeeded() {
        guard presets.isEmpty else { return }
        let preset = ClimatePreset(
            name: "Default",
            iconName: "fan",
            climateOptions: ClimateOptions(preferredUnits: unit),
            isSelected: true,
            vehicle: vehicle
        )
        modelContext.insert(preset)
        save()
    }
}
