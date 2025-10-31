{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}

module AtomicSwap.Types where

-- Plutus V2 core types
import Plutus.V2.Ledger.Api ( Address, Credential, POSIXTime )
-- Multi-asset Value (V1 module is where Value/CurrencySymbol/TokenName live)
import Plutus.V1.Ledger.Value ( Value, CurrencySymbol, TokenName)
-- Builtin bytes for version tags / HTLC preimages
import PlutusTx.Builtins ( BuiltinByteString )

import GHC.Generics ( Generic )

------------------------------------------------------------
-- Parameters (static, set at deploy time)
------------------------------------------------------------

-- | Script parameters (fixed when you compile/deploy the validator).
-- Keep them minimal and immutable.

data SwapParams = SwapParams
  { spOperator        :: !(Maybe Address) -- ^ Optional protocol/marketplace fee recipient.
  , spBeaconPolicyId  :: !(Maybe CurrencySymbol) -- ^ Optional "beacon" (SwapId) policy to identify listings & prevent replay.
  , spVersionTag      :: !BuiltinByteString -- ^ Opaque fingerprint/version tag to make migrations explicit.
  }
  deriving (Show, Eq, Generic)

-------------------------------------------------------
-- Expectation & payout modelling
-------------------------------------------------------

-- | How the listing specifies what the taker must pay.
-- Start with exact equality; you can extend later if needed.

data Expectation
  = ExpectExact !Value
    -- ^ Taker must pay exactly this Value (no slippage).
  deriving (Show, Eq, Generic)

-- | Proceeds routing: who gets paid and in what assets.
-- Using 'Value' per recipient lets you support ADA and multi-asset splits.
data Payout = Payout
  { pAddress :: !Address
  , pValue   :: !Value
  }
  deriving (Show, Eq, Generic)
  
-- | Behaviour flags for the listing (keep it strict by default).
data Flags = Flags
  { fSingleFill       :: !Bool  -- ^ true ⇒ no continuing script output on Buy
  , fAllowPartial     :: !Bool  -- ^ usually False for atomic swaps
  , fRespectRoyalties :: !Bool  -- ^ if you plan to enforce royalty splits
  }
  deriving (Show, Eq, Generic)

-------------------------------------------------------
-- Datum (per listing, inline - CIP-32)
-------------------------------------------------------

-- | Optional “beacon” (SwapId) to uniquely mark the listing UTxO.
-- Pair of policy + token name.
type SwapId = (CurrencySymbol, TokenName)

data SwapDatum = SwapDatum
  { sdSwapId    :: !(Maybe SwapId)          -- ^ Unique listing id (beacon NFT) [optional but recommended]
  , sdSeller    :: !Credential              -- ^ Who may cancel after deadline (auth checked in validator)
  , sdOffer     :: !Value                   -- ^ Asset bundle held at the listing UTxO (what the buyer receives)
  , sdExpect    :: !Expectation             -- ^ What the buyer must pay (strict equality) (exact by default)
  , sdPayouts   :: ![Payout]                -- ^ How to split 'sdExpect' across recipients (seller/fees/royalties)
  , sdDeadline  :: !POSIXTime               -- ^ fter this, seller can Cancel; before this, Buy must occur.
  , sdFlags     :: !Flags                    -- ^ Behaviour switches (single-fill, partials, royalties).
  , sdHashLock  :: !(Maybe BuiltinByteString) -- ^ (Optional HTLC) blake2b_256(preimage) expected (store the HASH here)
  , sdExpiryResponder :: !(Maybe POSIXTime)    -- ^ (Optional HTLC) Cardano-side timeout for responder
  }
  deriving (Show, Eq, Generic)

-------------------------------------------------------
-- Redeemer (intent)
-------------------------------------------------------

data SwapRedeemer
  = Buy                          -- ^ Taker fills the order  (validator enforces exact payouts & one-shot).
  | Cancel                       -- ^ Seller cancels after 'sdDeadline' (auth + full refund of 'sdOffer').
  | ClaimWithPreimage !BuiltinByteString -- ^ (Optional HTLC) provide the preimage whose hash matches 'sdHashLock'.
  deriving (Show, Eq, Generic)

{-|
Atomic Token Swap — Contract Surface (Plutus V2)

1) Script Parameters (static, set at deploy/compile)
   - operator        :: Address (optional protocol fee recipient)
   - swapIdPolicyId  :: PolicyId (optional beacon policy to ensure 1-per-listing)
   - versionTag      :: BuiltinByteString (script/version fingerprint)

2) Datum (per-listing, inline — CIP-32)
   - swapId    :: AssetClass         -- unique listing id (beacon NFT) [optional but recommended]
   - seller    :: PaymentCredential  -- who may cancel after deadline
   - offer     :: Value              -- asset bundle held at the listing UTxO
   - expect    :: Value              -- exact bundle buyer must pay (strict equality)
   - payouts   :: [(Address,Integer)]-- exact routing of proceeds (seller, operator, royalties)
   - deadline  :: POSIXTime          -- cancel after this time
   - flags     :: { singleFill = True, allowPartial = False, respectRoyalties = Bool }
   - (Optional HTLC)
       hashLock         :: BuiltinByteString  -- blake2b_256(s)
       expiryResponder  :: POSIXTime          -- Cardano-side timeout for responder

   NOTE: Keep datums INLINE to avoid datum-hash mismatch issues.

3) Redeemers (intents)
   - Buy                    -- taker fills the order
   - Cancel                 -- seller cancels after deadline
   - (Optional) ClaimWithPreimage BuiltinByteString  -- provide HTLC preimage

Design Notes:
- Use CIP-33 reference scripts for cheaper “Buy” spends.
- Prefer exact equality on Value & recipient pinning (no ≥ matches).
- Enforce single-fill: no continuing script state on Buy.
- If you adopt beacons, ensure the listing input carries the beacon and its lifecycle is handled on spend.
-}