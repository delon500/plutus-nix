# AtomicSwapHTLC – Beginner Tutorial / Documentation 🎯

## Table of Contents 🧭

1.  [Overview 📖](#1-overview-📖)
2.  [What Problem This Contract Solves (HTLC) 💡](#2-what-problem-this-contract-solves-htlc-💡)
3.  [How It Differs From `AtomicSwap.hs` 🔀](#3-how-it-differs-from-atomicswaphs-🔀)
4.  [High-Level Flow (Redeem vs Refund) 🌊](#4-high-level-flow-redeem-vs-refund-🌊)
5.  [Language Extensions (Why they’re here) 🔧](#5-language-extensions-why-theyre-here-🔧)
    * [5.1 `DataKinds` 🧱](#51-datakinds-🧱)
    * [5.2 `TemplateHaskell` 🧪](#52-templatehaskell-🧪)
    * [5.3 `NoImplicitPrelude` 🚫📚](#53-noimplicitprelude-🚫📚)
    * [5.4 `OverloadedStrings` 🔤](#54-overloadedstrings-🔤)
    * [5.5 `NamedFieldPuns` 🧩](#55-namedfieldpuns-🧩)
    * [5.6 `MultiParamTypeClasses` 👥](#56-multiparamtypeclasses-👥)
    * [5.7 `FlexibleInstances` 🧷](#57-flexibleinstances-🧷)
    * [5.8 `ScopedTypeVariables` 🔭](#58-scopedtypevariables-🔭)
6.  [Imports (What each one is for) 📦](#6-imports-what-each-one-is-for-📦)
7.  [On-Chain Data Types 🧬](#7-on-chain-data-types-🧬)
    * [7.1 `HtlcDatum` 🧾](#71-htlcdatum-🧾)
    * [7.2 `HtlcRedeemer` 📨](#72-htlcredeemer-📨)
    * [7.3 `IsData` & Lifting Instances 🧩](#73-isdata--lifting-instances-🧩)
8.  [On-Chain Functions & Checks ⚙️](#8-on-chain-functions--checks-⚙️)
    * [8.1 Helper Predicates 🛠️](#81-helper-predicates-🛠️)
    * [8.2 Core Validator 🔎](#82-core-validator-🔎)
    * [8.3 Untyped Wrapper & Compiled Script 🧱](#83-untyped-wrapper--compiled-script-🧱)
    * [8.4 Ledger/Prelude Functions You’re Using 🧭](#84-ledgerprelude-functions-youre-using-🧭)
    * [8.5 Validation Truth Table 🧪](#85-validation-truth-table-🧪)
9.  [Validation Logic ✅](#9-validation-logic-✅)
    * [9.1 Redeem (preimage path) 🔓](#91-redeem-preimage-path-🔓)
    * [9.2 Refund (timeout path) 🕰️](#92-refund-timeout-path-🕰️)
    * [9.3 Time window semantics (important) ⏳](#93-time-window-semantics-important-⏳)
10. [Producing the `atomic-swap-htlc.plutus` file 📦](#10-producing-the-atomic-swap-htlcplutus-file-📦)
11. [Testing the Contract 🧪](#11-testing-the-contract-🧪)
    * [11.1 Test scenarios covered 🧰](#111-test-scenarios-covered-🧰)
    * [11.2 Running the tests ▶️](#112-running-the-tests-▶️)
    * [11.3 Quick property-test ideas (optional) 💭](#113-quick-property-test-ideas-optional-💭)
12. [Off-Chain Builder Checklist 🧱](#12-off-chain-builder-checklist-🧱)
13. [Worked Examples (Datums & Redeemers) 🧩](#13-worked-examples-datums--redeemers-🧩)
    * [13.1 Datum (simple ADA HTLC)](#131-datum-simple-ada-htlc)
    * [13.2 Redeemer – Redeem with correct preimage](#132-redeemer-redeem-with-correct-preimage)
    * [13.3 Redeemer – Refund](#133-redeemer-refund)
14. [Edge Cases & Pitfalls ⚠️](#14-edge-cases--pitfalls-⚠️)
15. [Glossary of Terms 📚](#15-glossary-of-terms-📚)

---

## 1) Overview 📖

`AtomicSwapHTLC.hs` implements a classic **Hash Time-Locked Contract (HTLC)** on Cardano/Plutus V2:

* 💤 **Maker** locks funds at the script.
* 🎯 **Beneficiary** can claim the funds **only if** they reveal a valid **preimage** whose SHA-256 hash equals the on-chain hash **and** the transaction occurs **before the deadline**.
* 🕰️ If time runs out, the **Maker can refund** the funds **after the deadline**.

This is the canonical primitive for *atomic swaps* (on one chain or mirrored across chains) where revealing the preimage on one side enables settlement on the other.

---

## 2) What Problem This Contract Solves (HTLC) 💡

On its own, a payment conditioned only on time or signatures can't guarantee *atomicity* of a two-party exchange. HTLCs enforce:

* 🔐 **Knowledge condition**: the taker must know a **secret preimage** whose hash is known on-chain.
* 🛡️ **Timeout safety**: if the taker doesn't act in time, the maker can safely reclaim funds.

This enables trust-reduced exchanges: "I'll pay you if (and only if) you reveal the secret before time T; otherwise, I get my money back."

---

## 3) How It Differs From `AtomicSwap.hs` 🔀

| Aspect               | `AtomicSwap.hs` (Marketplace listing)         | `AtomicSwapHTLC.hs` (HTLC)                                 |
| -------------------- | --------------------------------------------- | ---------------------------------------------------------- |
| 🔓 Unlock condition  | Exact payouts + delivery before deadline      | Reveal **preimage** matching on-chain hash before deadline |
| 👥 Roles checked     | Seller may cancel; buyer must fulfill payouts | Beneficiary may redeem with preimage; maker may refund     |
| 🕑 Time logic        | Buy **before**, Cancel **after** deadline     | Redeem **before**, Refund **after** deadline               |
| 🌍 Cross-chain use   | Not inherently cross-chain                    | Designed to be paired with a mirror HTLC elsewhere         |
| 🧮 Payout complexity | Potentially multiple payouts                  | Minimal payouts logic—focus is preimage + signature + time |

---

## 4) High-Level Flow (Redeem vs Refund) 🌊

```
Maker locks funds at HTLC
        |
        v
+---------------------------+
|   HTLC script UTXO        |
| datum: maker, beneficiary |
|        hash, deadline     |
+---------------------------+
   |                   |
Redeem (before T)      | Refund (after T)
   |                   |
- sha2_256(preimage)   | - maker signed
  == datum.hash        | - tx valid after T
- beneficiary signed   |
- tx valid before T    |
```

---

## 5) Language Extensions (Why they're here) 🔧

```haskell
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}
```

### 5.1) `DataKinds` 🧱

**What it does:** Promotes certain values (like string literals) to the type level.

**Why here:** Plutus' generated types and some ledger APIs rely on kind-level machinery (especially around builtins and typed data). It's a safe default when mixing with `TemplateHaskell` and Plutus APIs.

**If removed:** Some auto-derived instances/macros (via TH) may fail to typecheck in more complex setups.

### 5.2) `TemplateHaskell` 🧪

**What it does:** Enables compile-time meta-programming (splices like `$$(...)`, and deriving code with `PlutusTx.unstableMakeIsData`).

**Why here:**

* `PlutusTx.unstableMakeIsData ''HtlcDatum` & `''HtlcRedeemer` derive on-chain serialization (IsData).
* `PlutusTx.compile [|| mkUntyped ||]` compiles your validator to Plutus Core.

**If removed:** You cannot produce on-chain `IsData` instances or compile the validator to a script.

### 5.3) `NoImplicitPrelude` 🚫📚

**What it does:** Stops GHC from importing the standard `Prelude` automatically.

**Why here:** On-chain code must use **`PlutusTx.Prelude`** (not base Prelude) for deterministic builtins. You then manually import only what you need from base Prelude for off-chain (IO) parts.

**If removed:** You might accidentally use non-deterministic or unsupported functions on-chain.

### 5.4) `OverloadedStrings` 🔤

**What it does:** Makes string literals polymorphic (e.g., can become `ByteString`, `Text`, or Plutus builtins).

**Why here:**

* Helps write literals for `BuiltinByteString` and JSON text fields without lots of conversions.

**If removed:** You'll need explicit `BSC.pack`, `fromString`, or `toBuiltin` in many places.

### 5.5) `NamedFieldPuns` 🧩

**What it does:** Lets you write `HtlcDatum{hdMaker, hdBeneficiary, ...}` instead of `HtlcDatum{hdMaker=hdMaker,...}`.

**Why here:** Cleaner pattern matches in `mkHtlc`.

**If removed:** You must spell `field = localVar` for every field.

### 5.6) `MultiParamTypeClasses` 👥

**What it does:** Allows typeclasses with more than one type parameter.

**Why here:** A lot of Plutus/ledger internals and TH-generated instances lean on this in the background.

**If removed:** Some derived instances or dependencies may fail to compile.

### 5.7) `FlexibleInstances` 🧷

**What it does:** Allows more liberal instance heads than Haskell 2010 permits.

**Why here:** Common in the Plutus ecosystem (especially with TH and on-chain data types).

**If removed:** Instance derivations from Plutus macros can fail.

### 5.8) `ScopedTypeVariables` 🔭

**What it does:** Lets you refer to a type variable across a definition using `forall` scoping.

**Why here:** Often needed around TH and `unsafeFromBuiltinData` patterns; helpful for explicit type annotations.

**If removed:** You'll sometimes get "ambiguous type variable" errors or struggle to pin types in splices.

---

## 6) Imports (What each one is for) 📦

```haskell
module Main where

import Prelude (IO, (.))
import qualified Prelude as P

import qualified PlutusTx
import           PlutusTx.Prelude
  ( Bool(..)
  , (==)
  , (&&)
  , elem
  , traceIfFalse
  , traceError
  )
import qualified PlutusTx.Builtins as Builtins

import qualified Plutus.V2.Ledger.Api      as V2
import qualified Plutus.V1.Ledger.Interval as I

import Codec.Serialise (serialise)
import qualified Data.Aeson             as Aeson
import qualified Data.ByteString.Base16 as B16
import qualified Data.ByteString.Lazy   as LBS
import qualified Data.ByteString.Char8  as BSC
```

### 6.1) `module Main where` ▶️

This file is an **executable** (it writes `atomic-swap-htlc.plutus`), so it defines a `main :: IO ()`.

### 6.2) `Prelude (IO, (.))` and `qualified Prelude as P` 🔌

* **Why:** You disabled implicit Prelude, but you still need a few **off-chain** bits (like `IO`, function composition `(.)`, and `putStrLn`).
* **Pattern:** Use `PlutusTx.Prelude` for on-chain; import base `Prelude` **narrowly** for IO.
* **Tip:** Qualify as `P` and call `P.putStrLn`, `P.String` so it's obvious what is off-chain.

### 6.3) `PlutusTx` & `PlutusTx.Prelude` 🧠

* `PlutusTx` is needed for **Template Haskell** splices and (un)typed data helpers:
  * `PlutusTx.compile`, `PlutusTx.unstableMakeIsData`, `PlutusTx.unsafeFromBuiltinData`.
* `PlutusTx.Prelude` exposes the **on-chain** Prelude:
  * `Bool(..)`, `(==)`, `(&&)`, `elem`, `traceIfFalse`, `traceError`, etc.
* **Why:** On-chain code **must** use this Prelude to compile to Plutus Core and remain deterministic.

### 6.4) `PlutusTx.Builtins as Builtins` 🧱

* Gives access to low-level builtins like `sha2_256`.
* **Why:** Your HTLC checks `Builtins.sha2_256 preimage == hdHash`.

### 6.5) `Plutus.V2.Ledger.Api as V2` 📜

* All the **ledger V2** types/functions you need: `ScriptContext`, `TxInfo`, `PubKeyHash`, `POSIXTime`, `BuiltinData`, `mkValidatorScript`, `Validator`, etc.
* **Why:** Your validator is **Plutus V2**.

### 6.6) `Plutus.V1.Ledger.Interval as I` ⏱️

* Interval utilities `I.from`, `I.to`, `I.contains` for time-range checks.
* **Why:** You check "before deadline" (`I.to d`) and "after deadline" (`I.from d`) on `txInfoValidRange`.
* **Note:** Using V1 interval with V2 ledger API is normal—interval utils are stable and re-used.

### 6.7) Serialization & file output stack 🗂️

* `Codec.Serialise (serialise)` → turns your `Validator` into CBOR bytes.
* `Data.Aeson` → prepares the **JSON envelope** (`type`, `description`, `cborHex`).
* `Data.ByteString.Base16 as B16` → encodes CBOR bytes to hex string.
* `Data.ByteString.Lazy as LBS` → writing JSON file (`LBS.writeFile`).
* `Data.ByteString.Char8 as BSC` → unpack bytes to plain `String` for JSON field.

**Why this bundle?**
Cardano tools (CLI, wallets) expect a JSON with a `cborHex` representing your compiled script. This exact trio—**serialise → base16 → Aeson**—is the standard way to emit `*.plutus`.

---

## 7) On-Chain Data Types 🧬

### 7.1) `HtlcDatum` 🧾

```haskell
data HtlcDatum = HtlcDatum
  { hdMaker       :: V2.PubKeyHash
  , hdBeneficiary :: V2.PubKeyHash
  , hdHash        :: V2.BuiltinByteString  -- sha2_256(preimage)
  , hdDeadline    :: V2.POSIXTime
  }
```

* 🧑‍💼 **hdMaker** — who may **refund** after deadline.
* 🎁 **hdBeneficiary** — who may **redeem** with the preimage before deadline.
* 🧩 **hdHash** — the **SHA-256** hash of the secret preimage.
* ⌛ **hdDeadline** — the time boundary for Redeem vs Refund.

> 📝 The script uses `Builtins.sha2_256`.

### 7.2) `HtlcRedeemer` 📨

```haskell
data HtlcRedeemer
  = Redeem V2.BuiltinByteString  -- the preimage
  | Refund
```

* 🔓 **Redeem preimage** — beneficiary path.
* 🔒 **Refund** — maker path.

### 7.3) `IsData` & Lifting Instances 🧩

```haskell
PlutusTx.unstableMakeIsData ''HtlcDatum
PlutusTx.makeLift        ''HtlcDatum

PlutusTx.unstableMakeIsData ''HtlcRedeemer
PlutusTx.makeLift        ''HtlcRedeemer
```

* 🧬 **`unstableMakeIsData`** — derives on-chain serialization (to/from `BuiltinData`) so your datum/redeemer can cross the script boundary.
* 🚀 **`makeLift`** — allows values of these types to be used in TH splices and embedded in compiled Plutus Core.

> ✅ Keep both for smooth TH compilation and on-chain (de)serialization.

---

## 8) On-Chain Functions & Checks ⚙️

### 8.1) Helper Predicates 🛠️

#### `signedBy` ✅

```haskell
{-# INLINABLE signedBy #-}
signedBy :: V2.TxInfo -> V2.PubKeyHash -> Bool
signedBy info pkh = pkh `elem` V2.txInfoSignatories info
```

* 🔍 **What it proves:** the tx is signed by a specific public key (maker or beneficiary).
* 🧭 **Used in:** both paths (beneficiary must sign on `Redeem`; maker must sign on `Refund`).

#### `insideDeadline` ⏳ (redeem before or at)

```haskell
{-# INLINABLE insideDeadline #-}
insideDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
insideDeadline d info = I.contains (I.to d) (V2.txInfoValidRange info)
```

* 🟢 **Passes** when the transaction's validity range is wholly **≤ deadline**.
* 🧭 **Used in:** **Redeem** branch.

#### `afterDeadline` ⌛ (refund after or at)

```haskell
{-# INLINABLE afterDeadline #-}
afterDeadline :: V2.POSIXTime -> V2.TxInfo -> Bool
afterDeadline d info = I.contains (I.from d) (V2.txInfoValidRange info)
```

* 🟢 **Passes** when the transaction's validity range starts **≥ deadline**.
* 🧭 **Used in:** **Refund** branch.

> ℹ️ Interval utilities:
>
> * `I.to d`  → `[−∞, d]`
> * `I.from d`→ `[d, +∞]`
> * `I.contains a b` → "interval `a` fully contains interval `b`".

---

### 8.2) Core Validator 🔎

#### `mkHtlc` — the on-chain decision function

```haskell
{-# INLINABLE mkHtlc #-}
mkHtlc :: HtlcDatum -> HtlcRedeemer -> V2.ScriptContext -> Bool
mkHtlc HtlcDatum{hdMaker, hdBeneficiary, hdHash, hdDeadline} redeemer ctx =
  let info = V2.scriptContextTxInfo ctx
  in case redeemer of
      -- beneficiary path
      Redeem preimage ->
           traceIfFalse "bad preimage"
             (Builtins.sha2_256 preimage == hdHash)
        && traceIfFalse "too late"
             (insideDeadline hdDeadline info)
        && traceIfFalse "not beneficiary"
             (signedBy info hdBeneficiary)

      -- maker path
      Refund ->
           traceIfFalse "too early"
             (afterDeadline hdDeadline info)
        && traceIfFalse "not maker"
             (signedBy info hdMaker)
```

* 🔓 **Redeem** (beneficiary):
  * ✅ `sha2_256(preimage) == hdHash`
  * ✅ `insideDeadline hdDeadline info`
  * ✅ `signedBy info hdBeneficiary`
* 🔒 **Refund** (maker):
  * ✅ `afterDeadline hdDeadline info`
  * ✅ `signedBy info hdMaker`
* 🧵 **Diagnostics:** fails with human-readable messages (`"bad preimage"`, `"too late"`, etc.) via `traceIfFalse`.

> 🧠 Hashing: `Builtins.sha2_256 :: BuiltinByteString -> BuiltinByteString`

---

### 8.3) Untyped Wrapper & Compiled Script 🧱

#### `mkUntyped` — converts raw `BuiltinData` to typed values

```haskell
{-# INLINABLE mkUntyped #-}
mkUntyped :: V2.BuiltinData -> V2.BuiltinData -> V2.BuiltinData -> ()
mkUntyped d r c =
  let datum    = PlutusTx.unsafeFromBuiltinData d :: HtlcDatum
      redeemer = PlutusTx.unsafeFromBuiltinData r :: HtlcRedeemer
      ctx      = PlutusTx.unsafeFromBuiltinData c :: V2.ScriptContext
  in if mkHtlc datum redeemer ctx
        then ()
        else traceError "HTLC validation failed"
```

* 🧰 Bridges untyped (on-chain) and typed (Haskell) worlds.
* ⚠️ Uses `unsafeFromBuiltinData` (assumes well-formed data); that's fine for validators.

#### `htlcValidator` — actual Plutus V2 validator

```haskell
htlcValidator :: V2.Validator
htlcValidator =
  V2.mkValidatorScript
    $$(PlutusTx.compile [|| mkUntyped ||])
```

* 🧪 **`PlutusTx.compile`** compiles your wrapped validator into Plutus Core.
* 🧩 **`mkValidatorScript`** produces a `Validator` value usable by off-chain tooling.

---

### 8.4) Ledger/Prelude Functions You're Using 🧭

* **From `PlutusTx.Prelude`:**
  * `Bool(..)`, `(==)`, `(&&)`, `elem`, `traceIfFalse`, `traceError`
* **From `PlutusTx.Builtins`:**
  * `sha2_256`
* **From `Plutus.V2.Ledger.Api` (aliased `V2`):**
  * `ScriptContext`, `TxInfo`, `PubKeyHash`, `POSIXTime`, `BuiltinData`
  * `scriptContextTxInfo`, `txInfoSignatories`, `txInfoValidRange`
  * `Validator`, `mkValidatorScript`
* **From `Plutus.V1.Ledger.Interval` (aliased `I`):**
  * `to`, `from`, `contains`

---

### 8.5) Validation Truth Table 🧪

| Path   | Condition                        | Must Hold |
| ------ | -------------------------------- | --------- |
| Redeem | `sha2_256 preimage == hdHash`    | ✅         |
| Redeem | `insideDeadline hdDeadline info` | ✅         |
| Redeem | `signedBy info hdBeneficiary`    | ✅         |
| Refund | `afterDeadline hdDeadline info`  | ✅         |
| Refund | `signedBy info hdMaker`          | ✅         |

> ❌ If **any** condition is false, the script fails (with the corresponding `traceIfFalse` message).

---

## 9) Validation Logic ✅

### 9.1) Redeem (preimage path) 🔓

To succeed, **all** must hold:

1. ✅ `sha2_256 preimage == hdHash`
2. ⏱️ Transaction validity range is **inside** `I.to hdDeadline` (i.e., **before** deadline)
3. ✍️ **Beneficiary** signed the transaction (`hdBeneficiary ∈ txInfoSignatories`)

If any fail → `traceError` with helpful message (e.g., "bad preimage", "too late", "not beneficiary").

### 9.2) Refund (timeout path) 🕰️

To succeed, **both** must hold:

1. ⏱️ Transaction validity range is **inside** `I.from hdDeadline` (i.e., **after** deadline)
2. ✍️ **Maker** signed the transaction (`hdMaker ∈ txInfoSignatories`)

If either fails → refund invalid.

### 9.3) Time window semantics (important) ⏳

* **Before deadline** check uses **`I.to t`**. Your tx's validity interval must be contained in this interval.
* **After deadline** check uses **`I.from t`**.
  Make sure off-chain code sets *POSIX time* correctly and chooses a range that truly intersects these intervals (slot→POSIX conversions matter).

---

## 10) Producing the `atomic-swap-htlc.plutus` file 📦

`main` in `AtomicSwapHTLC.hs`:

* 🧠 Compiles `mkUntyped` via `PlutusTx.compile`
* 🧾 Wraps the validator as JSON:

```json
{
  "type": "PlutusScriptV2",
  "description": "HTLC atomic swap validator",
  "cborHex": "<hex>"
}
```

* 💾 Saves as `atomic-swap-htlc.plutus`.

This is the file you pass to wallets/CLI when building transactions.

---

## 11) Testing the Contract 🧪

You already added `tests/AtomicSwapHTLCSpec.hs` and wired it in `tests/Spec.hs`.

### 11.1) Test scenarios covered 🧰

1. ✅ **Redeem succeeds** with correct preimage, beneficiary signature, **before** deadline.
2. ❌ **Redeem fails** with wrong preimage (still before deadline, signed by beneficiary).
3. ✅ **Refund succeeds** for maker **after** deadline, signed by maker.
4. ❌ **Refund fails** for maker **before** deadline.

These map exactly onto the validator's two branches.

### 11.2) Running the tests ▶️

```bash
cabal test wspace-tests
```

You should see the "AtomicSwap HTLC" group pass.

### 11.3) Quick property-test ideas (optional) 💭

* 📈 **Monotonicity in time**: any valid Redeem with range ⊆ `I.to d` should fail if you shift the range to be ⊆ `I.from d`.
* 🧪 **Signature necessity**: remove the required signer and assert failure (both branches).
* 🔐 **Preimage soundness**: assert `sha2_256 x == hdHash` iff Redeem passes the first guard.

---

## 12) Off-Chain Builder Checklist 🧱

**Redeem (beneficiary path)**

* [ ] ⏱️ Validity range ⊆ `I.to hdDeadline`
* [ ] ✍️ Include **beneficiary** signature
* [ ] 🔨 Provide redeemer `Redeem preimage`
* [ ] 💸 Spend the script UTXO and send funds to the beneficiary's desired outputs
* [ ] 🧯 Provide collateral input (Plutus requirement)
* [ ] 🧮 Balance & sign

**Refund (maker path)**

* [ ] ⏱️ Validity range ⊆ `I.from hdDeadline`
* [ ] ✍️ Include **maker** signature
* [ ] 🔒 Provide redeemer `Refund`
* [ ] 💸 Pay funds back to maker (wallet code handles outputs; script only enforces signer/time)
* [ ] 🧯 Provide collateral; 🧮 balance & sign

> 💡 If you also want to enforce "exact refund amount" like your marketplace script, that would be an additional check (not present in the current HTLC).

---

## 13) Worked Examples (Datums & Redeemers) 🧩

### 13.1) Datum (simple ADA HTLC)

```haskell
let makerPkh       = "<pkh hex>"
    beneficiaryPkh = "<pkh hex>"
    deadline       = 1_735_000_000 -- POSIX ms
    hash           = Builtins.sha2_256 "supersecret"
in HtlcDatum
     { hdMaker       = makerPkh
     , hdBeneficiary = beneficiaryPkh
     , hdHash        = hash
     , hdDeadline    = deadline
     }
```

### 13.2) Redeemer (Redeem with correct preimage)

```haskell
Redeem "supersecret"
```

### 13.3) Redeemer (Refund)

```haskell
Refund
```

---

## 14) Edge Cases & Pitfalls ⚠️

* ⛔ **Wrong validity range**: Redeem with `I.from` or Refund with `I.to` will fail.
* 🖊️ **Missing required signature**: beneficiary must sign for Redeem; maker must sign for Refund.
* 🧮 **Hash mismatch**: any bit-flip in the preimage yields a different SHA-256; Redeem fails.
* 🪙 **Boundary behavior**: clarify whether your environment treats `I.to deadline` as including or excluding the endpoint—set times with a small margin to be safe.
* ₳ **Min-ADA**: the validator doesn't check output values; your wallet code must still respect ledger min-ADA for outputs.

---

## 15) Glossary of Terms 📚

**HTLC (Hash Time-Locked Contract)** — A script that releases funds if a secret preimage is revealed before a timeout, otherwise refunds after timeout.

**Preimage / Hash** — The secret string (**preimage**) whose **sha2_256** equals the on-chain hash (`hdHash`).

**Maker** — Party who funds and can refund after deadline.

**Beneficiary** — Party who can claim by revealing the preimage before deadline.

**Deadline / POSIX time** — The time boundary that splits Redeem (before) and Refund (after).

**Validity interval** — The time range attached to a transaction, checked by the validator.

**Script context** — On-chain view of the spending transaction (signers, time range, inputs/outputs).

**Signatories** — Public keys that signed the transaction; used to check maker/beneficiary control.

**Collateral** — ADA input designated to cover script failure fees.

**Plutus V2** — The Plutus version targeted by this validator.

**`I.to t` / `I.from t`** — Interval constructors used to express "before t" and "after t".