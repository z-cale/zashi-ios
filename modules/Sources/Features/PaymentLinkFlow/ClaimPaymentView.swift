//
//  ClaimPaymentView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct ClaimPaymentView: View {
    @Environment(\.colorScheme) var colorScheme
    let store: StoreOf<ClaimPayment>

    public init(store: StoreOf<ClaimPayment>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            switch store.screen {
            case .loading:
                loadingView()
            case .ready:
                readyView()
            case .claiming:
                claimingView()
            case .claimed:
                claimedView()
            case .error:
                errorView()
            }
        }
        .applyScreenBackground()
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Loading

    @ViewBuilder private func loadingView() -> some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
            Text("Loading payment...")
                .zFont(size: 14, style: Design.Text.tertiary)
                .padding(.top, 16)
            Spacer()
        }
    }

    // MARK: - Ready (R1)

    @ViewBuilder private func readyView() -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Text("Someone sent you ZEC!")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                Text("\(store.amount) ZEC")
                    .zFont(.bold, size: 40, style: Design.Text.primary)

                Text("Finalize to sweep these funds\ninto your wallet")
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if let desc = store.description, !desc.isEmpty {
                Text(desc)
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .padding(.bottom, 16)
            }

            ZashiButton("Claim!", type: .ghost) {
                store.send(.claimTapped)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Claiming (R2)

    @ViewBuilder private func claimingView() -> some View {
        VStack(spacing: 0) {
            Spacer()

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .padding(.bottom, 24)

            Text("Claiming \(store.amount) ZEC")
                .zFont(.semiBold, size: 28, style: Design.Text.primary)

            Text("Your coins are being claimed")
                .zFont(size: 14, style: Design.Text.tertiary)
                .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Claimed (Success)

    @ViewBuilder private func claimedView() -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Text.primary.color(colorScheme))
                .padding(.bottom, 16)

            Text("Claimed!")
                .zFont(.semiBold, size: 28, style: Design.Text.primary)

            Text("Your coins were successfully claimed to your wallet!")
                .zFont(size: 14, style: Design.Text.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            Spacer()

            ZashiButton("Close") {
                store.send(.closeTapped)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Error

    @ViewBuilder private func errorView() -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Design.Utility.ErrorRed._600.color(colorScheme))
                .padding(.bottom, 16)

            Text("Failed to claim")
                .zFont(.semiBold, size: 22, style: Design.Text.primary)

            if let error = store.errorMessage {
                Text(error)
                    .zFont(size: 14, style: Design.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)
            }

            Spacer()

            ZashiButton("Close") {
                store.send(.closeTapped)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Placeholder

extension ClaimPayment {
    public static let placeholder = StoreOf<ClaimPayment>(
        initialState: .initial
    ) {
        ClaimPayment()
    }
}
