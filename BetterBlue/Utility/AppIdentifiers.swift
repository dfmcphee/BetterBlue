//
//  AppIdentifiers.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 8/30/26.
//

import Foundation

/// App Group and iCloud container identifiers, injected from build settings
/// (Config/Shared.xcconfig, overridable via Config/Local.xcconfig) through
/// each target's Info.plist so forks can build with their own team without
/// editing source.
enum AppIdentifiers {
    nonisolated static let appGroup = infoPlistValue(
        for: "BBAppGroupIdentifier",
        fallback: "group.com.dfmcphee.ncontrol"
    )

    nonisolated static let iCloudContainer = infoPlistValue(
        for: "BBICloudContainerIdentifier",
        fallback: "iCloud.com.dfmcphee.NControl"
    )

    /// Host of the Live Activity wake-up Worker, or nil when none is
    /// configured (background refresh of Live Activities is then off).
    nonisolated static let liveActivityHost: String? = {
        let value = infoPlistValue(for: "BBLiveActivityHost", fallback: "")
        return value.isEmpty ? nil : value
    }()

    private nonisolated static func infoPlistValue(for key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else {
            return fallback
        }
        return value
    }
}
