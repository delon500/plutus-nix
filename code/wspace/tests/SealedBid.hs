{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}

module Main where

import Prelude (IO, String, FilePath, putStrLn, (<>))
import qualified Prelude as P
import qualified Data.Text as T

-- Plutus core
import Plutus.V2.Ledger.Api
import Plutus.V2.Ledger.Contexts
import qualified Plutus.V2.Ledger.Api as PlutusV2
import Plutus.V1.Ledger.Interval as Interval
import Plutus.V1.Ledger.Value (valueOf, adaSymbol, adaToken)
import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins

-- Serialization
import qualified Codec.Serialise as Serialise
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS

-- Cardano API (for Bech32 address & text envelope)
import qualified Cardano.Api as C
import qualified Cardano.Api.Shelley as CS

------------------------------------------------------------------------
-- Datum and Redeemer
------------------------------------------------------------------------

-- | Datum for a single committed bid in the sealed-bid auction.
--   Includes seller and the auctioned NFT (currency + token name).
data CommitDatum = CommitDatum
    { cdBidder         :: PubKeyHash          -- ^ bidder who owns this commitment
    , cdSeller         :: PubKeyHash          -- ^ seller who will receive the ADA
    , cdCommitHash     :: BuiltinByteString   -- ^ hash of (amount, salt)
    , cdDeadlineReveal :: POSIXTime           -- ^ reveal deadline
    , cdCurrency       :: CurrencySymbol      -- ^ NFT currency symbol
    , cdToken          :: TokenName           -- ^ NFT token name
    }
PlutusTx.unstableMakeIsData ''CommitDatum

-- | Redeemer:
--   * Reveal amount salt  – prove your committed bid before deadline.
--   * Refund              – get your funds back after deadline.
data AuctionRedeemer
    = Reveal Integer BuiltinByteString
    | Refund
PlutusTx.unstableMakeIsData ''AuctionRedeemer

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

{-# INLINABLE bidHash #-}
bidHash :: Integer -> BuiltinByteString -> BuiltinByteString
bidHash amount salt =
    -- Hash the Plutus Data encoding of (amount, salt)
    Builtins.sha2_256 $
      Builtins.serialiseData (PlutusTx.toBuiltinData (amount, salt))

{-# INLINABLE ownInput #-}
ownInput :: ScriptContext -> TxOut
ownInput ctx =
    case findOwnInput ctx of
        Nothing -> traceError "own input missing"
        Just i  -> txInInfoResolved i

{-# INLINABLE inputAda #-}
inputAda :: ScriptContext -> Integer
inputAda ctx =
    let v = txOutValue (ownInput ctx)
    in valueOf v adaSymbol adaToken

------------------------------------------------------------------------
-- Validator Logic
------------------------------------------------------------------------

{-# INLINABLE mkValidator #-}
mkValidator :: CommitDatum -> AuctionRedeemer -> ScriptContext -> Bool

-- Reveal branch:
--   Bidder reveals (amount, salt) before deadline, proves it matches the commit hash,
--   pays ADA to the seller, and receives the NFT.
mkValidator dat (Reveal amount salt) ctx =
       traceIfFalse "bidder signature missing"   bidderSigned
    && traceIfFalse "reveal too late"           beforeDeadline
    && traceIfFalse "commitment mismatch"       commitMatches
    && traceIfFalse "seller not paid"           sellerPaid
    && traceIfFalse "bidder not receive NFT"    bidderGetsNFT
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    txRange :: POSIXTimeRange
    txRange = txInfoValidRange info

    bidder :: PubKeyHash
    bidder = cdBidder dat

    seller :: PubKeyHash
    seller = cdSeller dat

    bidderSigned :: Bool
    bidderSigned = txSignedBy info bidder

    -- Reveal must happen at or before the deadline
    beforeDeadline :: Bool
    beforeDeadline =
      Interval.contains (Interval.to (cdDeadlineReveal dat)) txRange

    -- Check that the revealed (amount, salt) matches the committed hash
    commitMatches :: Bool
    commitMatches =
      cdCommitHash dat == bidHash amount salt

    -- Seller must be paid at least the revealed bid amount in ADA
    sellerPaid :: Bool
    sellerPaid =
      let v = valuePaidTo info seller
      in valueOf v adaSymbol adaToken >= amount

    -- Bidder must receive the auctioned NFT
    bidderGetsNFT :: Bool
    bidderGetsNFT =
      let v = valuePaidTo info bidder
      in valueOf v (cdCurrency dat) (cdToken dat) >= 1


-- Refund branch:
--   After the reveal deadline, bidder can reclaim their committed ADA.
mkValidator dat Refund ctx =
       traceIfFalse "bidder signature missing"   bidderSigned
    && traceIfFalse "too early for refund"       afterDeadline
    && traceIfFalse "refund not paid to bidder"  refundPaid
  where
    info :: TxInfo
    info = scriptContextTxInfo ctx

    txRange :: POSIXTimeRange
    txRange = txInfoValidRange info

    bidder :: PubKeyHash
    bidder = cdBidder dat

    bidderSigned :: Bool
    bidderSigned = txSignedBy info bidder

    -- Refund only allowed strictly after the deadline
    afterDeadline :: Bool
    afterDeadline =
      Interval.contains (Interval.from (cdDeadlineReveal dat + 1)) txRange

    -- Ensure the bidder gets back at least what was in the committed UTxO
    refundPaid :: Bool
    refundPaid =
      let paidToBidder = valuePaidTo info bidder
      in valueOf paidToBidder adaSymbol adaToken
           >= inputAda ctx

------------------------------------------------------------------------
-- Boilerplate
------------------------------------------------------------------------

{-# INLINABLE mkValidatorUntyped #-}
mkValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkValidatorUntyped d r c =
    let dat = unsafeFromBuiltinData @CommitDatum     d
        red = unsafeFromBuiltinData @AuctionRedeemer r
        ctx = unsafeFromBuiltinData @ScriptContext   c
    in if mkValidator dat red ctx then () else error ()

validator :: Validator
validator = mkValidatorScript $$(PlutusTx.compile [|| mkValidatorUntyped ||])

------------------------------------------------------------------------
-- Validator Hash + Addresses
------------------------------------------------------------------------

-- On-chain (Plutus) hash and address (using plutus-ledger-api style hash)
plutusValidatorHash :: PlutusV2.Validator -> PlutusV2.ValidatorHash
plutusValidatorHash v =
    let bytes    = Serialise.serialise v
        short    = SBS.toShort (LBS.toStrict bytes)
        strictBS = SBS.fromShort short
        builtin  = Builtins.toBuiltin strictBS
    in PlutusV2.ValidatorHash builtin

plutusScriptAddress :: Address
plutusScriptAddress =
    Address (ScriptCredential (plutusValidatorHash validator)) Nothing

-- Off-chain (Cardano API) Bech32 address for CLI use
toBech32ScriptAddress :: C.NetworkId -> Validator -> String
toBech32ScriptAddress network val =
    let serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val
        plutusScript :: C.PlutusScript C.PlutusScriptV2
        plutusScript = CS.PlutusScriptSerialised serialised

        scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)

        shelleyAddr :: C.AddressInEra C.BabbageEra
        shelleyAddr =
            C.makeShelleyAddressInEra
                network
                (C.PaymentCredentialByScript scriptHash)
                C.NoStakeAddress
    in T.unpack (C.serialiseAddress shelleyAddr)

------------------------------------------------------------------------
-- File writing (Text envelope .plutus)
------------------------------------------------------------------------

-- | Writes the validator as a Cardano text-envelope Plutus script (.plutus),
-- which is the format accepted by `cardano-cli --script-file`.
writeValidator :: FilePath -> Validator -> IO ()
writeValidator path val = do
    let serialised :: SBS.ShortByteString
        serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

        plutusScript :: C.PlutusScript C.PlutusScriptV2
        plutusScript = CS.PlutusScriptSerialised serialised

    result <- C.writeFileTextEnvelope path (Just "Sealed-Bid Commit-Reveal NFT Auction Validator") plutusScript
    case result of
      Left err  -> putStrLn $ "Error writing validator: " <> C.displayError err
      Right ()  -> putStrLn $ "Validator written to: " <> path

------------------------------------------------------------------------
-- Main
------------------------------------------------------------------------

main :: IO ()
main = do
    let network = C.Testnet (C.NetworkMagic 1)

    -- This produces a text-envelope .plutus file
    writeValidator "sealed-bid-commit-reveal-nft.plutus" validator

    let vh      = plutusValidatorHash validator
        onchain = plutusScriptAddress
        bech32  = toBech32ScriptAddress network validator

    putStrLn "\n--- Sealed-Bid Commit–Reveal NFT Auction Validator Info ---"
    putStrLn $ "Validator Hash (Plutus): " <> P.show vh
    putStrLn $ "Plutus Script Address:    " <> P.show onchain
    putStrLn $ "Bech32 Script Address:    " <> bech32
    putStrLn "----------------------------------------------------------------"
    putStrLn "Sealed-bid commit–reveal NFT auction validator generated successfully."
