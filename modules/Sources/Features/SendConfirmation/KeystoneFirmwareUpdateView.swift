//
//  KeystoneFirmwareUpdateView.swift
//  Zashi
//
//  Shown when a signed PCZT comes back from Keystone but the firmware
//  version stamp (from `global.proprietary["keystone:fw_version"]`) is below
//  Zashi's required minimum, or absent (legacy firmware). Blocks broadcast
//  until the user updates their Keystone.
//

import SwiftUI
import ComposableArchitecture

import Generated
import UIComponents
import Utils

public struct KeystoneFirmwareUpdateView: View {
    @Perception.Bindable var store: StoreOf<SendConfirmation>

    public init(store: StoreOf<SendConfirmation>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                // Reuse the existing failure illustration set to stay within
                // the same visual language as PreSendingFailureView. A
                // dedicated Keystone-update illustration is a follow-up.
                store.failureIlustration
                    .resizable()
                    .frame(width: 148, height: 148)

                Text(String(localizable: .keystoneFirmwareUpdateTitle))
                    .zFont(.semiBold, size: 28, style: Design.Text.primary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)

                Text(bodyCopy)
                    .zFont(size: 14, style: Design.Text.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.5)
                    .screenHorizontalPadding()
                    .padding(.top, 12)

                Text(String(localizable: .keystoneFirmwareUpdateHowToUpdate))
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.5)
                    .screenHorizontalPadding()
                    .padding(.top, 16)

                Spacer()

                ZashiButton(String(localizable: .keystoneFirmwareUpdateDismissButton)) {
                    store.send(.dismissKeystoneFirmwareUpdate)
                }
                .padding(.bottom, 24)
            }
            .navigationBarBackButtonHidden()
            .padding(.vertical, 1)
            .screenHorizontalPadding()
            .applyFailureScreenBackground()
        }
    }

    /// The body copy varies on whether the firmware reported a version.
    ///
    /// - `detected != nil`: "This feature requires Keystone firmware X.Y.Z or
    ///   newer. Your device is on A.B.C."
    /// - `detected == nil`: "Your Keystone does not report its firmware
    ///   version. Please update to the latest version to continue."
    private var bodyCopy: String {
        if let detected = store.detectedKeystoneFirmware {
            return String(
                localizable: .keystoneFirmwareUpdateBodyOutdated(
                    store.requiredKeystoneFirmware.displayString,
                    detected.displayString
                )
            )
        } else {
            return String(localizable: .keystoneFirmwareUpdateBodyLegacy)
        }
    }
}

#Preview {
    NavigationView {
        KeystoneFirmwareUpdateView(store: SendConfirmation.initial)
    }
}
