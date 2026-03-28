# Share Status Polling — End-to-End Design

This document covers the complete lifecycle of delegated shares: how they leave the iOS wallet, how helpers reveal them on-chain, and how the wallet confirms they landed.

## Contents

- [Share Status Polling — End-to-End Design](#share-status-polling--end-to-end-design)
  - [Contents](#contents)
  - [Overview](#overview)
  - [Terminology](#terminology)
  - [Architecture diagram](#architecture-diagram)
  - [1. Share nullifier derivation](#1-share-nullifier-derivation)
  - [2. Share delegation (POST)](#2-share-delegation-post)
  - [3. Receipt persistence](#3-receipt-persistence)
  - [4. Helper-side processing](#4-helper-side-processing)
  - [5. Status polling](#5-status-polling)
    - [Scanner: `checkPendingShareReveals`](#scanner-checkpendingsharereveals)
    - [Per-group effect: `confirmShareRevealsForGroup`](#per-group-effect-confirmsharerevealsforgroup)
  - [6. Deferred reveal and app-restart recovery](#6-deferred-reveal-and-app-restart-recovery)
  - [7. Partial failure and self-healing](#7-partial-failure-and-self-healing)
  - [8. Resilience properties](#8-resilience-properties)
  - [9. State machine summary](#9-state-machine-summary)
  - [Database schema](#database-schema)
    - [`share_delegations` table (SQLite, scoped to wallet)](#share_delegations-table-sqlite-scoped-to-wallet)
    - [`votes` table (relevant columns)](#votes-table-relevant-columns)
    - [Key queries](#key-queries)
  - [API surface](#api-surface)
    - [Client → Helper](#client--helper)
    - [Helper → Chain](#helper--chain)
    - [Swift client interfaces](#swift-client-interfaces)
  - [Constants and tuning](#constants-and-tuning)

---

## Overview

After a voter's `CastVote` TX confirms on-chain, the wallet sends **encrypted shares** to vote-server helpers. Each helper delays randomly, generates a ZKP #3 proof, and submits `MsgRevealShare` to the chain. The wallet must confirm that these reveals landed; otherwise the vote is committed but unreadable at tally time.

The design is **fire-persist-poll**:

1. **Fire** — POST shares to a quorum of helpers.
2. **Persist** — Store `ShareDelegationReceipt` rows in the voting SQLite DB (one per accepted helper per share).
3. **Poll** — Background polling (`checkPendingShareReveals`) waits until `submit_at`, then queries each helper by nullifier until `confirmed`.

Confirmation does not block the vote submission UX. The user can vote on other proposals while reveals complete in the background.

## Terminology

| Term | Meaning |
|---|---|
| **Share** | One of N encrypted pieces of the vote's secret. Threshold reveals decrypt the vote at tally. |
| **Helper** | A vote-server endpoint (`/api/v1/shares`) that accepts shares, delays, proves ZKP #3, and submits `MsgRevealShare`. Same process as the chain REST API. |
| **Share nullifier** | A deterministic 32-byte Pallas field element derived from the vote commitment. Matches the ZKP #3 circuit's public nullifier so the client can poll for on-chain confirmation without an opaque server token. |
| **Receipt** | A `ShareDelegationReceipt` stored in SQLite: which helper accepted which share, with what nullifier, and the expected `submit_at`. |
| **`submit_at`** | Unix timestamp when the helper should reveal. The wallet samples a random time within the voting window per share for temporal unlinkability. `0` = immediate. |
| **`reveal_confirmed`** | Boolean per receipt row. Set to `true` when the helper's share-status endpoint returns `confirmed` (nullifier is on-chain). |
| **`submitted`** | Boolean on the `votes` table. Set to `true` when all shares for this proposal have been confirmed (reveals landed). This is the vote's "done" flag. |
| **`van_authority_spent`** | Boolean on the `votes` table. Set to `true` immediately after the `CastVote` TX confirms, so the next proposal's ZKP #2 sees the decremented proposal-authority bitmask. Separate from `submitted`. |

## Architecture diagram

```
┌──────────────────────────────────────────────────────────────┐
│                        iOS Wallet                            │
│                                                              │
│  CastVote TX confirmed                                       │
│        │                                                     │
│        ▼                                                     │
│  markVanAuthoritySpent()                                     │
│        │                                                     │
│  1111                             │
│  delegatePersistAndConfirmShares()                            │
│    ├─ POST /api/v1/shares ──► Helper A  (share 0, 2)         │
│    ├─ POST /api/v1/shares ──► Helper B  (share 0, 1, 3)      │
│    ├─ POST /api/v1/shares ──► Helper C  (share 1, 2, 3)      │
│    └─ persist receipts to SQLite                             │
│        │                                                     │
│        ▼                                                     │
│  .sharesAwaitingRevealRecorded ──► .checkPendingShareReveals │
│        │                                                     │
│        ▼                                                     │
│  (user continues voting on other proposals)                  │
│                                                              │
│  checkPendingShareReveals (lightweight scanner):             │
│    ├─ triggered: app foreground / governance open / post-vote│
│    ├─ listPendingShareReveals from DB                        │
│    ├─ per group within 5-min window:                         │
│    │      dispatch .confirmShareRevealsForGroup (per-group)  │
│    └─ per group beyond window: log and defer to next trigger │
│                                                              │
│  confirmShareRevealsForGroup (per-group, independent):       │
│    ├─ sleep until max(submit_at) for this group              │
│    ├─ poll GET /api/v1/share-status/{roundId}/{nullifier}    │
│    │      on each receipt's helper_url                        │
│    ├─ on "confirmed" → markShareRevealedForHelper()          │
│    ├─ on timeout → resubmitShare() to same helper, poll again│
│    └─ all shares confirmed → markVoteSubmitted()             │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                     Helper (svoted)                           │
│                                                              │
│  POST /api/v1/shares                                         │
│    └─ enqueue share, return "queued" / "duplicate"           │
│                                                              │
│  Processor loop (Poisson-timed):                             │
│    ├─ TakeReady() — shares whose delay elapsed               │
│    ├─ fetch VC Merkle path from vote-commitment tree         │
│    ├─ generate ZKP #3 (share-reveal proof)                   │
│    ├─ build MsgRevealShare with share_nullifier              │
│    └─ submit to chain                                        │
│                                                              │
│  GET /api/v1/share-status/{roundId}/{nullifier}              │
│    └─ HasShareNullifier() — checks vote keeper KV store      │
│       returns "pending" or "confirmed"                       │
└──────────────────────────────────────────────────────────────┘
```

## 1. Share nullifier derivation

The share nullifier is computed identically in the Rust library and in the ZKP #3 circuit, so the client can derive it locally without any server round-trip.

```
vc = vote_commitment_hash(round_id, shares_hash, proposal_id, vote_decision)
share_nullifier = share_nullifier_hash(vc, share_index, primary_blind)
```

Both Poseidon hashes use the same domain tags as `voting_circuits::share_reveal`.

**Source:** `librustvoting/src/vote_commitment.rs` → `compute_share_nullifier()`
**Types:** `ShareDelegationReceipt` and `PendingShareRevealGroup` are defined in `librustvoting/src/storage/mod.rs`.

The nullifier is:
- Computed once per share during `build_share_payloads`.
- Included in each `SharePayload` struct (used client-side for polling; not sent to helpers — they derive it independently in the ZKP #3 circuit).
- Stored in each `ShareDelegationReceipt` for polling.
- Submitted by the helper as a public input in `MsgRevealShare`.
- Recorded in the vote keeper's nullifier set on-chain after the TX confirms.

## 2. Share delegation (POST)

After `CastVote` TX confirms, the wallet builds share payloads and POSTs them to helpers.

**Flow in `VotingAPIClientLiveKey.swift` → `delegateShares`:**

1. Get the list of healthy vote servers from `ServerHealthTracker`.
2. Compute quorum: `max(1, (healthy.count + 1) / 2)`.
3. For each share payload:
   a. Pick `quorum` servers at random (independent per share for unlinkability).
   b. POST to all targets concurrently.
   c. Accept servers that return `"queued"` or `"duplicate"`.
   d. If all quorum servers fail, try remaining healthy servers as sequential fallback.
   e. Create a `ShareDelegationReceipt` for each accepting server (with `seq` preserving target order).
4. **Partial success:** Return all accumulated receipts. Only throw if zero receipts total.

Each share is sent to `quorum` servers independently, so no single helper sees a correlated subset of the voter's shares.

The POST body includes `submit_at` — a per-share random Unix timestamp within the voting window. The helper respects this as the earliest reveal time.

## 3. Receipt persistence

**Flow in `VotingStore.swift` → `delegatePersistAndConfirmShares`:**

1. Check for existing receipts (crash-retry guard). If already present, return.
2. Clear stale receipts, call `delegateShares`, persist returned receipts.
3. Retry up to 3 times (2s pause) on total failure.
4. This function does **not** poll — that is deferred to `checkPendingShareReveals`.

Each receipt is stored via `VotingCryptoClient.storeShareDelegationReceipt` → Rust FFI → SQLite `share_delegations` table.

**Receipt fields:**

| Field | Purpose |
|---|---|
| `share_index` | Which share (0..N-1) |
| `helper_url` | The server that accepted this share |
| `share_nullifier` | 32-byte deterministic nullifier for polling |
| `seq` | Target ordering (0 = primary polling server) |
| `submit_at` | Unix seconds when the helper should reveal |
| `reveal_confirmed` | `false` until the helper reports on-chain confirmation |

## 4. Helper-side processing

**Processor loop** (`sdk/internal/helper/processor.go`):

1. Wakes at Poisson-distributed intervals (exponential inter-arrival, mean configurable) for temporal unlinkability.
2. `TakeReady()` returns shares whose delay has elapsed (`submit_at` ≤ now).
3. For each share (bounded concurrency):
   a. Verify the round is still active.
   b. Fetch the VC Merkle path from the vote-commitment tree at `tree_position`.
   c. Decode share commitments, blind, and ciphertext.
   d. Call `GenerateShareRevealProof()` — ZKP #3.
   e. Build `MsgRevealShare` (includes `share_nullifier` as base64).
   f. Submit to chain via `ChainSubmitter.SubmitRevealShare()` → `POST /shielded-vote/v1/reveal-share`.
4. On success, the chain records the share nullifier in the vote keeper's KV store.

**Intra-share delay:** Between shares in a batch, the processor adds another exponential delay (half the inter-cycle mean) so multiple shares from the same voter aren't submitted back-to-back.

## 5. Status polling

**Client-side** (`VotingStore.swift`):

The polling system uses a **scanner + per-group effect** architecture for resilience. Voting on a new proposal does not cancel polling for a previous proposal.

### Scanner: `checkPendingShareReveals`

A lightweight TCA effect (`.cancellable(cancelInFlight: true)`) that reads the DB and dispatches per-group effects. Triggered:
- After share delegation completes (`.sharesAwaitingRevealRecorded`).
- On every governance page open / app restart (`.allRoundsLoaded`).
- On every app foreground (`willEnterForeground` in `RootInitialization` sends `.voting(.checkPendingShareReveals)`).
- After the delegation proof finishes (`.delegationProofCompleted` / `.delegationProofFailed`) — ensures groups that were blocked by `isDelegationProofInFlight` are picked up promptly.

The scanner calls `listPendingShareReveals()` and dispatches per-group effects for **all rounds** with pending groups. UI progress updates (pending-proposal set, progress bars) are scoped to the currently-viewed round for display purposes, but confirmation effects run for every round.

For each group:
- If `max(submit_at)` is within 5 minutes → dispatch `.confirmShareRevealsForGroup(group)`.
- If beyond 5 minutes → skip and track as deferred.

Groups beyond the 5-minute window are deferred. They will be picked up on the next scanner run, which happens on every app foreground or governance screen open. This avoids long-lived `Task.sleep` calls that would not survive iOS app suspension.

### Per-group effect: `confirmShareRevealsForGroup`

Each group runs as an independent TCA effect with a `ShareRevealGroupCancelID` (keyed on `roundId + bundleIndex + proposalId`). Multiple groups run concurrently. A guard prevents duplicate effects for the same group.

Per group:

1. Fetch the round via `fetchRoundById` to determine `isLastMoment` (single-share mode). On transient failure, the effect waits 30 seconds and re-dispatches `.checkPendingShareReveals` so the group is retried on the next scanner pass rather than silently abandoned.
2. Rebuild share payloads from the persisted `VoteCommitmentBundle` and the vote's `choice` (stored after `CastVote` TX). The `isLastMoment` flag determines whether a single share or multiple shares are built.
3. Restore `submit_at` values from receipt rows.
4. Call `confirmAllSharesForVote()` **concurrently with a 10-second progress ticker** (via `withThrowingTaskGroup`). The ticker re-reads all receipt rows from the DB and sends `shareProgressUpdated` to the UI so the per-proposal progress bars update as individual shares are confirmed. The ticker is cancelled when the polling task completes.
5. On completion (success or error), send `.shareRevealGroupFinished` to remove the group from the active set.

**Per share** (`confirmAllSharesForVote` — concurrent):

All shares are polled **concurrently** via `withThrowingTaskGroup`. Each share task independently:

1. Sleeps until **its own** `submit_at` (not the group max). A share with `submit_at = 0` starts polling immediately while later shares are still sleeping.
2. **Has receipts:** Sort by `seq`, poll each unconfirmed helper via `pollAndMaybeResubmitOneHelper()`.
3. **No receipts (partial failure recovery):** Try `resubmitShare()` to servers known from other shares' receipts. Persist the new receipt.
4. Returns whether quorum was reached for this share.

The function returns `true` only when all share tasks report quorum reached.

**Per helper** (`pollAndMaybeResubmitOneHelper`):

1. `pollShareWithBackoff()`: Exponential backoff — 20s, 40s, 80s, 160s, 320s (5 attempts, ~10.3 min total).
2. Each poll calls `GET /api/v1/share-status/{roundId}/{nullifier}` on the **same helper URL** that accepted the share.
3. If `"confirmed"` → `markShareRevealedForHelper()`, done.
4. If timed out → re-POST the share to the same helper via `resubmitShare()`, then poll again (same backoff).
5. If still timed out → return `false`.

**Quorum for confirmation:**

Per share, `requiredDistinct = 2` if the share was accepted by ≥ 2 helpers, otherwise `1`. This ensures redundant reveals are confirmed before marking the vote as submitted.

**Server-side** (`sdk/internal/helper/api.go` → `handleShareStatus`):

`GET /api/v1/share-status/{roundId}/{nullifier}`:
- Validates both path params as 64-character hex (32 bytes).
- Calls `ShareNullifierChecker(roundIDHex, shareNullifierBytes)`.
- Implementation: `keeperTreeReader.HasShareNullifier()` checks the vote keeper's KV store for `NullifierTypeShare`.
- Returns `{"status": "pending"}` or `{"status": "confirmed"}`.

## 6. Deferred reveal and app-restart recovery

**The 5-minute threshold:**

```swift
private let shareRevealNearThresholdSeconds: TimeInterval = 300
```

When the scanner runs:
- Groups whose `max(submit_at)` is within 5 minutes: dispatched as per-group effects immediately.
- Groups whose `max(submit_at)` is farther out: skipped and logged. They will be picked up on the next scanner run (triggered by app foreground or governance open).

**App-restart path:**

The scanner is triggered on every app foreground (`willEnterForeground` → `.voting(.checkPendingShareReveals)`) and every governance screen appear (`.allRoundsLoaded`). It calls `listPendingShareReveals()` which queries all `share_delegations` rows with `reveal_confirmed = 0` joined against `votes.submitted = 0`. Any groups within the 5-minute window are dispatched as per-group effects. Groups farther out are deferred until the next trigger.

**Concurrent voting:**

When the user votes on proposal B while proposal A's group effect is running, the scanner re-runs (`.sharesAwaitingRevealRecorded` → `.checkPendingShareReveals`) and dispatches a new group effect for B. The existing effect for A is **not cancelled** — each group has its own cancellation scope (`ShareRevealGroupCancelID`). A duplicate dispatch for A is suppressed by the `activeShareRevealGroupIDs` guard.

**What survives a crash:**

| Data | Persistence | Recovery |
|---|---|---|
| CastVote TX hash | `votes.tx_hash` in SQLite | Crash recovery checks chain for confirmation |
| VAN authority spent | `votes.van_authority_spent` in SQLite | Immediate after CastVote TX, before shares |
| Share payloads | Rebuilt from persisted `VoteCommitmentBundle` + vote choice | `buildSharePayloads()` is deterministic given the same bundle |
| Receipt per helper | `share_delegations` in SQLite | Survives crash. Used to resume polling. |
| `submit_at` per share | `share_delegations.submit_at` | Restored to rebuilt payloads before polling |

## 7. Partial failure and self-healing

**Scenario: some shares accepted, some not**

`delegateShares` returns partial receipts (only throwing on total zero). Receipts for accepted shares are persisted. When `confirmAllSharesForVote` runs, it iterates all share indices from payloads — not just those with receipt rows. For shares with no receipts, it attempts fresh submission via `resubmitShare()` to servers known from other shares' receipts.

**Scenario: crash between POST and DB write**

Some shares are on a helper but no local receipt. On restart, `checkPendingShareReveals` finds partial receipts from other shares. `confirmAllSharesForVote` sends the missing shares via `resubmitShare()`. The original helper returns `"duplicate"` (which counts as acceptance). A new receipt is created and polling proceeds.

**Scenario: total POST failure (infrastructure down)**

All 3 retry attempts in `delegatePersistAndConfirmShares` fail with zero receipts. The error surfaces to the user as a vote submission failure. The `CastVote` TX is on-chain but shares were never delegated. This is the only unrecoverable case — genuine infrastructure outage.

**Failure matrix:**

| Scenario | CastVote TX | Receipts | Recoverable? |
|---|---|---|---|
| Happy path | Confirmed | All shares | Yes |
| Partial POST failure | Confirmed | Some shares | Yes — missing shares resubmitted to known servers |
| Total POST, retry succeeds | Confirmed | All shares | Yes |
| Crash after POST, before DB write | Confirmed | Some/none | Yes — resubmit produces "duplicate" on original server |
| Total POST failure, all retries | Confirmed | None | No — thrown to user (infra down) |

## 8. Resilience properties

The scanner + per-group architecture provides four resilience guarantees:

**Per-group error isolation.** Each group's confirmation runs in its own TCA effect with an independent `do/catch`. If proposal A's helper is unreachable, proposal B's confirmation proceeds normally. In the previous serial design, one group's error aborted all remaining groups.

**No cross-proposal cancellation.** Each group effect has a unique `ShareRevealGroupCancelID` keyed on `(roundId, bundleIndex, proposalId)`. When the user votes on a new proposal, the scanner re-dispatches but existing group effects are not cancelled. A duplicate dispatch for an already-running group is suppressed by the `activeShareRevealGroupIDs` state guard.

**App-foreground sweep for deferred groups.** The scanner runs on every `willEnterForeground` (not just governance screen open), so deferred groups are picked up as soon as the user returns to the app for any reason. This avoids long-lived `Task.sleep` calls that would not survive iOS app suspension.

**Active effect cleanup.** On `.dismissFlow`, all tracked per-group effect IDs are cancelled alongside the scanner, preventing orphaned background work. The `activeShareRevealGroupIDs` set is cleared.

## 9. State machine summary

Per vote (one proposal within a bundle):

```
CastVote TX confirmed
     │
     ▼
markVanAuthoritySpent ──────────────────────────────────────┐
     │                                                      │
     ▼                                                      │ (VAN bitmask updated
delegatePersistAndConfirmShares                             │  for next proposal)
     │                                                      │
     ├── POST shares → partial/full receipts persisted      │
     │                                                      │
     ▼                                                      │
.sharesAwaitingRevealRecorded(proposalId)                   │
     │                                                      │
     ▼                                                      │
.checkPendingShareReveals (scanner)                         │
     │                                                      │
     ├── within 5 min → dispatch per-group effect ─────┐    │
     │                                                  │    │
     ├── beyond 5 min → defer to next app foreground     │    │
     │                                                  │    │
     │   .confirmShareRevealsForGroup (concurrent)      │    │
     │    ├── confirmAllSharesForVote (all 16 parallel) │    │
     │    │    ├── share 0: sleep(own submit_at), poll  │    │
     │    │    ├── share 1: sleep(own submit_at), poll  │    │
     │    │    ├── ...                                  │    │
     │    │    └── share 15: sleep(own submit_at), poll │    │
     │    │         all quorum?                         │    │
     │    │         ├── yes ────────────────────┐       │    │
     │    │         └── no → return false       │       │    │
     │    │              (retry on next scan)   │       │    │
     │    ├── progress ticker (10s DB re-read)  │       │    │
     │    └── .shareRevealGroupFinished         ▼       │    │
     │                                 markVoteSubmitted │    │
     │                                 .shareRevealsConf │    │
     │                                         │        │    │
     └─────────────────────────────────────────┘────────┘    │
                                                             │
     (user can vote on other proposals immediately) ◄────────┘

     Note: each group effect runs independently — voting on
     proposal B does NOT cancel the polling for proposal A.
```

## Database schema

### `share_delegations` table (SQLite, scoped to wallet)

```sql
CREATE TABLE share_delegations (
    round_id          TEXT NOT NULL,
    wallet_id         TEXT NOT NULL DEFAULT '',
    bundle_index      INTEGER NOT NULL,
    proposal_id       INTEGER NOT NULL,
    share_index       INTEGER NOT NULL,
    helper_url        TEXT NOT NULL,
    share_nullifier   BLOB NOT NULL,
    seq               INTEGER NOT NULL DEFAULT 0,
    created_at        INTEGER NOT NULL,
    submit_at         INTEGER NOT NULL DEFAULT 0,
    reveal_confirmed  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (round_id, wallet_id, bundle_index, proposal_id, share_index, helper_url),
    FOREIGN KEY (round_id, wallet_id, bundle_index)
        REFERENCES bundles(round_id, wallet_id, bundle_index) ON DELETE CASCADE
);
```

### `votes` table (relevant columns)

| Column | Purpose |
|---|---|
| `choice` | The voter's decision (option index). Required to deterministically rebuild share payloads during confirmation polling. |
| `submitted` | `1` when all share reveals are confirmed (vote fully done) |
| `van_authority_spent` | `1` after CastVote TX confirms (VAN bitmask decrement for next proposal) |

### Key queries

- **`list_pending_share_reveal_groups`**: Finds `(round, bundle, proposal)` tuples with at least one `reveal_confirmed = 0` row joined against `votes.submitted = 0`.
- **`list_pending_receipts_for_vote`**: Returns unconfirmed receipt rows for a specific vote.
- **`mark_share_revealed_for_helper`**: Sets `reveal_confirmed = 1` for a specific receipt.

## API surface

### Client → Helper

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/api/v1/shares` | Submit encrypted share payload. Returns `{"status": "queued"}` or `{"status": "duplicate"}`. |
| `GET` | `/api/v1/share-status/{roundId}/{nullifier}` | Poll share reveal status. Both params are 64-character lowercase hex. Returns `{"status": "pending"}` or `{"status": "confirmed"}`. |

### Helper → Chain

| Method | Endpoint | Purpose |
|---|---|---|
| `POST` | `/shielded-vote/v1/reveal-share` | Submit `MsgRevealShare` with ZKP #3 proof and share nullifier. |

### Swift client interfaces

| Dependency | Method | Signature |
|---|---|---|
| `VotingAPIClient` | `delegateShares` | `([SharePayload], String) async throws -> [ShareDelegationReceipt]` |
| `VotingAPIClient` | `fetchShareSubmissionStatus` | `(String, String, String) async throws -> String` |
| `VotingAPIClient` | `resubmitShare` | `(SharePayload, String, String) async throws -> Bool` |
| `VotingCryptoClient` | `clearShareDelegationReceiptsForVote` | `(String, UInt32, UInt32) async throws -> Void` |
| `VotingCryptoClient` | `storeShareDelegationReceipt` | `(String, UInt32, UInt32, ShareDelegationReceipt) async throws -> Void` |
| `VotingCryptoClient` | `listShareDelegationReceipts` | `(String, UInt32, UInt32) async throws -> [ShareDelegationReceipt]` |
| `VotingCryptoClient` | `markShareRevealedForHelper` | `(String, UInt32, UInt32, UInt32, String) async throws -> Void` |
| `VotingCryptoClient` | `listPendingShareReveals` | `() async throws -> [PendingShareRevealGroup]` |
| `VotingCryptoClient` | `markVoteSubmitted` | `(String, UInt32, UInt32) async throws -> Void` |

## Per-proposal progress tracking

Each proposal card in the governance list shows two segmented progress bars once shares have been delegated:

| Bar | Metric | Source |
|---|---|---|
| **Sent** (blue) | Distinct `share_index` values with at least one receipt row | `listShareDelegationReceipts` (all receipts, no `reveal_confirmed` filter) |
| **Confirmed** (green) | Distinct `share_index` values where any receipt has `reveal_confirmed = 1` | Same query |

Progress is refreshed at four points:

1. **`sharesAwaitingRevealRecorded`** — immediately after receipts are persisted.
2. **`checkPendingShareReveals`** — on every scanner run (governance open, app restart, self-reschedule).
3. **Progress ticker** — every 10 seconds concurrently with the per-group polling effect.
4. **`shareRevealGroupFinished`** — when a group's polling completes.

State: `Voting.State.shareProgress: [UInt32: ShareProgress]` (keyed by `proposalId`). Cleared on round change.

## Constants and tuning

| Constant | Value | Location | Purpose |
|---|---|---|---|
| `sharePollBackoffBaseSeconds` | 20s | `VotingStore.swift` | Base delay for exponential backoff (20, 40, 80, 160, 320s) |
| `shareRevealNearThresholdSeconds` | 300s (5 min) | `VotingStore.swift` | Max lookahead for `submit_at`; farther = deferred |
| Poll attempts per helper | 5 | `pollShareWithBackoff` | ~10.3 min total polling window per helper |
| Share delegation retries | 3 | `delegatePersistAndConfirmShares` | Full POST retries on total failure |
| Helper quorum | `max(1, ⌈healthy/2⌉)` | `delegateShares` | Servers targeted per share |
| Required confirmations per share | 2 (if ≥2 receipts) else 1 | `confirmAllSharesForVote` | On-chain reveal quorum |
| Progress ticker interval | 10s | `confirmShareRevealsForGroup` | DB re-read for UI progress bars |
| Processor mean interval | configurable | `Processor` | Mean of Poisson-timed reveal loop |
| Intra-share delay | `meanInterval / 2` | `Processor` | Jitter between reveals in a batch |
