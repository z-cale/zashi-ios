import SwiftUI
import ComposableArchitecture
import Generated
import UIComponents

// MARK: - Processing Screen

struct TachyonProcessingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Success Screen

struct TachyonSuccessView: View {
    let store: StoreOf<TachyonDemo>
    let title: String
    let subtitle: String

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text(title)
                    .font(.title2.weight(.bold))

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    store.send(.backToFlowPicker)
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarBackButtonHidden(true)
        }
    }
}

// MARK: - Mock QR Code View

struct TachyonQRCodeView: View {
    let content: String
    let size: CGFloat

    init(content: String, size: CGFloat = 200) {
        self.content = content
        self.size = size
    }

    var body: some View {
        if let image = generateQR(from: content) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemFill))
                .frame(width: size, height: size)
                .overlay {
                    Text("QR")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func generateQR(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii),
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

// MARK: - Mock Balance

struct MockBalanceView: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Balance:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(MockData.mockBalance) ZEC")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Truncated Key

struct TruncatedKeyView: View {
    let label: String
    let key: MockPaymentKey

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(key.truncated)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Via Relay Badge

struct ViaRelayBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption2)
            Text("via relay")
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
    }
}
