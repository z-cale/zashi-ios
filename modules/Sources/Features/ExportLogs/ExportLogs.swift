//
//  ExportLogs.swift
//
//
//  Created by Lukáš Korba on 06-20-2024.
//

import ComposableArchitecture

import Generated
import ZcashLightClientKit

// MARK: Alerts

extension AlertState where Action == ExportLogs.Action {
    public static func failed(_ error: ZcashError) -> AlertState {
        AlertState {
            TextState(String(localizable: .exportLogsAlertFailedTitle))
        } message: {
            TextState(String(localizable: .exportLogsAlertFailedMessage(error.detailedMessage)))
        }
    }
}

// MARK: Placeholders

extension ExportLogs.State {
    public static var initial: Self {
        .init()
    }
}
