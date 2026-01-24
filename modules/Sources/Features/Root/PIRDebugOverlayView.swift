//
//  PIRDebugOverlayView.swift
//  Zashi
//
//  Created for PIR Integration Demo
//

import SwiftUI
import ComposableArchitecture
import Perception
import ZcashLightClientKit
import Generated
import UIComponents

/// Debug overlay view showing PIR status and allowing test queries
public struct PIRDebugOverlayView: View {
    @Perception.Bindable var store: StoreOf<Root>

    public init(store: StoreOf<Root>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("PIR Debug")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button {
                    store.send(.pir(.toggleOverlay))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.title2)
                }
            }
            .padding()
            .background(Color.black.opacity(0.9))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status Section
                    statusSection

                    Divider().background(Color.white.opacity(0.3))

                    // Server Info Section
                    serverInfoSection

                    Divider().background(Color.white.opacity(0.3))

                    // Test Query Section
                    testQuerySection

                    Divider().background(Color.white.opacity(0.3))

                    // Results Section
                    resultsSection
                }
                .padding()
            }
            .background(Color.black.opacity(0.85))
        }
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding()
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.subheadline.bold())
                .foregroundColor(.white)

            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(store.pirState.pirState.displayText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                if store.pirState.pirState == .uninitialized {
                    Button("Initialize") {
                        store.send(.pir(.initializePIR))
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
            }

            if let cutoff = store.pirState.cutoffHeight {
                HStack {
                    Text("Cutoff Height:")
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(cutoff)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                }
            }
        }
    }

    private var statusColor: Color {
        switch store.pirState.pirState {
        case .uninitialized: return .gray
        case .initializing: return .yellow
        case .ready: return .green
        case .checking: return .blue
        case .error: return .red
        }
    }

    // MARK: - Server Info Section

    private var serverInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Server Info")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                Spacer()

                Button {
                    store.send(.pir(.fetchStatus))
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }

            if let status = store.pirState.serverStatus {
                VStack(alignment: .leading, spacing: 4) {
                    infoRow("Available:", status.isAvailable ? "Yes" : "No", color: status.isAvailable ? .green : .red)
                    infoRow("Status:", status.status, color: .white)
                    infoRow("PIR DB Height:", "\(status.pirDbHeight)", color: .white)
                    infoRow("Nullifiers:", status.numNullifiers, color: .white)
                    infoRow("Buckets:", status.numBuckets, color: .white)
                    if status.rebuildInProgress {
                        infoRow("Rebuilding:", "Yes (\(status.pendingBlocks) blocks pending)", color: .orange)
                    }
                }
            } else {
                Text("No status info")
                    .foregroundColor(.white.opacity(0.5))
                    .italic()
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(color)
        }
        .font(.caption)
    }

    // MARK: - Test Query Section

    private var testQuerySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test Query")
                .font(.subheadline.bold())
                .foregroundColor(.white)

            HStack {
                TextField("Nullifier (hex)", text: Binding(
                    get: { store.pirState.testNullifier },
                    set: { store.send(.pir(.setTestNullifier($0))) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .autocapitalization(.none)
                .disableAutocorrection(true)

                Button {
                    store.send(.pir(.checkNullifier))
                } label: {
                    if store.pirState.isChecking {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Check")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.pirState.testNullifier.isEmpty ||
                         store.pirState.pirState != .ready ||
                         store.pirState.isChecking)
            }

            // Wallet nullifiers section
            HStack {
                Text("Wallet nullifiers:")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                Spacer()

                Button {
                    store.send(.pir(.fetchWalletNullifiers))
                } label: {
                    if store.pirState.isFetchingNullifiers {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Text("Fetch")
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(store.pirState.isFetchingNullifiers)
            }

            if store.pirState.walletNullifiers.isEmpty {
                Text("No nullifiers fetched yet. Tap 'Fetch' to load from wallet.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .italic()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.pirState.walletNullifiers) { nullifier in
                            Button {
                                store.send(.pir(.selectWalletNullifier(nullifier)))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(nullifier.shortHex)
                                        .font(.system(.caption2, design: .monospaced))
                                    Text(nullifier.pool)
                                        .font(.system(size: 9))
                                        .foregroundColor(nullifier.pool == "sapling" ? .cyan : .purple)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(store.pirState.testNullifier == nullifier.id ? .green : .gray)
                        }
                    }
                }
                Text("\(store.pirState.walletNullifiers.count) nullifiers loaded")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Results")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                Spacer()

                if !store.pirState.recentResults.isEmpty {
                    Button("Clear") {
                        store.send(.pir(.clearResults))
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
            }

            if store.pirState.recentResults.isEmpty {
                Text("No results yet")
                    .foregroundColor(.white.opacity(0.5))
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(store.pirState.recentResults) { result in
                    resultRow(result)
                }
            }
        }
    }

    private func resultRow(_ result: Root.PIRCheckResultDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.nullifierShort)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                Text(result.isSpent ? "SPENT" : "UNSPENT")
                    .font(.caption.bold())
                    .foregroundColor(result.isSpent ? .red : .green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (result.isSpent ? Color.red : Color.green).opacity(0.2)
                    )
                    .cornerRadius(4)
            }

            HStack(spacing: 12) {
                Label("\(String(format: "%.0f", result.uploadKB))KB", systemImage: "arrow.up")
                Label("\(String(format: "%.0f", result.downloadKB))KB", systemImage: "arrow.down")
                Label("\(String(format: "%.0f", result.totalMs))ms", systemImage: "clock")
            }
            .font(.caption2)
            .foregroundColor(.white.opacity(0.6))

            if let height = result.spentAtHeight {
                Text("Spent at block \(height)")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    PIRDebugOverlayView(
        store: Store(
            initialState: Root.State.initial
        ) {
            Root()
        }
    )
    .frame(height: 600)
    .background(Color.gray)
}
