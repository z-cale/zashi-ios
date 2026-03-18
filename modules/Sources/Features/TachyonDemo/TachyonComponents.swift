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
                .zFont(size: 14, style: Design.Text.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationBarBackButtonHidden(true)
        .applyScreenBackground()
    }
}

// MARK: - Success Screen

struct TachyonSuccessView: View {
    let store: StoreOf<TachyonDemo>
    let title: String
    let subtitle: String

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.green)

                Text(title)
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .padding(.top, 16)

                Text(subtitle)
                    .zFont(size: 14, style: Design.Text.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                ZashiButton("Done") {
                    store.send(.backToFlowPicker)
                }
                .padding(.bottom, 32)
            }
            .screenHorizontalPadding()
            .navigationBarBackButtonHidden(true)
            .applyScreenBackground()
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
            RoundedRectangle(cornerRadius: Design.Radius._md)
                .fill(Color(.tertiarySystemFill))
                .frame(width: size, height: size)
                .overlay {
                    Text("QR")
                        .zFont(size: 14, style: Design.Text.support)
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
    var isOverBalance: Bool = false

    private static let quips = [
        "Insufficient funds — the one thing we didn't mock",
        "That amount fails the range proof",
        "Nice try — the commitment won't bind to that",
        "Not even a zero-knowledge proof can hide this overdraft",
    ]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("Balance:")
                    .zFont(size: 14, style: Design.Text.tertiary)
                Text("\(MockData.mockBalance) ZEC")
                    .zFont(.medium, size: 14, style: isOverBalance ? Design.Text.error : Design.Text.primary)
            }

            if isOverBalance {
                Text(Self.quips[Int.random(in: 0..<Self.quips.count)])
                    .zFont(.medium, size: 12, style: Design.Text.error)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isOverBalance)
    }
}

// MARK: - Truncated Key

struct TruncatedKeyView: View {
    let label: String
    let key: MockPaymentKey

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .zFont(size: 14, style: Design.Text.tertiary)
            Text(key.truncated)
                .zFont(fontFamily: .robotoMono, size: 14, style: Design.Text.primary)
        }
    }
}

// MARK: - Via Relay Badge

struct ViaRelayBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
            Text("via relay")
                .zFont(.medium, size: 12, color: .orange)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Demo Banner

struct DemoBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flask.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text("Prototype — all crypto is mocked")
                .zFont(size: 12, style: Design.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - Confirm Row

struct ConfirmRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .zFont(size: 14, style: Design.Text.tertiary)
            Spacer()
            Text(value)
                .zFont(fontFamily: .robotoMono, size: 14, style: Design.Text.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - Mock Scan Placeholder

struct MockScanView: View {
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: Design.Radius._2xl)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .zForegroundColor(Design.Surfaces.strokePrimary)
            .frame(width: 240, height: 240)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .zForegroundColor(Design.Text.support)
                    Text(label)
                        .zFont(size: 14, style: Design.Text.support)
                }
            }
    }
}

// MARK: - Role Colors

enum RoleColor {
    static func color(for role: TachyonDemo.State.Role) -> Color {
        switch role {
        case .recipient: return .green
        case .sender: return .blue
        }
    }

    static func tint(for role: TachyonDemo.State.Role) -> Color {
        color(for: role).opacity(0.04)
    }
}

// MARK: - Role Banner

struct RoleBanner: View {
    let role: TachyonDemo.State.Role

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(RoleColor.color(for: role))
                .frame(width: 8, height: 8)

            Text(role.label)
                .zFont(.medium, size: 12, color: RoleColor.color(for: role))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoleColor.color(for: role).opacity(0.08))
    }
}

// MARK: - Role Legend

struct RoleLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            legendItem(role: .recipient)
            legendItem(role: .sender)
        }
    }

    private func legendItem(role: TachyonDemo.State.Role) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(RoleColor.color(for: role))
                .frame(width: 8, height: 8)
            Text(role == .recipient ? "Recipient" : "Sender")
                .zFont(size: 12, style: Design.Text.tertiary)
        }
    }
}

// MARK: - Role-Tinted Screen Background

struct RoleTintModifier: ViewModifier {
    let role: TachyonDemo.State.Role?

    func body(content: Content) -> some View {
        content
            .background {
                if let role {
                    RoleColor.tint(for: role)
                        .ignoresSafeArea()
                }
            }
    }
}

extension View {
    func roleTint(_ role: TachyonDemo.State.Role?) -> some View {
        modifier(RoleTintModifier(role: role))
    }
}
