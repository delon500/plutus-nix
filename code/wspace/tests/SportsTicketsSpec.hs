{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NumericUnderscores  #-}

module SportsTicketsSpec
  ( sportsTicketsTests
  , tests
  ) where

import Prelude (Show(..), Eq(..), ($), (.), (++), (<>))
import qualified Prelude               as P

import Test.Tasty
import Test.Tasty.HUnit

import PlutusTx                      (toBuiltinData)
import PlutusTx.Prelude              hiding (Semigroup(..), unless, ($))
import qualified PlutusTx.Builtins   as Builtins

import Plutus.V2.Ledger.Api
import qualified Plutus.V1.Ledger.Interval as I
import Plutus.V1.Ledger.Value        (adaSymbol, adaToken)
import qualified Plutus.V1.Ledger.Value as Value

import qualified Data.ByteString.Char8 as BSC
import qualified PlutusTx.AssocMap     as AMap

import SportsTicketsContract
  ( TicketDatum(..)
  , TicketRedeemer(..)
  , mkTicketValidator
  )

--------------------------------------------------------------------------------
-- Helpers / constants
--------------------------------------------------------------------------------

dummyTxId :: TxId
dummyTxId =
  TxId (Builtins.toBuiltin (BSC.pack "dummy-tx-id"))

dummyValidatorHash :: ValidatorHash
dummyValidatorHash =
  ValidatorHash (Builtins.toBuiltin (BSC.pack "sports-tickets"))

pkhOwner, pkhBuyer :: PubKeyHash
pkhOwner = PubKeyHash (Builtins.toBuiltin (BSC.pack "owner-wallet"))
pkhBuyer = PubKeyHash (Builtins.toBuiltin (BSC.pack "buyer-wallet"))

-- Event time we use across tests
eventTime :: POSIXTime
eventTime = POSIXTime 1_700_000_000

-- Dummy NFT that represents this specific ticket (must match TicketDatum)
ticketPolicyId :: CurrencySymbol
ticketPolicyId =
  CurrencySymbol (Builtins.toBuiltin (BSC.pack "sports-ticket-policy"))

usedTokenName :: TokenName
usedTokenName = TokenName ("USED-" <> unTokenName ticketTokenName)

usedSouvenirVal :: Value.Value
usedSouvenirVal = Value.singleton ticketPolicyId usedTokenName 1

ticketTokenName :: TokenName
ticketTokenName =
  TokenName (Builtins.toBuiltin (BSC.pack "TICKET-001"))

pkAddress :: PubKeyHash -> Address
pkAddress pkh = Address (PubKeyCredential pkh) Nothing

scriptAddress :: Address
scriptAddress = Address (ScriptCredential dummyValidatorHash) Nothing

-- Script input UTxO holding the ticket NFT and some ADA (priceAda)
-- (We don't model full value conservation in these unit tests.)
scriptInputOut :: Integer -> TxOut
scriptInputOut priceAda =
  let adaVal = Value.singleton adaSymbol adaToken priceAda
      nftVal = Value.singleton ticketPolicyId ticketTokenName 1
      theVal = Value.unionWith (+) adaVal nftVal
  in TxOut
       { txOutAddress         = scriptAddress
       , txOutValue           = theVal
       , txOutDatum           = NoOutputDatum
       , txOutReferenceScript = Nothing
       }

-- Continuing script output with the ticket NFT and an inline TicketDatum
scriptContinuingOut :: TicketDatum -> TxOut
scriptContinuingOut dat =
  let nftVal = Value.singleton (tdPolicyId dat) (tdTokenName dat) 1
  in TxOut
       { txOutAddress         = scriptAddress
       , txOutValue           = nftVal
       , txOutDatum           = OutputDatum (Datum (toBuiltinData dat))
       , txOutReferenceScript = Nothing
       }

-- Continuing output with NO ticket NFT (forces nftOk = False without exceptions)
scriptContinuingOutNoNft :: TicketDatum -> TxOut
scriptContinuingOutNoNft dat =
  TxOut
    { txOutAddress         = scriptAddress
    , txOutValue           = mempty            -- 👈 no NFT here
    , txOutDatum           = OutputDatum (Datum (toBuiltinData dat))
    , txOutReferenceScript = Nothing
    }


-- Simple ADA output to a PKH (used to pay the current owner)
adaOut :: PubKeyHash -> Integer -> TxOut
adaOut pkh amt =
  TxOut
    { txOutAddress         = pkAddress pkh
    , txOutValue           = Value.singleton adaSymbol adaToken amt
    , txOutDatum           = NoOutputDatum
    , txOutReferenceScript = Nothing
    }

-- Base TicketDatum used in tests, with KYC disabled (Nothing)
-- and bound to our dummy NFT (ticketPolicyId, ticketTokenName).
baseTicketDatum :: PubKeyHash -> TicketDatum
baseTicketDatum owner =
  TicketDatum
    { tdEventId      = "EVENT-001"
    , tdSeat         = "BLOCK-A-ROW-1-SEAT-10"
    , tdOwner        = owner
    , tdUsed         = False
    , tdFaceValue    = 1_000_000
    , tdMaxPrice     = 1_500_000
    , tdEventTime    = eventTime
    , tdKycAuthority = Nothing
    , tdPolicyId     = ticketPolicyId
    , tdTokenName    = ticketTokenName
    , tdUsedPolicyId = ticketPolicyId 
    }

-- Build a TxInfo for a transfer scenario where:
--  * There is one script input with the ticket NFT.
--  * There is exactly one continuing script output with updated datum.
--  * The current owner receives 'price' ADA in a separate output.
mkTransferInfo
  :: TicketDatum      -- ^ old datum (with old owner)
  -> PubKeyHash       -- ^ new owner
  -> Integer          -- ^ price (ADA)
  -> [PubKeyHash]     -- ^ signatories
  -> TxInfo
mkTransferInfo oldDat newOwner price signers =
  let inputOut =
        scriptInputOut price

      inputInfo =
        TxInInfo
          { txInInfoOutRef   = TxOutRef dummyTxId 0
          , txInInfoResolved = inputOut
          }

      newDat :: TicketDatum
      newDat = oldDat { tdOwner = newOwner }

      scriptOut :: TxOut
      scriptOut = scriptContinuingOut newDat

      sellerOut :: TxOut
      sellerOut = adaOut (tdOwner oldDat) price

  in TxInfo
       { txInfoInputs          = [inputInfo]
       , txInfoReferenceInputs = []
       , txInfoOutputs         = [scriptOut, sellerOut]
       , txInfoFee             = mempty
       , txInfoMint            = mempty
       , txInfoDCert           = []
       , txInfoWdrl            = AMap.empty
       , txInfoValidRange      = I.always
       , txInfoSignatories     = signers
       , txInfoRedeemers       = AMap.empty
       , txInfoData            = AMap.empty
       , txInfoId              = dummyTxId
       }

-- Gate scenario: we only need a script input with the NFT and a valid range.
mkGateInfo :: POSIXTimeRange -> Value.Value -> [TxOut] -> TxInfo
mkGateInfo range minted outs =
  let inputOut = scriptInputOut 0
      inputInfo =
        TxInInfo
          { txInInfoOutRef   = TxOutRef dummyTxId 0
          , txInInfoResolved = inputOut
          }
  in TxInfo
       { txInfoInputs          = [inputInfo]
       , txInfoReferenceInputs = []
       , txInfoOutputs         = outs
       , txInfoFee             = mempty
       , txInfoMint            = minted
       , txInfoDCert           = []
       , txInfoWdrl            = AMap.empty
       , txInfoValidRange      = range
       , txInfoSignatories     = []
       , txInfoRedeemers       = AMap.empty
       , txInfoData            = AMap.empty
       , txInfoId              = dummyTxId
       }

mkCtx :: TxInfo -> ScriptPurpose -> ScriptContext
mkCtx info purpose = ScriptContext info purpose

souvenirTo :: PubKeyHash -> TxOut
souvenirTo pkh =
  TxOut
    { txOutAddress         = pkAddress pkh
    , txOutValue           = usedSouvenirVal
    , txOutDatum           = NoOutputDatum
    , txOutReferenceScript = Nothing
    }

--------------------------------------------------------------------------------
-- Test tree
--------------------------------------------------------------------------------

sportsTicketsTests :: TestTree
sportsTicketsTests =
  testGroup "SportsTickets (on-chain v1)"
    [ transferTests
    , gateTests
    ]

-- alias used in Spec.hs
tests :: TestTree
tests = sportsTicketsTests

--------------------------------------------------------------------------------
-- Transfer tests
--------------------------------------------------------------------------------

transferTests :: TestTree
transferTests =
  testGroup "Transfer"
    [ testCase "valid transfer passes (owner signed, price <= cap)" $
        assertBool "expected valid transfer" validTransfer

    , testCase "transfer fails when owner not signed" $
        assertBool "expected validator to fail" (P.not ownerNotSigned)

    , testCase "transfer fails when price is above cap" $
        assertBool "expected validator to fail" (P.not priceAboveCap)

    , testCase "transfer fails if static fields change" $
        assertBool "expected validator to fail" (P.not transferStaticFieldTamper)
        
    , testCase "transfer fails if continuing output lacks the ticket NFT" $
        assertBool "expected validator to fail" (P.not transferMissingNft)
    ]
  where
    -- Happy path: owner signs, buyer pays 1.2M (<= 1.5M cap)
    validTransfer :: P.Bool
    validTransfer =
      let price   = 1_200_000
          dat     = baseTicketDatum pkhOwner
          info    = mkTransferInfo dat pkhBuyer price [pkhOwner]
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
          red     = Transfer pkhBuyer price
      in mkTicketValidator dat red ctx

    -- Owner not in signatories ⇒ should fail
    ownerNotSigned :: P.Bool
    ownerNotSigned =
      let price   = 1_200_000
          dat     = baseTicketDatum pkhOwner
          info    = mkTransferInfo dat pkhBuyer price []  -- no owner in signers
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
          red     = Transfer pkhBuyer price
      in mkTicketValidator dat red ctx

    -- Price above cap ⇒ should fail
    priceAboveCap :: P.Bool
    priceAboveCap =
      let price   = 2_000_000  -- > tdMaxPrice 1.5M
          dat     = baseTicketDatum pkhOwner
          info    = mkTransferInfo dat pkhBuyer price [pkhOwner]
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
          red     = Transfer pkhBuyer price
      in mkTicketValidator dat red ctx

    -- NEW HELPER: tamper continuing datum’s static fields
    transferStaticFieldTamper :: P.Bool
    transferStaticFieldTamper =
      let price    = 1_200_000
          oldDat   = baseTicketDatum pkhOwner
          -- Build a normal transfer tx:
          info0    = mkTransferInfo oldDat pkhBuyer price [pkhOwner]
          -- Replace the continuing output with one that changes a static field:
          badNew   = oldDat { tdOwner = pkhBuyer
                            , tdSeat  = "BLOCK-Z-ROW-99-SEAT-99" -- tamper
                            }
          badOut   = scriptContinuingOut badNew
          seller   = adaOut (tdOwner oldDat) price
          info     = info0 { txInfoOutputs = [badOut, seller] }
          ctx      = mkCtx info (Spending (TxOutRef dummyTxId 0))
          red      = Transfer pkhBuyer price
      in mkTicketValidator oldDat red ctx

    transferMissingNft :: P.Bool
    transferMissingNft =
      let price    = 1_200_000
          oldDat   = baseTicketDatum pkhOwner
          newDat   = oldDat { tdOwner = pkhBuyer }      -- owner updated as normal
          badOut   = scriptContinuingOutNoNft newDat    -- 👈 no NFT in output
          seller   = adaOut (tdOwner oldDat) price
          inputOut = scriptInputOut price
          inputInfo =
            TxInInfo { txInInfoOutRef = TxOutRef dummyTxId 0
                    , txInInfoResolved = inputOut
                    }
          info = TxInfo
            { txInfoInputs          = [inputInfo]
            , txInfoReferenceInputs = []
            , txInfoOutputs         = [badOut, seller]  -- exactly one continuing out
            , txInfoFee             = mempty
            , txInfoMint            = mempty
            , txInfoDCert           = []
            , txInfoWdrl            = AMap.empty
            , txInfoValidRange      = I.always
            , txInfoSignatories     = [pkhOwner]
            , txInfoRedeemers       = AMap.empty
            , txInfoData            = AMap.empty
            , txInfoId              = dummyTxId
            }
          ctx = mkCtx info (Spending (TxOutRef dummyTxId 0))
          red = Transfer pkhBuyer price
      in mkTicketValidator oldDat red ctx


--------------------------------------------------------------------------------
-- UseAtGate tests
--------------------------------------------------------------------------------
gateTests :: TestTree
gateTests =
  testGroup "UseAtGate"
    [ testCase "unused ticket before event (burn + mint USED to owner) passes" $
        assertBool "expected gate use to pass" gateValid

    , testCase "already-used ticket fails at gate" $
        assertBool "expected gate use to fail" (P.not gateAlreadyUsed)

    , testCase "ticket after event time fails" $
        assertBool "expected gate use to fail" (P.not gateAfterEvent)

    , testCase "missing burn of original ticket fails" $
        assertBool "expected validator to fail" (P.not gateMissingBurn)

    , testCase "missing mint of USED souvenir fails" $
        assertBool "expected validator to fail" (P.not gateMissingMint)

    , testCase "USED souvenir not sent to owner fails" $
        assertBool "expected validator to fail" (P.not gateSouvenirWrongRecipient)

    , testCase "USED souvenir under wrong policy fails" $
        assertBool "expected validator to fail" (P.not gateSouvenirWrongPolicy)

    , testCase "USED souvenir minted but not paid to owner fails" $
        assertBool "expected validator to fail" (P.not gateSouvenirPaidToScript)
    ]
  where
    burnMint :: Value.Value
    burnMint =
         Value.singleton ticketPolicyId ticketTokenName (-1)
      <> Value.singleton ticketPolicyId usedTokenName      1

    gateValid :: P.Bool
    gateValid =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = False
                                               , tdPolicyId  = ticketPolicyId
                                               , tdTokenName = ticketTokenName
                                               }
          range   = I.to eventTime
          outs    = [souvenirTo pkhOwner]
          info    = mkGateInfo range burnMint outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    gateAlreadyUsed :: P.Bool
    gateAlreadyUsed =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = True
                                               , tdPolicyId  = ticketPolicyId
                                               , tdTokenName = ticketTokenName
                                               }
          range   = I.to eventTime
          outs    = [souvenirTo pkhOwner]
          info    = mkGateInfo range burnMint outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    gateAfterEvent :: P.Bool
    gateAfterEvent =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = False
                                               , tdPolicyId  = ticketPolicyId
                                               , tdTokenName = ticketTokenName
                                               }
          range   = I.from (eventTime + 1)
          outs    = [souvenirTo pkhOwner]
          info    = mkGateInfo range burnMint outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    gateMissingBurn :: P.Bool
    gateMissingBurn =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = False
                                               , tdPolicyId  = ticketPolicyId
                                               , tdTokenName = ticketTokenName
                                               }
          range   = I.to eventTime
          outs    = [souvenirTo pkhOwner]
          -- Only mint the USED token, don't burn original
          minted  = Value.singleton ticketPolicyId usedTokenName 1
          info    = mkGateInfo range minted outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    gateMissingMint :: P.Bool
    gateMissingMint =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = False
                                               , tdPolicyId  = ticketPolicyId
                                               , tdTokenName = ticketTokenName
                                               }
          range   = I.to eventTime
          outs    = []  -- no souvenir output
          -- Only burn the original, don't mint souvenir
          minted  = Value.singleton ticketPolicyId ticketTokenName (-1)
          info    = mkGateInfo range minted outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    gateSouvenirWrongPolicy :: P.Bool
    gateSouvenirWrongPolicy =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = False}
          range   = I.to eventTime
          -- Souvenir under wrong policy
          wrongCs = CurrencySymbol (Builtins.toBuiltin (BSC.pack "wrong-policy"))
          minted  =    Value.singleton ticketPolicyId ticketTokenName (-1)
                    <> Value.singleton wrongCs       usedTokenName     1
          outs    = [souvenirTo pkhOwner]  -- still pays owner, but wrong policy
          info    = mkGateInfo range minted outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    gateSouvenirWrongRecipient :: P.Bool
    gateSouvenirWrongRecipient =
      let dat     = (baseTicketDatum pkhOwner) { tdUsed = False
                                               , tdPolicyId  = ticketPolicyId
                                               , tdTokenName = ticketTokenName
                                               }
          range   = I.to eventTime
          -- Souvenir sent to the buyer instead of owner
          outs    = [souvenirTo pkhBuyer]
          info    = mkGateInfo range burnMint outs
          ctx     = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx

    souvenirToScript :: TxOut
    souvenirToScript =
      TxOut
        { txOutAddress         = scriptAddress
        , txOutValue           = usedSouvenirVal
        , txOutDatum           = NoOutputDatum
        , txOutReferenceScript = Nothing
        }

    gateSouvenirPaidToScript :: P.Bool
    gateSouvenirPaidToScript =
      let dat    = (baseTicketDatum pkhOwner) { tdUsed = False }
          range  = I.to eventTime
          minted =    Value.singleton ticketPolicyId ticketTokenName (-1)
                   <> Value.singleton ticketPolicyId usedTokenName     1
          outs   = [souvenirToScript]  -- wrong recipient (script, not owner)
          info   = mkGateInfo range minted outs
          ctx    = mkCtx info (Spending (TxOutRef dummyTxId 0))
      in mkTicketValidator dat UseAtGate ctx
