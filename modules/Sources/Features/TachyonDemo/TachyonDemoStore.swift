import ComposableArchitecture
import CoreGraphics
import Foundation

@Reducer
public struct TachyonDemo {
    @Dependency(\.mainQueue) var mainQueue

    private enum CancelID {
        case simulatedDelay
        case qrGeneration
    }

    // MARK: - State

    @ObservableState
    public struct State: Equatable {
        public enum Screen: Equatable {
            case flowPicker

            // Perspective switch
            case switchTo(Perspective)

            // Flow 1: Payment Request
            case prRecipientCreate
            case prRecipientShowQR
            case prSenderConfirm
            case prSenderProcessing
            case prRecipientReceived

            // Flow 2A: Payment Link (onboarding)
            case plSenderEnterAmount
            case plSenderShare          // share sheet
            case plSenderRevoking
            case plSenderRevoked
            case plOutsideMessageReceived  // mock: iMessage with link
            case plOutsideInstallApp       // mock: App Store install
            case plRecipientClaim
            case plRecipientFinalizing
            case plRecipientDone

            // Flow 2B: Local Cash (QR handoff)
            case cashSenderEnterAmount
            case cashSenderShowQR
            case cashSenderRevoking
            case cashSenderRevoked
            case cashOutsideCameraScan     // mock: camera app scanning QR
            case cashOutsideInstallApp     // mock: App Store install
            case cashRecipientClaim
            case cashRecipientFinalizing
            case cashRecipientDone

            // Flow 3: Public Payment
            case ppRecipientRegister
            case ppRecipientRegistering
            case ppRecipientShowURL
            case ppSenderEnterAmount
            case ppSenderConfirm
            case ppSenderProcessing
            case ppRecipientCheckRelay
            case ppRecipientChecking
            case ppRecipientPaymentsArrived

            public var role: Role? {
                switch self {
                case .flowPicker, .switchTo,
                     .plOutsideMessageReceived, .plOutsideInstallApp,
                     .cashOutsideCameraScan, .cashOutsideInstallApp:
                    return nil
                case .prRecipientCreate, .prRecipientShowQR, .prRecipientReceived,
                     .plRecipientClaim, .plRecipientFinalizing, .plRecipientDone,
                     .cashRecipientClaim, .cashRecipientFinalizing, .cashRecipientDone,
                     .ppRecipientRegister, .ppRecipientRegistering, .ppRecipientShowURL,
                     .ppRecipientCheckRelay, .ppRecipientChecking, .ppRecipientPaymentsArrived:
                    return .recipient
                case .prSenderConfirm, .prSenderProcessing,
                     .plSenderEnterAmount, .plSenderShare, .plSenderRevoking, .plSenderRevoked,
                     .cashSenderEnterAmount, .cashSenderShowQR, .cashSenderRevoking, .cashSenderRevoked,
                     .ppSenderEnterAmount, .ppSenderConfirm, .ppSenderProcessing:
                    return .sender
                }
            }
        }

        public enum Perspective: Equatable {
            case sender
            case recipient
            case recipientOffline
            case outsideApp

            public var title: String {
                switch self {
                case .sender: return "Sender's Device"
                case .recipient: return "Recipient's Device"
                case .recipientOffline: return "Recipient Goes Offline"
                case .outsideApp: return "Outside the App"
                }
            }

            public var subtitle: String {
                switch self {
                case .sender: return "Now viewing the sender's perspective"
                case .recipient: return "Now viewing the recipient's perspective"
                case .recipientOffline: return "The recipient puts their phone away. Time passes..."
                case .outsideApp: return "What happens outside Zodl"
                }
            }

            public var systemImage: String {
                switch self {
                case .sender: return "arrow.up.circle.fill"
                case .recipient: return "arrow.down.circle.fill"
                case .recipientOffline: return "moon.zzz.fill"
                case .outsideApp: return "iphone.and.arrow.right.inward"
                }
            }
        }

        public enum Flow: Equatable, CaseIterable {
            case paymentRequest
            case paymentLink
            case localCash
            case publicPayment

            public var title: String {
                switch self {
                case .paymentRequest: return "Payment Request"
                case .paymentLink: return "Payment Link"
                case .localCash: return "Local Cash"
                case .publicPayment: return "Public Payment"
                }
            }

            public var description: String {
                switch self {
                case .paymentRequest:
                    return "Request a payment by sharing a QR code"
                case .paymentLink:
                    return "Send a friend their first ZEC via a link"
                case .localCash:
                    return "Hand someone digital cash via QR"
                case .publicPayment:
                    return "Accept payments while offline via relay"
                }
            }

            public var systemImage: String {
                switch self {
                case .paymentRequest: return "qrcode"
                case .paymentLink: return "link"
                case .localCash: return "banknote.fill"
                case .publicPayment: return "antenna.radiowaves.left.and.right"
                }
            }
        }

        // MARK: - Screen Role

        public enum Role: Equatable {
            case recipient
            case sender

            public var label: String {
                switch self {
                case .recipient: return "Recipient's Device"
                case .sender: return "Sender's Device"
                }
            }
        }

        public var screenStack: [Screen] = [.flowPicker]
        public var selectedFlow: Flow?

        public var activeRole: Role? {
            screenStack.last?.role
        }

        // Amount input
        public var amount: String = ""

        public var isOverBalance: Bool {
            guard let value = Double(amount) else { return false }
            return value > 12.5
        }

        // QR
        public var qrCodeImage: CGImage?
        public var qrContent: String = ""

        // Share
        public var isSharePresented: Bool = false

        // Relay
        public var relayURL: String = ""

        // Mock received payments
        public var receivedPayments: [MockPayment] = []

        public static let initial = State()

        public init() {}
    }

    // MARK: - Action

    public enum Action: Equatable {
        // Navigation
        case dismissFlow
        case goBack
        case flowSelected(State.Flow)

        // Amount
        case amountChanged(String)

        // Proceed through screens
        case proceedTapped

        // QR
        case generateQRCode(String)
        case qrCodeGenerated(CGImage?)

        // Share
        case sharePayment
        case shareFinished

        // Delays
        case simulatedDelayCompleted

        // Revoke
        case revokePayment

        // Public Payment specific
        case registerWithRelay
        case checkRelay

        // Reset
        case backToFlowPicker
    }

    // MARK: - Reducer

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .dismissFlow:
                state.screenStack = [.flowPicker]
                state.reset()
                return .cancel(id: CancelID.simulatedDelay)

            case .goBack:
                if state.screenStack.count > 1 {
                    state.screenStack.removeLast()
                }
                return .none

            case .backToFlowPicker:
                state.screenStack = [.flowPicker]
                state.reset()
                return .none

            case let .flowSelected(flow):
                state.selectedFlow = flow
                switch flow {
                case .paymentRequest:
                    state.screenStack.append(.prRecipientCreate)
                case .paymentLink:
                    state.screenStack.append(.plSenderEnterAmount)
                case .localCash:
                    state.screenStack.append(.cashSenderEnterAmount)
                case .publicPayment:
                    state.screenStack.append(.ppRecipientRegister)
                }
                return .none

            // MARK: Amount

            case let .amountChanged(text):
                state.amount = text
                return .none

            // MARK: QR

            case let .generateQRCode(content):
                state.qrContent = content
                return .none

            case let .qrCodeGenerated(image):
                state.qrCodeImage = image
                return .none

            // MARK: Share

            case .sharePayment:
                state.isSharePresented = true
                return .none

            case .shareFinished:
                state.isSharePresented = false
                return .none

            // MARK: Flow navigation

            case .proceedTapped:
                return handleProceed(&state)

            case .simulatedDelayCompleted:
                return handleDelayCompleted(&state)

            case .revokePayment:
                let screen: State.Screen = state.selectedFlow == .paymentLink
                    ? .plSenderRevoking : .cashSenderRevoking
                state.screenStack.append(screen)
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(1.5))
                    await send(.simulatedDelayCompleted)
                }
                .cancellable(id: CancelID.simulatedDelay)

            case .registerWithRelay:
                state.screenStack.append(.ppRecipientRegistering)
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(3))
                    await send(.simulatedDelayCompleted)
                }
                .cancellable(id: CancelID.simulatedDelay)

            case .checkRelay:
                state.screenStack.append(.ppRecipientChecking)
                return .run { send in
                    try await mainQueue.sleep(for: .seconds(3))
                    await send(.simulatedDelayCompleted)
                }
                .cancellable(id: CancelID.simulatedDelay)
            }
        }
    }

    // MARK: - Helpers

    private func handleProceed(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {

        // MARK: Flow 1 — Payment Request

        case .prRecipientCreate:
            let amount = state.amount.isEmpty ? "1.0" : state.amount
            state.qrContent = TachyonURI.paymentRequest(
                pk: MockData.recipientKey.hex,
                amount: amount
            )
            state.screenStack.append(.prRecipientShowQR)
            return .none

        case .prRecipientShowQR:
            state.screenStack.append(.switchTo(.sender))
            return .none

        case .switchTo(.sender) where state.selectedFlow == .paymentRequest:
            state.screenStack.append(.prSenderConfirm)
            return .none

        case .prSenderConfirm:
            state.screenStack.append(.prSenderProcessing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // MARK: Flow 2A — Payment Link

        case .plSenderEnterAmount:
            state.qrContent = TachyonURI.encapsulatedPayment(noteHex: MockData.mockNoteHex)
            state.screenStack.append(.plSenderShare)
            return .none

        case .plSenderShare:
            // Sender shared link → show what happens outside the app
            state.screenStack.append(.switchTo(.outsideApp))
            return .none

        case .switchTo(.outsideApp) where state.selectedFlow == .paymentLink:
            state.screenStack.append(.plOutsideMessageReceived)
            return .none

        case .plOutsideMessageReceived:
            state.screenStack.append(.plOutsideInstallApp)
            return .none

        case .plOutsideInstallApp:
            state.screenStack.append(.plRecipientClaim)
            return .none

        case .plRecipientClaim:
            state.screenStack.append(.plRecipientFinalizing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // MARK: Flow 2B — Local Cash

        case .cashSenderEnterAmount:
            state.qrContent = TachyonURI.encapsulatedPayment(noteHex: MockData.mockNoteHex)
            state.screenStack.append(.cashSenderShowQR)
            return .none

        case .cashSenderShowQR:
            state.screenStack.append(.switchTo(.outsideApp))
            return .none

        case .switchTo(.outsideApp) where state.selectedFlow == .localCash:
            state.screenStack.append(.cashOutsideCameraScan)
            return .none

        case .cashOutsideCameraScan:
            state.screenStack.append(.cashOutsideInstallApp)
            return .none

        case .cashOutsideInstallApp:
            state.screenStack.append(.cashRecipientClaim)
            return .none

        case .cashRecipientClaim:
            state.screenStack.append(.cashRecipientFinalizing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(1.5))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        // MARK: Flow 3 — Public Payment

        case .ppRecipientShowURL:
            state.screenStack.append(.switchTo(.recipientOffline))
            return .none

        case .switchTo(.recipientOffline):
            state.screenStack.append(.switchTo(.sender))
            return .none

        case .switchTo(.sender) where state.selectedFlow == .publicPayment:
            state.screenStack.append(.ppSenderEnterAmount)
            return .none

        case .ppSenderEnterAmount:
            state.screenStack.append(.ppSenderConfirm)
            return .none

        case .ppSenderConfirm:
            state.screenStack.append(.ppSenderProcessing)
            return .run { send in
                try await mainQueue.sleep(for: .seconds(2))
                await send(.simulatedDelayCompleted)
            }
            .cancellable(id: CancelID.simulatedDelay)

        case .switchTo(.recipient) where state.selectedFlow == .paymentRequest:
            state.screenStack.append(.prRecipientReceived)
            return .none

        case .switchTo(.recipient) where state.selectedFlow == .publicPayment:
            state.screenStack.append(.ppRecipientCheckRelay)
            return .none

        default:
            return .none
        }
    }

    private func handleDelayCompleted(_ state: inout State) -> Effect<Action> {
        guard let currentScreen = state.screenStack.last else { return .none }

        switch currentScreen {
        case .prSenderProcessing:
            state.screenStack.append(.switchTo(.recipient))
            return .none

        case .plSenderRevoking:
            state.screenStack.append(.plSenderRevoked)
            return .none

        case .plRecipientFinalizing:
            state.screenStack.append(.plRecipientDone)
            return .none

        case .cashSenderRevoking:
            state.screenStack.append(.cashSenderRevoked)
            return .none

        case .cashRecipientFinalizing:
            state.screenStack.append(.cashRecipientDone)
            return .none

        case .ppRecipientRegistering:
            state.relayURL = TachyonURI.relayURL(relayId: MockData.relayId)
            state.qrContent = state.relayURL
            state.screenStack.append(.ppRecipientShowURL)
            return .none

        case .ppSenderProcessing:
            state.screenStack.append(.switchTo(.recipient))
            return .none

        case .ppRecipientChecking:
            let sentAmount = state.amount.isEmpty ? "1.0" : state.amount
            state.receivedPayments = MockData.mockReceivedPayments(primaryAmount: sentAmount)
            state.screenStack.append(.ppRecipientPaymentsArrived)
            return .none

        default:
            return .none
        }
    }
}

// MARK: - State Reset

extension TachyonDemo.State {
    mutating func reset() {
        selectedFlow = nil
        amount = ""
        qrCodeImage = nil
        qrContent = ""
        isSharePresented = false
        relayURL = ""
        receivedPayments = []
    }
}
