//
//  VehicleInfoComponents.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 9/8/25.
//

import BetterBlueKit
import SwiftData
import SwiftUI
import WidgetKit

struct VehicleBasicInfoSection: View {
    let bbVehicle: BBVehicle
    @Binding var showingCopiedMessage: Bool

    var body: some View {
        Section("Basic Information") {
            HStack {
                Text("Original Name")
                Spacer()
                Text(bbVehicle.model)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Brand")
                Spacer()
                if let account = bbVehicle.account {
                    Text(account.brandEnum.displayName)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("VIN")
                Spacer()
                Text(bbVehicle.vin)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                copyVINToClipboard()
            }
            VehicleFuelTypeOverride(bbVehicle: bbVehicle)
        }
    }

    private func copyVINToClipboard() {
        UIPasteboard.general.string = bbVehicle.vin

        withAnimation(.easeInOut(duration: 0.3)) {
            showingCopiedMessage = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingCopiedMessage = false
            }
        }
    }
}

/// Plain vehicle-type selector. Reads the effective `fuelType` (which
/// is the override when pinned, otherwise the inferred value), and any
/// change pins it as an override. The "automatic vs override" detail
/// is intentionally hidden — from the user's perspective it's just
/// "what kind of car is this?".
struct VehicleFuelTypeOverride: View {
    @Bindable var bbVehicle: BBVehicle
    @Environment(\.modelContext) private var modelContext

    private static let allTypes: [FuelType] = [.gas, .electric, .phev]

    private static func label(for type: FuelType) -> String {
        switch type {
        case .gas: "Gas"
        case .electric: "Electric"
        case .phev: "Plug-in Hybrid"
        }
    }

    private var selection: Binding<FuelType> {
        Binding(
            get: { bbVehicle.fuelType },
            set: { newValue in
                bbVehicle.fuelTypeOverride = newValue
                // Clear off-axis ranges so the UI updates immediately;
                // updateStatus already gates writes on the effective
                // fuelType, but stale data set BEFORE the change
                // wouldn't disappear on its own.
                bbVehicle.normalizeRangesForCurrentFuelType()
                do {
                    try modelContext.save()
                    // Widgets/Live Activities cache range visibility,
                    // so reload timelines too.
                    WidgetCenter.shared.reloadAllTimelines()
                } catch {
                    BBLogger.error(.app, "VehicleFuelTypeOverrideSection: failed to save type: \(error)")
                }
            }
        )
    }

    var body: some View {
            Picker("Vehicle Type", selection: selection) {
                ForEach(Self.allTypes, id: \.self) { type in
                    Text(Self.label(for: type)).tag(type)
                }
            }
    }
}
