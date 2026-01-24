# PIR Nullifier Integration Plan for Zashi iOS

## Overview

Integrate PIR (Private Information Retrieval) into Zashi iOS to enable instant spent-status checks for known notes when the app opens and is behind on sync. This is the first step toward replacing all historical trial decryption with PIR.

**Goal**: When Zashi opens and sees it's X blocks behind, use PIR to immediately check if any known notes have been spent.

---

## Repository Layout

| Repository                 | Local Path                                           | Branch                                      | Status                      |
| -------------------------- | ---------------------------------------------------- | ------------------------------------------- | --------------------------- |
| **zashi-ios**              | `/Users/czar/Documents/forks/zashi-ios`              | `adam/nullifier-demo`                       | Main integration target     |
| **lightwalletd**           | `/Users/czar/Documents/forks/lightwalletd`           | `adam/lightwalletd-nullifier-precheck-perf` | PIR gRPC endpoints ready    |
| **pir**                    | `/Users/czar/Documents/pir`                          | `adam/live-ingestion-hotswap`               | PIR server + client library |
| **zcash-swift-wallet-sdk** | `/Users/czar/Documents/forks/zcash-swift-wallet-sdk` | `TBD: adam/pir-integration`                 | Needs branch creation       |

### Branch to Create

```bash
cd /Users/czar/Documents/forks/zcash-swift-wallet-sdk
git checkout -b adam/pir-integration
git push -u origin adam/pir-integration
```

---

## Architecture

```
ZASHI iOS APP (/Users/czar/Documents/forks/zashi-ios)
     │
     ▼
ZCASH-SWIFT-WALLET-SDK (/Users/czar/Documents/forks/zcash-swift-wallet-sdk)
     │
     ├──► FFI Crypto (local operations)
     │    • precomputeKeys()
     │    • generateQuery()
     │    • decryptResponse()
     │
     └──► gRPC to lightwalletd
          • GetPirParams()
          • InspireQuery()
          • GetPirStatus()
               │
               ▼
          LIGHTWALLETD (/Users/czar/Documents/forks/lightwalletd)
               │
               ▼ (internal HTTP proxy)
          NULLIFIER-PIR SERVER (/Users/czar/Documents/pir)
```

### Key Architectural Points

1. **All network communication** goes through lightwalletd gRPC (existing pattern)
2. **FFI is only for local crypto** - key generation, query encryption, response decryption
3. **Zashi never talks directly to PIR server** - lightwalletd proxies

---

## Work Packages

### Package 1: FFI Crypto Layer

**Location**: `/Users/czar/Documents/pir` branch `adam/live-ingestion-hotswap`

**New directory**: `nullifier-pir/crates/client-ffi/`

**Purpose**: Expose PIR cryptographic operations to Swift via UniFFI

#### 1.1 Files to Create

```
nullifier-pir/crates/client-ffi/
├── Cargo.toml
├── src/
│   └── lib.rs
├── build.rs
└── uniffi.toml
```

#### 1.2 Cargo.toml

```toml
[package]
name = "nullifier-client-ffi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib", "staticlib"]
name = "nullifier_client_ffi"

[dependencies]
nullifier-client = { path = "../client", features = ["client-only"] }
nullifier-common = { path = "../common" }
uniffi = { version = "0.28", features = ["cli"] }
thiserror = "2.0"
serde = { workspace = true }
serde_json = { workspace = true }

[build-dependencies]
uniffi = { version = "0.28", features = ["build"] }
```

#### 1.3 FFI Interface (lib.rs)

```rust
use std::sync::{Arc, Mutex};
use nullifier_common::{Nullifier, SpentInfo};

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum PirError {
    #[error("Not initialized: {msg}")]
    NotInitialized { msg: String },
    #[error("Crypto error: {msg}")]
    CryptoError { msg: String },
    #[error("Invalid input: {msg}")]
    InvalidInput { msg: String },
}

/// Result of a nullifier spent check
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiSpentInfo {
    pub block_height: u64,
    pub tx_index: u32,
}

/// PIR parameters received from lightwalletd
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiPirParams {
    pub pir_cutoff_height: u64,
    pub protocol: String,  // "inspire" or "ypir"
    pub params_json: String,  // Full params as JSON for flexibility
}

/// Query to send to lightwalletd
#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiPirQuery {
    pub query_bytes: Vec<u8>,
    pub bucket_indices: Vec<u64>,
}

/// PIR crypto client - handles all local cryptographic operations
#[derive(uniffi::Object)]
pub struct PirCryptoClient {
    inner: Mutex<Option<ClientState>>,
}

struct ClientState {
    // Internal crypto state
    keys_ready: bool,
    // ... precomputed keys, etc.
}

#[uniffi::export]
impl PirCryptoClient {
    /// Create a new PIR crypto client
    #[uniffi::constructor]
    pub fn new() -> Self {
        Self {
            inner: Mutex::new(None),
        }
    }

    /// Initialize with parameters from lightwalletd GetPirParams response
    pub fn initialize(&self, params: FfiPirParams) -> Result<(), PirError> {
        // Parse params and setup crypto state
        Ok(())
    }

    /// Precompute cryptographic keys (expensive, ~3s for InsPIRe)
    pub fn precompute_keys(&self) -> Result<(), PirError> {
        // Generate secret keys, packing keys, etc.
        Ok(())
    }

    /// Check if keys have been precomputed
    pub fn keys_ready(&self) -> bool {
        self.inner.lock().unwrap()
            .as_ref()
            .map(|s| s.keys_ready)
            .unwrap_or(false)
    }

    /// Generate encrypted PIR query for a nullifier
    pub fn generate_query(&self, nullifier_hex: String) -> Result<FfiPirQuery, PirError> {
        // 1. Compute Cuckoo bucket indices
        // 2. Generate encrypted query
        // 3. Return serialized query bytes
        todo!()
    }

    /// Decrypt PIR response from lightwalletd
    pub fn decrypt_response(
        &self,
        response_bytes: Vec<u8>,
        nullifier_hex: String,
    ) -> Result<Option<FfiSpentInfo>, PirError> {
        // 1. Decrypt response using secret keys
        // 2. Search decrypted bucket for nullifier
        // 3. Return SpentInfo if found
        todo!()
    }
}
```

#### 1.4 Build XCFramework Script

Create `nullifier-pir/build-xcframework.sh`:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building for iOS device..."
cargo build --release --target aarch64-apple-ios -p nullifier-client-ffi

echo "Building for iOS simulator (Apple Silicon)..."
cargo build --release --target aarch64-apple-ios-sim -p nullifier-client-ffi

echo "Generating Swift bindings..."
mkdir -p bindings
cargo run --bin uniffi-bindgen generate \
    --library target/aarch64-apple-ios/release/libnullifier_client_ffi.a \
    --language swift \
    --out-dir bindings

echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libnullifier_client_ffi.a \
    -headers bindings \
    -library target/aarch64-apple-ios-sim/release/libnullifier_client_ffi.a \
    -headers bindings \
    -output NullifierClientFFI.xcframework

echo "Done! XCFramework at: NullifierClientFFI.xcframework"
```

#### 1.5 Update Workspace Cargo.toml

Add to `/Users/czar/Documents/pir/nullifier-pir/Cargo.toml`:

```toml
members = [
    "crates/ingestion",
    "crates/server",
    "crates/client",
    "crates/common",
    "crates/client-ffi",  # Add this
]
```

---

### Package 2: SDK Integration

**Location**: `/Users/czar/Documents/forks/zcash-swift-wallet-sdk` branch `adam/pir-integration`

#### 2.1 Update Proto Files

The lightwalletd proto already has PIR definitions. Regenerate Swift code from:
`/Users/czar/Documents/forks/lightwalletd/lightwallet-protocol/walletrpc/service.proto`

PIR messages already defined:
- `GetPirParamsRequest` / `PirParamsResponse`
- `YpirQueryRequest` / `YpirQueryResponse`
- `InspireQueryRequest` / `InspireQueryResponse`
- `GetPirStatusRequest` / `PirStatusResponse`

#### 2.2 Add PIR gRPC Methods

File: `Sources/ZcashLightClientKit/Service/LightWalletGRPCService.swift`

```swift
extension LightWalletGRPCService {

    /// Fetch PIR parameters from lightwalletd
    func getPirParams() async throws -> PirParamsResponse {
        let request = GetPirParamsRequest()
        return try await compactTxStreamer.getPirParams(request)
    }

    /// Execute InsPIRe query
    func inspireQuery(_ queryBytes: Data) async throws -> InspireQueryResponse {
        var request = InspireQueryRequest()
        request.query = queryBytes
        return try await compactTxStreamer.inspireQuery(request)
    }

    /// Execute YPIR query
    func ypirQuery(_ queryBytes: Data) async throws -> YpirQueryResponse {
        var request = YpirQueryRequest()
        request.query = queryBytes
        return try await compactTxStreamer.ypirQuery(request)
    }

    /// Get PIR service status
    func getPirStatus() async throws -> PirStatusResponse {
        let request = GetPirStatusRequest()
        return try await compactTxStreamer.getPirStatus(request)
    }
}
```

#### 2.3 Create PIRChecker Component

New file: `Sources/ZcashLightClientKit/PIR/PIRChecker.swift`

```swift
import Foundation
import NullifierClientFFI  // The FFI framework

public enum PIRError: Error {
    case notInitialized
    case serviceUnavailable(String)
    case cryptoError(String)
    case networkError(String)
}

public struct SpentInfo: Equatable, Sendable {
    public let blockHeight: BlockHeight
    public let txIndex: Int
}

public actor PIRChecker {
    private let lightWalletService: LightWalletService
    private let pirCrypto: PirCryptoClient
    private var initialized = false
    private var pirCutoffHeight: BlockHeight = 0

    public init(lightWalletService: LightWalletService) {
        self.lightWalletService = lightWalletService
        self.pirCrypto = PirCryptoClient()
    }

    /// Initialize PIR client with params from lightwalletd
    public func initialize() async throws {
        // 1. Fetch params from lightwalletd (gRPC)
        let paramsResponse = try await lightWalletService.getPirParams()

        guard paramsResponse.pirReady else {
            throw PIRError.serviceUnavailable(paramsResponse.status)
        }

        // 2. Convert to FFI format
        let ffiParams = FfiPirParams(
            pirCutoffHeight: paramsResponse.pirCutoffHeight,
            protocol: "inspire",
            paramsJson: try paramsResponse.jsonString()
        )

        // 3. Initialize crypto (FFI - local)
        try pirCrypto.initialize(params: ffiParams)

        // 4. Precompute keys (FFI - local, ~3 seconds)
        try pirCrypto.precomputeKeys()

        self.pirCutoffHeight = BlockHeight(paramsResponse.pirCutoffHeight)
        self.initialized = true
    }

    /// Check if a single nullifier has been spent
    public func checkNullifier(_ nullifier: Data) async throws -> SpentInfo? {
        guard initialized else {
            throw PIRError.notInitialized
        }

        let nullifierHex = nullifier.hexEncodedString()

        // 1. Generate query locally (FFI)
        let query = try pirCrypto.generateQuery(nullifierHex: nullifierHex)

        // 2. Send query to lightwalletd (gRPC)
        let response = try await lightWalletService.inspireQuery(Data(query.queryBytes))

        // 3. Decrypt response locally (FFI)
        let result = try pirCrypto.decryptResponse(
            responseBytes: Array(response.response),
            nullifierHex: nullifierHex
        )

        return result.map {
            SpentInfo(blockHeight: BlockHeight($0.blockHeight), txIndex: Int($0.txIndex))
        }
    }

    /// Check multiple nullifiers
    public func checkNullifiers(_ nullifiers: [Data]) async throws -> [Data: SpentInfo?] {
        var results: [Data: SpentInfo?] = [:]

        for nullifier in nullifiers {
            let result = try await checkNullifier(nullifier)
            results[nullifier] = result
        }

        return results
    }

    public var cutoffHeight: BlockHeight { pirCutoffHeight }
    public var isReady: Bool { initialized && pirCrypto.keysReady() }
}
```

#### 2.4 Add Nullifier Query API

New file: `Sources/ZcashLightClientKit/PIR/UnspentNoteInfo.swift`

```swift
public struct UnspentNoteInfo: Equatable, Sendable {
    public let nullifier: Data
    public let value: Zatoshi
    public let pool: ShieldedProtocol
    public let receivedAtHeight: BlockHeight
}
```

Add to `NotesRepository.swift`:

```swift
public protocol NotesRepository {
    // ... existing methods ...

    /// Get nullifiers for all notes the wallet believes are unspent
    func getUnspentNoteNullifiers(accountUUID: AccountUUID) async throws -> [UnspentNoteInfo]
}
```

#### 2.5 Add Quick Spend Check to Synchronizer

New file: `Sources/ZcashLightClientKit/Synchronizer/SDKSynchronizer+PIR.swift`

```swift
public enum QuickSpendCheckResult: Equatable, Sendable {
    case pirUnavailable(reason: String)
    case alreadySynced
    case noNotesToCheck
    case checked(totalNotes: Int, spentNotes: [SpentNoteInfo], pirCutoffHeight: BlockHeight, blocksBehind: Int)
}

public struct SpentNoteInfo: Equatable, Sendable {
    public let nullifier: Data
    public let value: Zatoshi
    public let pool: ShieldedProtocol
    public let spentAtHeight: BlockHeight
}

extension SDKSynchronizer {

    /// Perform quick spend check using PIR
    public func performQuickSpendCheck(account: Account) async throws -> QuickSpendCheckResult {
        // 1. Check PIR availability
        let pirStatus = try await service.getPirStatus()
        guard pirStatus.available else {
            return .pirUnavailable(reason: pirStatus.status)
        }

        // 2. Check if we're behind enough to benefit
        let latestHeight = try await service.latestBlockHeight()
        let localHeight = try await latestState().latestBlockHeight

        let blocksBehind = Int(latestHeight - localHeight)
        guard blocksBehind > 0 else {
            return .alreadySynced
        }

        // 3. Initialize PIR if needed
        if !pirChecker.isReady {
            try await pirChecker.initialize()
        }

        // 4. Get unspent note nullifiers from local DB
        let unspentNotes = try await notesRepository.getUnspentNoteNullifiers(accountUUID: account.id)

        guard !unspentNotes.isEmpty else {
            return .noNotesToCheck
        }

        // 5. Check via PIR
        let nullifiers = unspentNotes.map { $0.nullifier }
        let results = try await pirChecker.checkNullifiers(nullifiers)

        // 6. Process results
        let spentNotes = unspentNotes.compactMap { note -> SpentNoteInfo? in
            guard let spentInfo = results[note.nullifier] ?? nil else { return nil }
            return SpentNoteInfo(
                nullifier: note.nullifier,
                value: note.value,
                pool: note.pool,
                spentAtHeight: spentInfo.blockHeight
            )
        }

        return .checked(
            totalNotes: unspentNotes.count,
            spentNotes: spentNotes,
            pirCutoffHeight: pirChecker.cutoffHeight,
            blocksBehind: blocksBehind
        )
    }
}
```

#### 2.6 Update Package.swift

Add the FFI framework dependency and new source files.

---

### Package 3: Zashi iOS App Integration

**Location**: `/Users/czar/Documents/forks/zashi-ios` branch `adam/nullifier-demo`

#### 3.1 Create PIRChecker Dependency

New file: `modules/Sources/Dependencies/PIRChecker/PIRCheckerInterface.swift`

```swift
import ComposableArchitecture
import ZcashLightClientKit

@DependencyClient
public struct PIRCheckerClient: Sendable {
    public var initialize: @Sendable () async throws -> Void
    public var isAvailable: @Sendable () async -> Bool
    public var performQuickSpendCheck: @Sendable (WalletAccount) async throws -> QuickSpendCheckResult
}

extension PIRCheckerClient: DependencyKey {
    public static var liveValue: PIRCheckerClient {
        @Dependency(\.sdkSynchronizer) var sdkSynchronizer

        return PIRCheckerClient(
            initialize: {
                try await sdkSynchronizer.pirChecker.initialize()
            },
            isAvailable: {
                await sdkSynchronizer.pirChecker.isReady
            },
            performQuickSpendCheck: { account in
                try await sdkSynchronizer.performQuickSpendCheck(account: account)
            }
        )
    }

    public static var testValue: PIRCheckerClient {
        PIRCheckerClient(
            initialize: { },
            isAvailable: { true },
            performQuickSpendCheck: { _ in .noNotesToCheck }
        )
    }
}

extension DependencyValues {
    public var pirChecker: PIRCheckerClient {
        get { self[PIRCheckerClient.self] }
        set { self[PIRCheckerClient.self] = newValue }
    }
}
```

New file: `modules/Sources/Dependencies/PIRChecker/PIRCheckerLive.swift`

```swift
import Foundation
import ZcashLightClientKit

extension PIRCheckerClient {
    public static func live(synchronizer: SDKSynchronizerClient) -> Self {
        PIRCheckerClient(
            initialize: {
                // Implementation
            },
            isAvailable: {
                // Implementation
            },
            performQuickSpendCheck: { account in
                // Implementation
            }
        )
    }
}
```

#### 3.2 Add PIR State and Actions to Root

Update `modules/Sources/Features/Root/RootStore.swift`:

```swift
// Add to State
@ObservableState
public struct State: Equatable {
    // ... existing state ...
    public var pirCheckResult: QuickSpendCheckResult?
    public var pirCheckInProgress: Bool = false
}

// Add Actions
public enum Action: Equatable {
    // ... existing actions ...
    case pirCheckRequested
    case pirCheckCompleted(QuickSpendCheckResult)
    case pirCheckFailed(String)
    case dismissPirResult
}
```

Update reducer:

```swift
case .appBecameActive:
    // Existing logic...
    return .merge(
        existingEffects,
        .send(.pirCheckRequested)
    )

case .pirCheckRequested:
    guard !state.pirCheckInProgress else { return .none }
    state.pirCheckInProgress = true

    return .run { [account = state.selectedAccount] send in
        do {
            let result = try await pirChecker.performQuickSpendCheck(account)
            await send(.pirCheckCompleted(result))
        } catch {
            await send(.pirCheckFailed(error.localizedDescription))
        }
    }

case .pirCheckCompleted(let result):
    state.pirCheckInProgress = false
    state.pirCheckResult = result
    return .none

case .pirCheckFailed(let error):
    state.pirCheckInProgress = false
    // Log error, PIR is optional enhancement
    return .none
```

#### 3.3 Add UI for PIR Results

Option A: SmartBanner integration (recommended)

Update `modules/Sources/Features/SmartBanner/SmartBannerStore.swift` to handle PIR results.

Option B: Toast notification for quick feedback.

---

### Package 4: Demo Feedback UI

**Location**: `/Users/czar/Documents/forks/zashi-ios` branch `adam/nullifier-demo`

**Purpose**: Provide clear visual feedback showing PIR queries in progress and results, so developers can verify the integration is working correctly.

#### 4.1 PIR Debug State

Add to `RootStore.swift` State:

```swift
// PIR Debug State for Demo
public struct PIRDebugState: Equatable {
    public enum Status: Equatable {
        case idle
        case initializingCrypto
        case precomputingKeys
        case queryingNullifiers(current: Int, total: Int)
        case completed
        case failed(String)
    }

    public var status: Status = .idle
    public var keyPrepTimeMs: Int?
    public var totalQueries: Int = 0
    public var completedQueries: Int = 0
    public var spentNullifiers: [SpentNullifierResult] = []
    public var unspentCount: Int = 0
    public var logEntries: [LogEntry] = []
    public var isVisible: Bool = true

    public struct LogEntry: Equatable, Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let message: String
    }

    public struct SpentNullifierResult: Equatable, Identifiable {
        public var id: String { nullifierHex }
        public let nullifierHex: String
        public let spentAtHeight: UInt64
        public let value: UInt64  // in zatoshi
    }
}
```

#### 4.2 PIR Debug Actions

Add to `RootStore.swift` Action:

```swift
public enum Action: Equatable {
    // ... existing actions ...

    // PIR Debug Actions
    case pirDebug(PIRDebugAction)
}

public enum PIRDebugAction: Equatable {
    case started
    case cryptoInitialized
    case keyPrecomputeStarted
    case keyPrecomputeCompleted(timeMs: Int)
    case queryStarted(nullifierIndex: Int, total: Int)
    case queryCompleted(nullifierHex: String, spent: Bool, spentHeight: UInt64?, value: UInt64)
    case allQueriesCompleted
    case failed(String)
    case log(String)
    case toggleVisibility
    case dismiss
}
```

#### 4.3 PIR Debug Overlay View

New file: `modules/Sources/Features/Root/PIRDebugOverlayView.swift`

```swift
import SwiftUI
import ComposableArchitecture

struct PIRDebugOverlayView: View {
    let state: RootReducer.PIRDebugState
    let send: (RootReducer.PIRDebugAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "lock.shield")
                Text("PIR Nullifier Check")
                    .font(.headline)
                Spacer()
                Button(action: { send(.toggleVisibility) }) {
                    Image(systemName: state.isVisible ? "chevron.up" : "chevron.down")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.8))
            .foregroundColor(.white)

            if state.isVisible {
                VStack(alignment: .leading, spacing: 6) {
                    // Status
                    statusView

                    Divider()

                    // Stats
                    statsView

                    Divider()

                    // Log
                    logView
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 4)
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        HStack {
            statusIcon
            Text(statusText)
                .font(.subheadline)
        }
    }

    private var statusIcon: some View {
        Group {
            switch state.status {
            case .idle:
                Image(systemName: "circle").foregroundColor(.gray)
            case .initializingCrypto, .precomputingKeys, .queryingNullifiers:
                ProgressView().scaleEffect(0.8)
            case .completed:
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
            }
        }
    }

    private var statusText: String {
        switch state.status {
        case .idle:
            return "Waiting..."
        case .initializingCrypto:
            return "Initializing crypto..."
        case .precomputingKeys:
            return "Precomputing keys (~3s)..."
        case .queryingNullifiers(let current, let total):
            return "Querying nullifier \(current)/\(total)..."
        case .completed:
            return "Completed ✓"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    @ViewBuilder
    private var statsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let keyTime = state.keyPrepTimeMs {
                Text("Key prep: \(keyTime)ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if state.totalQueries > 0 {
                Text("Queries: \(state.completedQueries)/\(state.totalQueries)")
                    .font(.caption)

                HStack {
                    Label("\(state.spentNullifiers.count) spent", systemImage: "arrow.up.circle.fill")
                        .foregroundColor(.orange)
                    Label("\(state.unspentCount) unspent", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .font(.caption)
            }

            // Show spent nullifier details
            if !state.spentNullifiers.isEmpty {
                Text("Spent Notes:")
                    .font(.caption.bold())
                    .padding(.top, 4)

                ForEach(state.spentNullifiers) { spent in
                    HStack {
                        Text("• \(spent.nullifierHex.prefix(8))...")
                            .font(.caption.monospaced())
                        Text("@ \(spent.spentAtHeight)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(formatZatoshi(spent.value)) ZEC")
                            .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var logView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Log:")
                .font(.caption.bold())

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(state.logEntries.suffix(10)) { entry in
                        Text("[\(formatTime(entry.timestamp))] \(entry.message)")
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxHeight: 100)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatZatoshi(_ zatoshi: UInt64) -> String {
        let zec = Double(zatoshi) / 100_000_000
        return String(format: "%.8f", zec)
    }
}
```

#### 4.4 Integrate Overlay into RootView

Update `modules/Sources/Features/Root/RootView.swift`:

```swift
struct RootView: View {
    let store: StoreOf<RootReducer>

    var body: some View {
        ZStack {
            // Existing content
            existingRootContent(store: store)

            // PIR Debug Overlay (only in debug builds)
            #if DEBUG
            if store.pirDebugState.status != .idle || !store.pirDebugState.logEntries.isEmpty {
                VStack {
                    Spacer()
                    PIRDebugOverlayView(
                        state: store.pirDebugState,
                        send: { store.send(.pirDebug($0)) }
                    )
                }
                .transition(.move(edge: .bottom))
            }
            #endif
        }
    }
}
```

#### 4.5 Update PIRChecker to Send Debug Events

Modify the PIR check flow to emit debug actions:

```swift
case .pirCheckRequested:
    guard !state.pirCheckInProgress else { return .none }
    state.pirCheckInProgress = true

    return .run { send in
        await send(.pirDebug(.started))
        await send(.pirDebug(.log("Starting PIR check...")))

        do {
            // Initialize
            await send(.pirDebug(.log("Fetching PIR params from lightwalletd...")))
            await send(.pirDebug(.initializingCrypto))

            // Key precomputation
            await send(.pirDebug(.keyPrecomputeStarted))
            let keyStartTime = Date()
            try await pirChecker.initialize()
            let keyTimeMs = Int(Date().timeIntervalSince(keyStartTime) * 1000)
            await send(.pirDebug(.keyPrecomputeCompleted(timeMs: keyTimeMs)))
            await send(.pirDebug(.log("Keys ready in \(keyTimeMs)ms")))

            // Get nullifiers
            let nullifiers = try await getNullifiersToCheck()
            await send(.pirDebug(.log("Found \(nullifiers.count) nullifiers to check")))

            // Query each
            for (index, nullifier) in nullifiers.enumerated() {
                await send(.pirDebug(.queryStarted(nullifierIndex: index + 1, total: nullifiers.count)))
                await send(.pirDebug(.log("Querying nullifier \(nullifier.hex.prefix(8))...")))

                let result = try await pirChecker.checkNullifier(nullifier)
                let isSpent = result != nil

                await send(.pirDebug(.queryCompleted(
                    nullifierHex: nullifier.hex,
                    spent: isSpent,
                    spentHeight: result?.blockHeight,
                    value: nullifier.value
                )))

                if isSpent {
                    await send(.pirDebug(.log("✗ SPENT at height \(result!.blockHeight)")))
                } else {
                    await send(.pirDebug(.log("✓ Unspent")))
                }
            }

            await send(.pirDebug(.allQueriesCompleted))
            await send(.pirDebug(.log("PIR check complete!")))

        } catch {
            await send(.pirDebug(.failed(error.localizedDescription)))
            await send(.pirDebug(.log("Error: \(error.localizedDescription)")))
        }
    }
```

#### 4.6 Reducer for Debug Actions

Add to RootReducer:

```swift
case .pirDebug(let action):
    switch action {
    case .started:
        state.pirDebugState = PIRDebugState()
        state.pirDebugState.status = .initializingCrypto

    case .cryptoInitialized:
        state.pirDebugState.status = .precomputingKeys

    case .keyPrecomputeStarted:
        state.pirDebugState.status = .precomputingKeys

    case .keyPrecomputeCompleted(let timeMs):
        state.pirDebugState.keyPrepTimeMs = timeMs

    case .queryStarted(let current, let total):
        state.pirDebugState.status = .queryingNullifiers(current: current, total: total)
        state.pirDebugState.totalQueries = total

    case .queryCompleted(let hex, let spent, let height, let value):
        state.pirDebugState.completedQueries += 1
        if spent, let h = height {
            state.pirDebugState.spentNullifiers.append(
                PIRDebugState.SpentNullifierResult(
                    nullifierHex: hex,
                    spentAtHeight: h,
                    value: value
                )
            )
        } else {
            state.pirDebugState.unspentCount += 1
        }

    case .allQueriesCompleted:
        state.pirDebugState.status = .completed

    case .failed(let error):
        state.pirDebugState.status = .failed(error)

    case .log(let message):
        state.pirDebugState.logEntries.append(
            PIRDebugState.LogEntry(timestamp: Date(), message: message)
        )

    case .toggleVisibility:
        state.pirDebugState.isVisible.toggle()

    case .dismiss:
        state.pirDebugState = PIRDebugState()
    }
    return .none
```

#### 4.7 Example Debug Output

When the app opens with 4 unspent notes and 1 is found to be spent:

```
┌──────────────────────────────────────────────┐
│ 🛡 PIR Nullifier Check                    ▼  │
├──────────────────────────────────────────────┤
│ ✓ Completed                                  │
├──────────────────────────────────────────────┤
│ Key prep: 2847ms                             │
│ Queries: 4/4                                 │
│ 🔶 1 spent  ✅ 3 unspent                     │
│                                              │
│ Spent Notes:                                 │
│ • a3f2c9e1... @ 2847521  0.50000000 ZEC      │
├──────────────────────────────────────────────┤
│ Log:                                         │
│ [14:32:01] Starting PIR check...             │
│ [14:32:01] Fetching PIR params...            │
│ [14:32:02] Keys ready in 2847ms              │
│ [14:32:02] Found 4 nullifiers to check       │
│ [14:32:03] Querying nullifier a3f2c9e1...    │
│ [14:32:04] ✗ SPENT at height 2847521         │
│ [14:32:04] Querying nullifier b7d4e2f3...    │
│ [14:32:05] ✓ Unspent                         │
│ [14:32:05] Querying nullifier c1a8b5d9...    │
│ [14:32:06] ✓ Unspent                         │
│ [14:32:06] Querying nullifier d5f3c7a2...    │
│ [14:32:07] ✓ Unspent                         │
│ [14:32:07] PIR check complete!               │
└──────────────────────────────────────────────┘
```

#### 4.8 Feature Flag

Add to `modules/Sources/Utils/FeatureFlags.swift` or equivalent:

```swift
enum PIRFeatureFlags {
    /// Show debug overlay during PIR checks (DEBUG builds only)
    static var showDebugOverlay: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Enable PIR checking at all
    static var pirEnabled: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "pirEnabled")
        #endif
    }
}
```

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    APP LAUNCH / BECOME ACTIVE                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Root.appBecameActive → .pirCheckRequested                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. SDK: Check PIR availability                                 │
│     gRPC: GetPirStatus() → lightwalletd                         │
│     If unavailable → skip, continue normal sync                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. SDK: Initialize PIR crypto if needed                        │
│     gRPC: GetPirParams() → receive crypto parameters            │
│     FFI: initialize(params) → setup local crypto state          │
│     FFI: precomputeKeys() → ~3 seconds (one-time)               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. SDK: Get unspent note nullifiers from local DB              │
│     Query data.db for notes without spend records               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. For each nullifier:                                         │
│     FFI: generateQuery(nullifier) → encrypted query bytes       │
│     gRPC: InspireQuery(bytes) → lightwalletd → PIR server       │
│     FFI: decryptResponse(bytes) → SpentInfo or nil              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. Return results to app                                       │
│     If any spent: Show banner "X notes spent while away"        │
│     If none spent: Toast "Balance confirmed"                    │
│     Continue normal sync for blocks > PIR cutoff                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Order

### Phase 1: FFI Crypto Layer
**Repo**: `/Users/czar/Documents/pir` branch `adam/live-ingestion-hotswap`

- [ ] Create `nullifier-pir/crates/client-ffi/` directory structure
- [ ] Implement UniFFI bindings
- [ ] Create build script for XCFramework
- [ ] Test on iOS simulator

### Phase 2: SDK Integration
**Repo**: `/Users/czar/Documents/forks/zcash-swift-wallet-sdk` branch `adam/pir-integration`

- [ ] Create branch `adam/pir-integration`
- [ ] Regenerate Swift proto code with PIR messages
- [ ] Add PIR gRPC methods to LightWalletService
- [ ] Create PIRChecker component
- [ ] Add nullifier query to NotesRepository
- [ ] Implement performQuickSpendCheck()
- [ ] Add FFI framework dependency
- [ ] Write tests

### Phase 3: App Integration
**Repo**: `/Users/czar/Documents/forks/zashi-ios` branch `adam/nullifier-demo`

- [ ] Create PIRCheckerClient dependency
- [ ] Add PIR state/actions to RootStore
- [ ] Wire into app lifecycle (appBecameActive)
- [ ] Add UI for results (SmartBanner or toast)
- [ ] Update SDK dependency to fork
- [ ] End-to-end testing

### Phase 4: Demo Feedback UI
**Repo**: `/Users/czar/Documents/forks/zashi-ios` branch `adam/nullifier-demo`

- [ ] Add PIRDebugState to RootStore State
- [ ] Add PIRDebugAction cases
- [ ] Create PIRDebugOverlayView.swift
- [ ] Integrate overlay into RootView (DEBUG builds)
- [ ] Update PIR check flow to emit debug actions
- [ ] Add feature flags for debug overlay
- [ ] Test visual feedback during PIR flow

---

## Dependencies Between Packages

```
Package 1 (FFI) ──────► Package 2 (SDK) ──────► Package 3 (App) ──────► Package 4 (Debug UI)
     │                       │                       │                       │
     │                       │                       │                       │
     ▼                       ▼                       ▼                       ▼
XCFramework            SDK with PIR            Zashi with              Visual feedback
                       support                 PIR feature             for verification
```

Note: Package 4 (Demo Feedback UI) can be developed in parallel with Package 3 as it only requires the action/state interfaces.

---

## Testing Strategy

### Unit Tests
- FFI: Test crypto operations in isolation
- SDK: Mock lightwalletd responses, test PIRChecker logic
- App: Test TCA reducer actions

### Integration Tests
- SDK + lightwalletd: Real gRPC calls to test server
- Full stack: App → SDK → lightwalletd → PIR server

### Manual Testing
1. Launch app while behind on sync
2. Verify PIR check runs
3. Check UI shows appropriate results
4. Verify normal sync continues after PIR check

---

## Configuration

### Lightwalletd Endpoint
The PIR-enabled lightwalletd should be configured in the app. For testing:

```swift
// Custom endpoint for PIR-enabled lightwalletd
let pirEndpoint = LightWalletEndpoint(
    address: "your-pir-lightwalletd.example.com",
    port: 443,
    secure: true
)
```

### Feature Flag (Optional)
Consider adding a feature flag to enable/disable PIR checking during rollout.

---

## Open Questions

1. **Key Persistence**: Should precomputed keys be cached to disk, or regenerated each session?
   - Recommendation: In-memory per session for now, ~3s is acceptable on app launch

2. **Parallel Queries**: Should we query multiple nullifiers in parallel?
   - Recommendation: Yes, with concurrency limit (e.g., 4 concurrent queries)

3. **Error Handling**: What should happen if PIR check fails mid-way?
   - Recommendation: Log error, skip remaining checks, continue with normal sync

4. **UI Treatment**: Banner vs toast vs inline transaction annotation?
   - Recommendation: SmartBanner for spent detection, toast for "all confirmed"

---

## References

- [PIR Client Integration Doc](https://github.com/z-cale/lightwalletd/blob/adam/lightwalletd-nullifier-precheck-perf/docs/PIR_CLIENT_INTEGRATION.md)
- [PIR Fast Balance Flow](https://github.com/z-cale/lightwalletd/blob/adam/lightwalletd-nullifier-precheck-perf/docs/PIR_FAST_BALANCE_FLOW.md)
- [PIR Nullifier Lookup Flow](https://github.com/z-cale/lightwalletd/blob/adam/lightwalletd-nullifier-precheck-perf/docs/PIR_NULLIFIER_LOOKUP_FLOW.md)
- [lightwalletd service.proto](https://github.com/z-cale/lightwalletd/blob/adam/lightwalletd-nullifier-precheck-perf/lightwallet-protocol/walletrpc/service.proto)
