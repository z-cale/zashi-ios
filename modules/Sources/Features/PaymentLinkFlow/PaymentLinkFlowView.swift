//
//  PaymentLinkFlowView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

public struct PaymentLinkFlowView: View {
    @Environment(\.colorScheme) var colorScheme
    let store: StoreOf<PaymentLinkFlow>

    public init(store: StoreOf<PaymentLinkFlow>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            switch store.screen {
            case .enterAmount:
                enterAmountView()
            case .creating:
                processingView(title: "Creating Payment Link...", subtitle: "Funding ephemeral address")
            case .linkReady:
                linkReadyView()
            case .revoking:
                processingView(title: "Revoking Payment...", subtitle: "Sweeping funds back to your wallet")
            case .revoked:
                resultView(
                    title: "Payment Revoked",
                    subtitle: "Funds swept back to your wallet. The link is now invalid."
                )
            }
        }
        .applyScreenBackground()
        .screenTitle("ZIP-324")
    }

    // MARK: - Enter Amount

    @ViewBuilder private func enterAmountView() -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Send a Friend ZEC")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                Text("They'll receive a link to claim the funds")
                    .zFont(size: 14, style: Design.Text.tertiary)
            }
            .padding(.top, 24)

            Spacer()

            // Amount display
            HStack(spacing: 4) {
                Text(store.amount.isEmpty ? "0" : store.amount)
                    .zFont(.bold, size: 42, style: Design.Text.primary)
                Text("ZEC")
                    .zFont(size: 42, style: Design.Text.tertiary)
            }

            Text("Balance: \(store.balance) ZEC")
                .zFont(size: 14, style: Design.Text.tertiary)
                .padding(.top, 4)

            if store.isOverBalance {
                Text("Amount exceeds balance")
                    .zFont(size: 14, style: Design.Utility.ErrorRed._600)
                    .padding(.top, 4)
            }

            Spacer()

            // Numpad
            numpad()
                .padding(.horizontal, 24)

            // Create button
            ZashiButton("Create Payment Link") {
                store.send(.createTapped)
            }
            .disabled(!store.isValidAmount)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Link Ready

    @ViewBuilder private func linkReadyView() -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Payment Link Ready")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)

                Text("\(store.paymentLink?.amount ?? store.amount) ZEC")
                    .zFont(.bold, size: 32, style: Design.Text.primary)
            }

            // QR code
            if !store.qrContent.isEmpty, let qrImage = generateQR(from: store.qrContent, size: 200) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .cornerRadius(12)
                    .padding(.top, 24)
            }

            Text("Send this to your friend.\nThey can claim it in the Zodl app.")
                .zFont(size: 14, style: Design.Text.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 16)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                ZashiButton("Share Link") {
                    store.send(.shareLinkTapped)
                }

                ZashiButton("Share QR Code", type: .ghost) {
                    store.send(.shareQRTapped)
                }

                ZashiButton("Revoke Payment", type: .destructive1) {
                    store.send(.revokeTapped)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: Binding(
            get: { store.isSharePresented },
            set: { newValue in
                if !newValue { store.send(.shareFinished) }
            }
        )) {
            if !store.qrContent.isEmpty {
                ShareSheet(activityItems: [store.qrContent])
            }
        }
    }

    // MARK: - Processing

    @ViewBuilder private func processingView(title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .padding(.bottom, 24)

            Text(title)
                .zFont(.semiBold, size: 28, style: Design.Text.primary)

            Text(subtitle)
                .zFont(size: 14, style: Design.Text.tertiary)
                .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Result

    @ViewBuilder private func resultView(title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Text.primary.color(colorScheme))
                .padding(.bottom, 16)

            Text(title)
                .zFont(.semiBold, size: 28, style: Design.Text.primary)

            Text(subtitle)
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

    // MARK: - Numpad

    @ViewBuilder private func numpad() -> some View {
        let keys: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            [".", "0", "⌫"]
        ]

        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKeyPress(key)
                        } label: {
                            Text(key)
                                .zFont(.medium, size: 32, style: Design.Text.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func handleKeyPress(_ key: String) {
        var current = store.amount
        if key == "⌫" {
            if !current.isEmpty {
                current.removeLast()
            }
        } else if key == "." {
            if !current.contains(".") {
                current += current.isEmpty ? "0." : "."
            }
        } else {
            // Limit decimal places to 8
            if let dotIndex = current.firstIndex(of: ".") {
                let decimals = current[current.index(after: dotIndex)...]
                if decimals.count >= 8 { return }
            }
            current += key
        }
        store.send(.amountChanged(current))
    }
}

// MARK: - QR Generator

extension PaymentLinkFlowView {
    func generateQR(from string: String, size: CGFloat) -> UIImage? {
        guard !string.isEmpty,
              let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.size.width
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Placeholder

extension PaymentLinkFlow {
    public static let placeholder = StoreOf<PaymentLinkFlow>(
        initialState: .initial
    ) {
        PaymentLinkFlow()
    }
}
