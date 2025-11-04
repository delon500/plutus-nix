{-# LANGUAGE NamedFieldPuns #-}

module AtomicSwap.Validator where
-- Plutus V2 ledger types available in this repo version
import Plutus.V2.Ledger.Api
  ( ScriptContext(..)
  , ScriptPurpose(..)
  , TxInfo(..)
  , TxInInfo(..)
  , TxOut(..)
  , Address(..)
  , Credential(..)
  , POSIXTime
  , POSIXTimeRange
  , Value
  )

-- We'll need Prelude-like stuff from PlutusTx.Prelude when we start writing
-- actual on-chain logic (traceIfFalse, etc.). For now we only document.
-- We'll import PlutusTx.Prelude later when we actually implement.
-- import PlutusTx.Prelude (...) 

import qualified Plutus.V2.Ledger.Api as V2 
import qualified Plutus.V1.Ledger.Interval as I 

-- on-chain-ish Prelude
import PlutusTx.Prelude
  ( Bool(..)
  , (==)
  , traceIfFalse
  , traceError
  , elem
  , mconcat
  )

import Prelude (Maybe(..))

import AtomicSwap.Types
  ( SwapParams(..)
  , SwapDatum(..)
  , SwapRedeemer(..)
  , Expectation(..)
  , Payout(..)
  , Flags(..)
  )

-- [CXL1] tx must be at/after sdDeadline 
validAfterDeadline :: POSIXTime -> TxInfo -> Bool
validAfterDeadline deadline info =
  I.contains (I.from deadline) (V2.txInfoValidRange info) 

-- [CXL2] only the seller (PubKeyCredential) may cancel
sellerSigned :: Credential -> TxInfo -> Bool
sellerSigned cred info = 
       case cred of
         PubKeyCredential pkh -> pkh `elem` V2.txInfoSignatories info 
         _                   -> False -- script credentials can't "sign"

-- [CXL3] full refund back to seller, no leakage
refundIsExact :: Credential -> Value -> TxInfo -> Bool
refundIsExact sellerCred offer info =
  let outs = V2.txInfoOutputs info

      toSeller =
        [ txOutValue o
        | o <- outs
        , let addr = txOutAddress o
        , addrCredential addr == sellerCred
        ]

      paidToSeller = mconcat toSeller
  in  paidToSeller == offer
  where
    addrCredential (Address cred _stake) = cred

-- actual cancel rule 
validateCancel :: SwapDatum -> TxInfo -> Bool 
validateCancel SwapDatum{sdSeller, sdOffer, sdDeadline} info =
     traceIfFalse "Cancel: too early" (validAfterDeadline sdDeadline info) &&
     traceIfFalse "Cancel: not seller" (sellerSigned sdSeller info) && 
     traceIfFalse "Cancel: bad refund" (refundIsExact sdSeller sdOffer info)

-- Buy stub (to be done later)
validateBuy :: SwapDatum -> SwapRedeemer -> TxInfo -> Bool
validateBuy _ _ _ = 
       traceError "Buy path not implemented"

-- Top-level validator
mkSwapValidator :: SwapParams -> SwapDatum -> SwapRedeemer -> ScriptContext -> Bool
mkSwapValidator _params datum redeemer ScriptContext{scriptContextTxInfo=info} =
     case redeemer of
       Cancel      -> validateCancel datum info
       Buy -> validateBuy datum redeemer info 
       ClaimWithPreimage _ -> traceError "HTLC path not implemented"


{-|
Validator logic (high-level, to be implemented):

We will match on the redeemer:

1. Cancel
   Must enforce ALL of these:

   [CXL1] Time check:
          txValidRange must be AT or AFTER sdDeadline.
          So: transaction validity interval starts ≥ sdDeadline.

   [CXL2] Authorization:
          The tx must be signed by sdSeller (the seller in the datum),
          or otherwise prove control of that credential.

   [CXL3] Refund:
          The full sdOffer (exact Value) must be paid back to the seller.
          No one else keeps any piece of sdOffer.

   [CXL4] Beacon cleanup (optional if you use beacons):
          If sdSwapId is Just (policyId, tokenName),
          the transaction that consumes this listing UTxO must either
          burn that beacon or not leave it sitting somewhere pretending
          there's still an active listing.
          (We'll enforce that later using the minting policy.)

   Summary:
     Cancel = "seller can recover their locked offer after deadline, nobody else gets it".

2. Buy
   Must enforce ALL of these:

   [BUY1] Payouts:
          sdExpect describes what must be paid in. For ExpectExact vExpect:
            - The transaction outputs must pay each Payout {pAddress, pValue}
              exactly. No missing, no short pay, no redirect.
            - Combined payouts must add up to vExpect exactly.
              (No skimming, no dust tricks.)

   [BUY2] Offer delivery:
          The entire sdOffer must go to the taker (the buyer).
          We’ll define how to identify the taker (probably from the redeemer,
          or we could say: first non-script output that holds sdOffer).

   [BUY3] No continuing script output:
          fSingleFill should be True. That means the listing UTxO is consumed
          and there is NO new output at the same script address carrying any
          leftover portion of sdOffer. One-shot only.

   [BUY4] Deadline window:
          Optionally enforce that Buy happens BEFORE sdDeadline,
          so after deadline you can't buy, only cancel.

   [BUY5] HTLC (optional):
          If sdHashLock = Just h, then in the Buy case:
            - the redeemer must be ClaimWithPreimage preimage
            - blake2b_256(preimage) == h
            - and you only allow Buy if that matches.
          If sdHashLock = Nothing, plain Buy is fine.

   [BUY6] Beacon cleanup (optional):
          Similar to Cancel: consuming the listing should retire the beacon.

Notes on implementation:
- We will look at TxInfo.inputs to find the consumed script UTxO and its datum.
- We will look at TxInfo.outputs to verify:
    * where sdOffer went
    * how payouts were split
    * that no new listing UTxO was created
- We will look at TxInfo.validRange for time checks.
- We will look at TxInfo.signatories to confirm seller auth in Cancel.

The tests in AtomicSwapSpec will exercise these rules.
-}