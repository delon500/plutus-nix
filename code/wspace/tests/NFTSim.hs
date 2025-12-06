{-# LANGUAGE OverloadedStrings #-}

module Main where

import           NFT
import           Plutus.V2.Ledger.Api       (TxId (..), TxOutRef (..), TokenName, CurrencySymbol)
import           PlutusTx.Builtins.Internal (BuiltinByteString (..))
import qualified Data.ByteString.Char8      as BS8
import qualified Data.ByteString.Base16     as B16
import           Data.Either                (fromRight)
import           Prelude                    (IO, putStrLn, String, (<>), show, error)


-- Console-only "simulation" of creating an NFT called Moran
-- using the provided minting policy and a *real* TxId.
main :: IO ()
main = do
    let tn :: TokenName
        tn = "Moran"  -- the NFT name

        -- Your real tx hash (hex)
        txHashHex :: BS8.ByteString
        txHashHex = "295d218cc9b2b0e692fb443bdbf1d490c8060c803d25aaa53367719dcb6ceaaf"

        -- Decode hex -> raw bytes (crash with a clear error if somehow invalid)
        txHashBytes =
          fromRight (error "Invalid hex tx hash for Moran NFT") (B16.decode txHashHex)

        -- Build TxId from raw bytes
        realTxId :: TxId
        realTxId = TxId (BuiltinByteString txHashBytes)

        -- IMPORTANT: adjust the index if the UTxO is at #1, #2, etc.
        oref :: TxOutRef
        oref = TxOutRef realTxId 0

        -- Use your given minting policy to derive the CurrencySymbol
        cs :: CurrencySymbol
        cs = nftCurrencySymbol oref tn

    putStrLn "=== NFT Moran – Local Console Simulation==="
    putStrLn ("TxOutRef (used by policy): " <> show oref)
    putStrLn ("Token name               : Moran")
    putStrLn ("Currency symbol (policy) : " <> show cs)
    --putStrLn "This corresponds to minting exactly 1 NFT called 'Moran' under this real TxId-based policy."
