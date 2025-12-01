{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TemplateHaskell       #-}
{-# LANGUAGE NumericUnderscores    #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances     #-}


module SportsTicketsPolicy
  ( TicketMintParams(..)
  , TicketMintRedeemer(..)
  , mkTicketPolicy
  , ticketPolicy
  ) where

import qualified Prelude as Haskell

import PlutusTx
import PlutusTx.Prelude

import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V2.Ledger.Contexts as V2Ctx
import qualified Plutus.V1.Ledger.Value    as Value

--------------------------------------------------------------------------------
-- Parameters & Redeemer
--------------------------------------------------------------------------------

-- | Parameters baked into the minting policy.
--   * tmpOrganizer – who is allowed to mint / burn these tickets
--   * tmpEventId   – event identifier (mainly for off-chain context / grouping)
data TicketMintParams = TicketMintParams
  { tmpOrganizer :: V2.PubKeyHash       -- ^ Who is allowed to mint / burn
  , tmpEventId   :: BuiltinByteString   -- ^ Event id this policy is for
  }

PlutusTx.makeLift ''TicketMintParams

-- | Redeemer distinguishes mint vs burn of a specific seat NFT.
data TicketMintRedeemer
  = MintTicket BuiltinByteString
  | BurnTicket BuiltinByteString
  deriving (Haskell.Eq, Haskell.Show)


PlutusTx.unstableMakeIsData ''TicketMintRedeemer

--------------------------------------------------------------------------------
-- Core policy logic
--------------------------------------------------------------------------------

{-# INLINABLE mkTicketPolicy #-}
mkTicketPolicy :: TicketMintParams -> TicketMintRedeemer -> V2.ScriptContext -> Bool
mkTicketPolicy params redeemer ctx =
  case redeemer of
    MintTicket seat ->
         traceIfFalse "organizer not signed" (signedByOrganizer info)
      && traceIfFalse "wrong minting for seat" (checkMint seat 1)
      && traceIfFalse "no extra tokens under this policy" noExtraUnderPolicy

    BurnTicket seat ->
         traceIfFalse "organizer not signed" (signedByOrganizer info)
      && traceIfFalse "burn must be -1" (checkMint seat (-1))
      && traceIfFalse "no extra tokens under this policy" noExtraUnderPolicy
  where
    info :: V2.TxInfo
    info = V2Ctx.scriptContextTxInfo ctx

    -- The CurrencySymbol of THIS policy in this tx
    cs :: V2.CurrencySymbol
    cs = V2Ctx.ownCurrencySymbol ctx

    minted :: [(V2.CurrencySymbol, Value.TokenName, Integer)]
    minted = Value.flattenValue (V2.txInfoMint info)

    signedByOrganizer :: V2.TxInfo -> Bool
    signedByOrganizer txInfo =
      V2Ctx.txSignedBy txInfo (tmpOrganizer params)

    -- Check exactly one entry for (cs, TokenName seat) with expected amount
    checkMint :: BuiltinByteString -> Integer -> Bool
    checkMint seat expected =
      let tn   = Value.TokenName seat
          ours = [amt | (cs', tn', amt) <- minted, cs' == cs, tn' == tn]
      in case ours of
           [amt] -> amt == expected
           _     -> False

    -- Ensure we don't mint/burn any other tokens under this policy
    noExtraUnderPolicy :: Bool
    noExtraUnderPolicy =
      let underThis = [(tn, amt) | (cs', tn, amt) <- minted, cs' == cs]
      in length underThis == 1

--------------------------------------------------------------------------------
-- Wrap as MintingPolicy
--------------------------------------------------------------------------------

{-# INLINABLE mkWrappedPolicy #-}
mkWrappedPolicy :: TicketMintParams -> BuiltinData -> BuiltinData -> ()
mkWrappedPolicy params r ctxData =
  let redeemer :: TicketMintRedeemer
      redeemer = unsafeFromBuiltinData r

      ctx :: V2.ScriptContext
      ctx = unsafeFromBuiltinData ctxData
  in
    if mkTicketPolicy params redeemer ctx
      then ()
      else traceError "ticket minting policy failed"


ticketPolicy :: TicketMintParams -> V2.MintingPolicy
ticketPolicy params =
  V2.mkMintingPolicyScript $
    $$(PlutusTx.compile [|| \p -> mkWrappedPolicy p ||])
      `PlutusTx.applyCode` PlutusTx.liftCode params

-- -- Off-chain helper to get the CurrencySymbol for these params
-- ticketCurrencySymbol :: TicketMintParams -> V2.CurrencySymbol
-- ticketCurrencySymbol params =
--   let mph :: V2.MintingPolicyHash
--       mph = V2.mintingPolicyHash (ticketPolicy params)
--   in case mph of
--        V2.MintingPolicyHash bs -> V2.CurrencySymbol bs
