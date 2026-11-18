//
//  VehicleCommandRunner.swift
//  N Link
//
//  Runs vehicle commands for the N Link screens: sends the command,
//  waits for the car to confirm, and keeps per-action busy/status state
//  plus a single error banner. Ported from PersistentVehicleSheet so the
//  new screens behave the same way the old sheet did.
//

import BetterBlueKit
import Foundation
import Observation
import SwiftData
import WidgetKit

@MainActor
@Observable
final class VehicleCommandRunner {
    enum Action: Hashable {
        case refresh, lock, climate, charge, limits
    }

    struct Banner: Identifiable {
        let id = UUID()
        let message: String
        let apiError: APIError?
        let actionError: ActionError?
    }

    let vehicle: BBVehicle
    private(set) var busy: Set<Action> = []
    private(set) var statusText: [Action: String] = [:]
    var banner: Banner?
    /// Lock state the in-flight lock command is driving toward, so the
    /// spinner stays on the button that was tapped even if the car's
    /// reported state flips mid-command.
    private(set) var pendingLockTarget: Bool?

    init(vehicle: BBVehicle) {
        self.vehicle = vehicle
    }

    func isBusy(_ action: Action) -> Bool { busy.contains(action) }

    // MARK: - Refresh

    func refresh(modelContext: ModelContext, force: Bool = true) async {
        guard let account = vehicle.account, !isBusy(.refresh) else { return }
        begin(.refresh, "Refreshing")
        defer { end(.refresh) }
        do {
            try await account.fetchAndUpdateVehicleStatus(
                for: vehicle,
                modelContext: modelContext,
                cached: !force,
                forceVehicleListRefresh: false
            )
            banner = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            handle(error, action: "Refresh \(vehicle.displayName)")
        }
    }

    // MARK: - Lock

    func setLocked(_ locked: Bool, modelContext: ModelContext) async {
        guard let account = vehicle.account, !isBusy(.lock) else { return }
        begin(.lock, locked ? "Locking" : "Unlocking")
        pendingLockTarget = locked
        defer {
            end(.lock)
            pendingLockTarget = nil
        }
        do {
            if locked {
                try await account.lockVehicle(vehicle, modelContext: modelContext)
            } else {
                try await account.unlockVehicle(vehicle, modelContext: modelContext)
            }
            let target: VehicleStatus.LockStatus = locked ? .locked : .unlocked
            try await vehicle.waitForStatusChange(
                modelContext: modelContext,
                condition: { $0.lockStatus == target },
                statusMessageUpdater: updater(for: .lock)
            )
        } catch {
            handle(error, action: locked ? "Lock \(vehicle.displayName)" : "Unlock \(vehicle.displayName)")
        }
    }

    // MARK: - Climate

    func startClimate(
        options: ClimateOptions,
        presetName: String?,
        presetIcon: String?,
        modelContext: ModelContext
    ) async {
        guard let account = vehicle.account, !isBusy(.climate) else { return }
        begin(.climate, "Starting climate")
        defer { end(.climate) }
        do {
            try await account.startClimate(
                vehicle,
                options: options,
                modelContext: modelContext,
                presetName: presetName,
                presetIcon: presetIcon
            )
            try await vehicle.waitForStatusChange(
                modelContext: modelContext,
                condition: { $0.climateStatus.airControlOn },
                statusMessageUpdater: updater(for: .climate)
            )
        } catch {
            handle(error, action: "Start climate")
        }
    }

    func stopClimate(modelContext: ModelContext) async {
        guard let account = vehicle.account, !isBusy(.climate) else { return }
        begin(.climate, "Stopping climate")
        defer { end(.climate) }
        do {
            try await account.stopClimate(vehicle, modelContext: modelContext)
            try? await account.fetchAndUpdateVehicleStatus(for: vehicle, modelContext: modelContext, cached: false)
            try await vehicle.waitForStatusChange(
                modelContext: modelContext,
                condition: { !$0.climateStatus.airControlOn },
                statusMessageUpdater: updater(for: .climate)
            )
        } catch {
            handle(error, action: "Stop climate")
        }
    }

    // MARK: - Charging

    func setCharging(_ start: Bool, modelContext: ModelContext) async {
        guard let account = vehicle.account, !isBusy(.charge) else { return }
        begin(.charge, start ? "Starting charge" : "Stopping charge")
        defer { end(.charge) }
        do {
            if start {
                try await account.startCharge(vehicle, modelContext: modelContext)
            } else {
                try await account.stopCharge(vehicle, modelContext: modelContext)
                try? await account.fetchAndUpdateVehicleStatus(for: vehicle, modelContext: modelContext, cached: false)
            }
            // Charging state propagates slowest — give it a longer window.
            try await vehicle.waitForStatusChange(
                modelContext: modelContext,
                condition: { $0.evStatus?.charging == start },
                statusMessageUpdater: updater(for: .charge),
                maxAttempts: 5,
                retryDelaySeconds: 15
            )
        } catch {
            handle(error, action: start ? "Start charging" : "Stop charging")
        }
    }

    func setChargeLimits(ac: Int, dc: Int, modelContext: ModelContext) async {
        guard let account = vehicle.account, !isBusy(.limits) else { return }
        begin(.limits, "Saving limits")
        defer { end(.limits) }
        do {
            try await account.setTargetSOC(vehicle, acLevel: ac, dcLevel: dc, modelContext: modelContext)
            try await vehicle.waitForStatusChange(
                modelContext: modelContext,
                condition: { status in
                    guard let ev = status.evStatus else { return false }
                    return Int(ev.targetSocAC ?? -1) == ac && Int(ev.targetSocDC ?? -1) == dc
                },
                statusMessageUpdater: updater(for: .limits)
            )
        } catch {
            handle(error, action: "Set charge limits")
        }
    }

    // MARK: - State helpers

    private func begin(_ action: Action, _ text: String) {
        busy.insert(action)
        statusText[action] = text
    }

    private func end(_ action: Action) {
        busy.remove(action)
        statusText[action] = nil
    }

    private func updater(for action: Action) -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor in
                guard let self, self.busy.contains(action) else { return }
                self.statusText[action] = message
            }
        }
    }

    private func handle(_ error: Error, action: String) {
        if error is CancellationError { return }
        // Accepted but not yet confirmed: not a failure (issue #83).
        if let apiError = error as? APIError, apiError.errorType == .statusVerificationTimeout {
            BBLogger.info(.app, "\(action): command sent, confirmation pending")
            return
        }
        let apiError = error as? APIError
        let message: String
        if let apiError {
            message = Self.friendlyMessage(for: apiError, action: action)
        } else {
            message = "\(action) failed: \(error.localizedDescription)"
        }
        let actionError: ActionError? = apiError?.errorType == .requiresMFA
            ? nil
            : ActionError(action: action, error: error, accountId: vehicle.account?.id)
        banner = Banner(message: message, apiError: apiError, actionError: actionError)
    }

    static func friendlyMessage(for error: APIError, action: String) -> String {
        switch error.errorType {
        case .invalidCredentials: return "Login expired — check account settings"
        case .invalidPin: return "PIN validation failed — check account settings"
        case .invalidVehicleSession: return "Vehicle session expired — trying to reconnect"
        case .serverError: return "Server temporarily unavailable — try again later"
        case .concurrentRequest: return "Another request in progress — try again shortly"
        case .failedRetryLogin: return "Unable to reconnect — check account settings"
        case .requiresMFA: return "\(error.message) — tap to verify"
        case .kiaInvalidRequest, .featureNotSupported: return error.message
        case .regionNotSupported: return "This region is not yet supported"
        case .statusVerificationTimeout: return "Command sent — waiting for the car to confirm"
        case .general:
            if error.message.localizedCaseInsensitiveContains("timeout")
                || error.message.localizedCaseInsensitiveContains("timed out") {
                return "Vehicle not responding — try again later"
            }
            if error.message.localizedCaseInsensitiveContains("network") {
                return "Network connection issue — check your internet"
            }
            return "\(action) failed — check connection and try again"
        }
    }
}
