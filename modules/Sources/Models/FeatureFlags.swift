//
//  FeatureFlags.swift
//  Zashi
//
//  Created by Lukáš Korba on 10-15-2024.
//

public struct FeatureFlags: Equatable {
    public let addUAtoMemo: Bool
    public let appLaunchBiometric: Bool
    public let batchVoting: Bool
    public let flexa: Bool
    public let selectText: Bool

    public init(
        addUAtoMemo: Bool = false,
        appLaunchBiometric: Bool = true,
        batchVoting: Bool = false,
        flexa: Bool = true,
        selectText: Bool = true
    ) {
        self.addUAtoMemo = addUAtoMemo
        self.appLaunchBiometric = appLaunchBiometric
        self.batchVoting = batchVoting
        self.flexa = flexa
        self.selectText = selectText
    }
}

public extension FeatureFlags {
    static let initial = FeatureFlags()
}
