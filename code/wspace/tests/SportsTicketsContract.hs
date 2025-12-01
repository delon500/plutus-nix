{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}

module SportsTicketsContract
  ( TicketDatum(..)
  , TicketRedeemer(..)
  , mkTicketValidator
  , mkTicketValidatorUntyped
  , validator
  ) where

import Plutus.V2.Ledger.Api
    ( Validator
    , ScriptContext(..)
    , TxInfo(..)
    , TxOut(..)
    , TxInInfo(..)
    , TxOutRef
    , Address(..)
    , Credential(..)
    , OutputDatum(..)
    , Datum(..)
    , POSIXTime
    , POSIXTimeRange
    , PubKeyHash
    , CurrencySymbol
    , TokenName(..)
    , unTokenName
    , ValidatorHash
    , BuiltinData
    , mkValidatorScript
    )
import Plutus.V2.Ledger.Contexts
    ( txSignedBy
    , scriptContextTxInfo
    , valuePaidTo
    , findOwnInput
    , ownHash
    , txInInfoResolved
    )
import Plutus.V1.Ledger.Interval as Interval
    ( contains
    , to
    )
import Plutus.V1.Ledger.Value
    ( Value
    , valueOf
    , adaSymbol
    , adaToken
    , flattenValue
    )
import PlutusTx
import PlutusTx.Prelude
    hiding (Semigroup(..), unless)

import qualified PlutusTx.Builtins as Builtins

----------------------------------------------------------------------
-- Datum & Redeemer
----------------------------------------------------------------------

-- | On-chain state of a single ticket.
--
-- This captures:
--  * which event (`tdEventId`)
--  * which seat  (`tdSeat`)
--  * current owner
--  * whether it has already been used (`tdUsed`)
--  * primary price + max allowed resale price
--  * event time (for gate checks)
--  * optional KYC authority that must co-sign any transfer
--  * the exact NFT (policy + token name) that represents this ticket
data TicketDatum = TicketDatum
    { tdEventId      :: BuiltinByteString  -- ^ Event identifier
    , tdSeat         :: BuiltinByteString  -- ^ Seat / section description
    , tdOwner        :: PubKeyHash         -- ^ Current owner of the ticket
    , tdUsed         :: Bool               -- ^ Has this ticket been used at the gate?
    , tdFaceValue    :: Integer            -- ^ Primary sale price (in lovelace)
    , tdMaxPrice     :: Integer            -- ^ Max allowed resale price (in lovelace)
    , tdEventTime    :: POSIXTime          -- ^ Event time (for gate checks)
    , tdKycAuthority :: Maybe PubKeyHash   -- ^ If Just pk, transfers require pk's signature
    , tdPolicyId     :: CurrencySymbol     -- ^ Policy ID of the ticket NFT
    , tdTokenName    :: TokenName          -- ^ Token name of the ticket NFT
    , tdUsedPolicyId :: CurrencySymbol  -- ^ Policy for USED souvenir tokens
    }
PlutusTx.unstableMakeIsData ''TicketDatum

-- | Actions that can be performed on a ticket UTxO.
--
-- * Transfer newOwner price:
--     resale / transfer to `newOwner`, expected ADA price in lovelace.
-- * UseAtGate:
--     spend the ticket at the event gate (entry scan).
data TicketRedeemer
    = Transfer PubKeyHash Integer  -- ^ new owner, resale price
    | UseAtGate
PlutusTx.unstableMakeIsData ''TicketRedeemer

----------------------------------------------------------------------
-- Helper accessors
----------------------------------------------------------------------

{-# INLINABLE info #-}
info :: ScriptContext -> TxInfo
info = scriptContextTxInfo

{-# INLINABLE txRange #-}
txRange :: ScriptContext -> POSIXTimeRange
txRange = txInfoValidRange . info

{-# INLINABLE usedTokenName #-}
usedTokenName :: TokenName -> TokenName
usedTokenName tn = 
  TokenName (Builtins.appendByteString "USED-" (unTokenName tn))

{-# INLINABLE mintedAmountOf #-}
mintedAmountOf :: CurrencySymbol -> TokenName -> ScriptContext -> Integer
mintedAmountOf cs tn ctx =
  let mintedTriples = flattenValue (txInfoMint (info ctx))
  in sum [ amt | (cs', tn', amt) <- mintedTriples, cs' == cs, tn' == tn ]

{-# INLINABLE valuePaidOf #-}
valuePaidOf :: PubKeyHash -> CurrencySymbol -> TokenName -> ScriptContext -> Integer
valuePaidOf pkh cs tn ctx =
  let v = valuePaidTo (info ctx) pkh
  in valueOf v cs tn

{-# INLINABLE getContinuingOutput #-}
getContinuingOutput :: ScriptContext -> TxOut
getContinuingOutput ctx =
  let ti   = info ctx
      vh   = ownHash ctx
      outs = txInfoOutputs ti
      isOwn o = case txOutAddress o of
                  Address (ScriptCredential vh') _ -> vh' == vh
                  _                                -> False
      ownOuts = filter isOwn outs
  in case ownOuts of
       [o] -> o
       _   -> traceError "expected exactly one continuing ticket output"

{-# INLINABLE datumFromOutput #-}
datumFromOutput :: TxOut -> TicketDatum
datumFromOutput o =
  case txOutDatum o of
    OutputDatum (Datum d) -> unsafeFromBuiltinData d
    _                     -> traceError "expected inline datum on continuing output"

{-# INLINABLE ticketStaticFieldsEqual #-}
ticketStaticFieldsEqual :: TicketDatum -> TicketDatum -> Bool
ticketStaticFieldsEqual old new =
       tdEventId old      == tdEventId new
    && tdSeat old         == tdSeat new
    && tdFaceValue old    == tdFaceValue new
    && tdMaxPrice old     == tdMaxPrice new
    && tdEventTime old    == tdEventTime new
    && tdKycAuthority old == tdKycAuthority new
    && tdPolicyId old     == tdPolicyId new
    && tdTokenName old    == tdTokenName new

{-# INLINABLE noContinuingOutput #-}
noContinuingOutput :: ScriptContext -> Bool
noContinuingOutput ctx =
  let vh   = ownHash ctx
      outs = txInfoOutputs (scriptContextTxInfo ctx)
      isOwn o = case txOutAddress o of
                  Address (ScriptCredential vh') _ -> vh' == vh
                  _                                -> False
  in all (not . isOwn) outs

----------------------------------------------------------------------
-- NFT helpers
----------------------------------------------------------------------

-- | Check that the script input UTxO contains exactly 1 of the ticket NFT
--   identified by (tdPolicyId, tdTokenName).
{-# INLINABLE ticketNftBound #-}
ticketNftBound :: TicketDatum -> ScriptContext -> Bool
ticketNftBound dat ctx =
  case findOwnInput ctx of
    Nothing  -> traceIfFalse "ticket input missing" False
    Just inp ->
      let v       = txOutValue (txInInfoResolved inp)
          triples = flattenValue v
          ours    =
            [ amt
            | (cs, tn, amt) <- triples
            , cs == tdPolicyId dat
            , tn == tdTokenName dat
            ]
      in case ours of
           [1] -> True
           _   -> traceIfFalse "expected exactly one matching ticket NFT in input" False

-- | Enforce a proper state transition for Transfer:
--   * exactly one continuing output at this script
--   * that output contains exactly 1 ticket NFT
--   * owner updated to newOwner
--   * static fields unchanged
--   * tdUsed unchanged (still False) on Transfer
{-# INLINABLE ticketStateTransitionOk #-}
ticketStateTransitionOk :: TicketDatum -> PubKeyHash -> ScriptContext -> Bool
ticketStateTransitionOk dat newOwner ctx =
  let out    = getContinuingOutput ctx
      outDat = datumFromOutput out

      -- must still hold exactly 1 of *this* ticket NFT
      nftOk  = valueOf (txOutValue out) (tdPolicyId dat) (tdTokenName dat) == 1

      -- forbid any other non-ADA assets in the continuing output
      nonAdaTriples =
        [ (cs, tn, amt)
        | (cs, tn, amt) <- flattenValue (txOutValue out)
        , not (cs == adaSymbol && tn == adaToken)
        ]

      onlyThisNft :: Bool
      onlyThisNft =
        case nonAdaTriples of
          [(cs, tn, amt)] -> cs == tdPolicyId dat && tn == tdTokenName dat && amt == 1
          _               -> False

  in     traceIfFalse "ticket NFT not preserved in output" nftOk
     &&  traceIfFalse "continuing output contains extra non-ADA tokens" onlyThisNft
     &&  traceIfFalse "owner not updated to new owner"     (tdOwner outDat == newOwner)
     &&  traceIfFalse "static ticket fields changed"       (ticketStaticFieldsEqual dat outDat)
     &&  traceIfFalse "used flag changed on transfer"      (tdUsed outDat == tdUsed dat)


----------------------------------------------------------------------
-- Validation branches
----------------------------------------------------------------------

-- | Validate a ticket transfer / resale.
--
-- Enforces:
--   * script input has exactly one matching NFT (ticketNftBound)
--   * ticket unused
--   * current owner signed
--   * if tdKycAuthority = Just pk, pk must also sign
--   * actual ADA paid to owner == 'price'
--   * price <= tdMaxPrice
--   * newOwner /= old owner
--   * continuing output has correct datum + NFT (ticketStateTransitionOk)
{-# INLINABLE validateTransfer #-}
validateTransfer :: TicketDatum -> PubKeyHash -> Integer -> ScriptContext -> Bool
validateTransfer dat newOwner price ctx =
       traceIfFalse "ticket NFT missing / invalid" ticketHasNft
    && traceIfFalse "ticket already used"          ticketNotUsed
    && traceIfFalse "owner signature missing"      ownerSigned
    && traceIfFalse "kyc signature missing"        kycOk
    && traceIfFalse "resale price too high"        withinCap
    && traceIfFalse "owner unchanged"              ownerChanges
    && traceIfFalse "owner not paid correctly"     ownerPaidCorrectly
    && traceIfFalse "ticket state invalid"         stateOk
    && traceIfFalse "ticket state invalid"         (ticketStateTransitionOk dat newOwner ctx)
  where
    ti :: TxInfo
    ti = info ctx

    ticketHasNft :: Bool
    ticketHasNft = ticketNftBound dat ctx

    ticketNotUsed :: Bool
    ticketNotUsed = not (tdUsed dat)

    ownerSigned :: Bool
    ownerSigned = txSignedBy ti (tdOwner dat)

    -- If a KYC authority is configured, it must co-sign transfers.
    kycOk :: Bool
    kycOk =
      case tdKycAuthority dat of
        Nothing      -> True
        Just authPkh -> txSignedBy ti authPkh

    -- Actual ADA paid to the current owner in this transaction
    actualPaidAda :: Integer
    actualPaidAda =
      let v = valuePaidTo ti (tdOwner dat)
      in valueOf v adaSymbol adaToken

    -- The actual money flow must match the declared price,
    -- and that price must be <= the configured cap.
    ownerPaidCorrectly :: Bool
    ownerPaidCorrectly = actualPaidAda == price

    withinCap :: Bool
    withinCap = price <= tdMaxPrice dat

    ownerChanges :: Bool
    ownerChanges = newOwner /= tdOwner dat

    stateOk :: Bool
    stateOk = ticketStateTransitionOk dat newOwner ctx

{-# INLINABLE validateUseAtGate #-}
validateUseAtGate :: TicketDatum -> ScriptContext -> Bool
validateUseAtGate dat ctx =
       traceIfFalse "ticket NFT missing / invalid"        ticketHasNft
    && traceIfFalse "ticket already used"                 ticketNotUsed
    && traceIfFalse "too late for entry"                  beforeOrAtEventTime
    && traceIfFalse "must burn 1 ticket NFT"              burnedExactlyOne
    && traceIfFalse "must mint 1 USED souvenir"           mintedExactlyOne
    && traceIfFalse "unexpected extra minting"            noExtraMinting
    && traceIfFalse "USED souvenir not paid to owner"     souvenirPaidToOwner
    && traceIfFalse "no continuing output expected"       noContinuingOutput ctx
  where
    ti :: TxInfo
    ti = info ctx

    ticketHasNft :: Bool
    ticketHasNft = ticketNftBound dat ctx

    ticketNotUsed :: Bool
    ticketNotUsed = not (tdUsed dat)

    beforeOrAtEventTime :: Bool
    beforeOrAtEventTime =
      Interval.contains (Interval.to (tdEventTime dat)) (txRange ctx)

    -- The ticket (to burn) and the souvenir (to mint)
    csTicket = tdPolicyId     dat
    tn       = tdTokenName    dat
    csUsed   = tdUsedPolicyId dat
    utn      = usedTokenName  tn

    -- Exactly: burn 1 ticket, mint 1 USED
    burnedExactlyOne :: Bool
    burnedExactlyOne = mintedAmountOf csTicket tn  ctx == (-1)

    mintedExactlyOne :: Bool
    mintedExactlyOne = mintedAmountOf csUsed   utn ctx == 1

    -- Forbid *any* other mint/burn besides the two above
    noExtraMinting :: Bool
    noExtraMinting =
      let mintedTriples = flattenValue (txInfoMint ti)
          allowed (cs, tnm, amt) =
               (cs == csTicket && tnm == tn  && amt == (-1))
            || (cs == csUsed   && tnm == utn && amt == 1)
      in  all allowed mintedTriples && length mintedTriples == 2

    -- Ensure the newly minted USED souvenir goes to the current owner
    souvenirPaidToOwner :: Bool
    souvenirPaidToOwner = valuePaidOf (tdOwner dat) csUsed utn ctx == 1



----------------------------------------------------------------------
-- Main validator
----------------------------------------------------------------------

{-# INLINABLE mkTicketValidator #-}
mkTicketValidator :: TicketDatum -> TicketRedeemer -> ScriptContext -> Bool
mkTicketValidator dat red ctx =
  case red of
    Transfer newOwner price ->
        validateTransfer dat newOwner price ctx

    UseAtGate ->
        validateUseAtGate dat ctx

----------------------------------------------------------------------
-- Untyped wrapper & compiled validator
----------------------------------------------------------------------

{-# INLINABLE mkTicketValidatorUntyped #-}
mkTicketValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkTicketValidatorUntyped d r c =
    let dat = unsafeFromBuiltinData @TicketDatum    d
        red = unsafeFromBuiltinData @TicketRedeemer r
        ctx = unsafeFromBuiltinData @ScriptContext  c
    in if mkTicketValidator dat red ctx
          then ()
          else error ()

-- | Plutus V2 validator script.
validator :: Validator
validator = mkValidatorScript $$(PlutusTx.compile [|| mkTicketValidatorUntyped ||])
