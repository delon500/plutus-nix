module AtomicSwap.BeaconPolicy where
-- TODO: One-per-listing beacon rules (mint/burn/guardrails)
{-|
Atomic Token Swap — Beacon Minting Policy (design notes)

Purpose:
  - Mint exactly one beacon NFT (e.g., "SwapId#<nonce>") per listing UTxO.
  - Pin the beacon to the listing so it cannot be re-used/replayed elsewhere.
  - Burn (or move under rules) on Buy/Cancel to close the listing cleanly.

Policy Parameters (fixed at compile/deploy):
  - scriptHashListing :: ScriptHash
      -- The validator hash of the AtomicSwap listing script (ties mint to listing).
  - versionTag        :: BuiltinByteString
      -- Optional fingerprint / versioning.
  - (Optional) operator :: Address
      -- If you want an operator to be able to mint/burn, else restrict to seller.

Minting Constraints (at listing creation):
  [M1] Exactly +1 unit of the beacon asset is minted (NFT semantics).
  [M2] The tx MUST create exactly one output at the listing script address (scriptHashListing)
       that *contains* the newly minted beacon AND the inline datum for this listing.
  [M3] The beacon token name scheme:
       - tokenName = "SwapId#" <> <nonce or hash>
       - (Optionally) ensure tokenName embeds a hash of the inline datum to bind identity.
  [M4] (Optional) Require seller’s signature to mint their own beacon.
  [M5] (Optional) Prevent multiple beacons per tx to avoid accidental batches.

Burning / Closing Constraints (on Buy or Cancel):
  [B1] Exactly -1 unit of that same beacon is burned in the tx that consumes the listing UTxO,
      OR (alternative) require the beacon to be paid to a specific sink address/policy.
  [B2] The listing UTxO is *also* consumed in this tx (prevents stray burns without closing).
  [B3] (Optional) Require either:
       - Buy path: no continuing script output (single-fill).
       - Cancel path: seller signature present.
  [B4] No additional beacons minted in the same tx (net = -1).

Replay / Relist Considerations:
  - If you want to allow *relisting* the same beacon id, you must define explicit rules
    (e.g., re-mint only if previous was provably burned in prior tx and new datum differs).
  - Simpler approach: never re-mint the same token name; always mint a fresh nonce.

Indexer & Discovery:
  - UI/indexer watches for UTxOs at `scriptHashListing` that *contain* this beacon policy id.
  - The presence of the beacon + inline datum = “active listing”.

Operational Notes:
  - Enforce small, deterministic checks for budget predictability.
  - Keep token naming deterministic from off-chain builder to simplify testing/UX.

Pitfalls to Avoid:
  - Allowing mint without simultaneously creating the listing output.
  - Forgetting to burn on close (leaves “ghost” active-looking listings).
  - Letting multiple beacons through in one tx (user misconfig).
-}