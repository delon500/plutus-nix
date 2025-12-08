# RevenueSplitter.hs – Beginner Tutorial / Documentation

## Table of Contents

- [RevenueSplitter.hs – Beginner Tutorial / Documentation](#revenuesplitterhs--beginner-tutorial--documentation)
  - [Table of Contents](#table-of-contents)
  - [1. Overview](#1-overview)
  - [2. What Problem This Contract Solves](#2-what-problem-this-contract-solves)
    - [How `RevenueSplitter` fixes this on-chain](#how-revenuesplitter-fixes-this-on-chain)
  - [3. High-Level Flow (Lock Revenue → Distribute Shares)](#3-high-level-flow-lock-revenue--distribute-shares)
    - [3.1 Setup: event ID and recipient shares](#31-setup-event-id-and-recipient-shares)
    - [3.2 Locking the revenue pot at the script](#32-locking-the-revenue-pot-at-the-script)
    - [3.3 Distribution transaction (on-chain `Distribute` branch)](#33-distribution-transaction-on-chain-distribute-branch)
  - [4. On-Chain Data Types](#4-on-chain-data-types)
    - [4.1 `RevenueDatum`](#41-revenuedatum)
      - [Fields](#fields)
      - [Why `unstableMakeIsData`?](#why-unstablemakeisdata)
    - [4.2 `RevenueRedeemer`](#42-revenueredeemer)
      - [`Distribute`](#distribute)
  - [5. Language Extensions (Why they’re here)](#5-language-extensions-why-theyre-here)
    - [5.1 `DataKinds`](#51-datakinds)
    - [5.2 `NoImplicitPrelude`](#52-noimplicitprelude)
    - [5.3 `TemplateHaskell`](#53-templatehaskell)
    - [5.4 `ScopedTypeVariables`](#54-scopedtypevariables)
    - [5.5 `OverloadedStrings`](#55-overloadedstrings)
    - [5.6 `TypeApplications`](#56-typeapplications)
  - [6. Imports (What each one is for)](#6-imports-what-each-one-is-for)
    - [6.1 Module structure (`RevenueSplitterContract`, `RevenueSplitter`)](#61-module-structure-revenuesplittercontract-revenuesplitter)
      - [`RevenueSplitterContract.hs`](#revenuesplittercontracths)
      - [`RevenueSplitter.hs`](#revenuesplitterhs)
    - [6.2 `Prelude` and `qualified Prelude as P`](#62-prelude-and-qualified-prelude-as-p)
    - [6.3 Plutus core imports](#63-plutus-core-imports)
      - [In `RevenueSplitterContract.hs` (on-chain validator)](#in-revenuesplittercontracths-on-chain-validator)
      - [In `RevenueSplitter.hs` (writer executable)](#in-revenuesplitterhs-writer-executable)
    - [6.4 Serialization stack](#64-serialization-stack)
    - [6.5 Cardano API imports](#65-cardano-api-imports)
      - [Text envelope `.plutus` file](#text-envelope-plutus-file)
      - [Script hash \& Bech32 address](#script-hash--bech32-address)
  - [7. Revenue Splitter Validator Logic (`RevenueSplitterContract`)](#7-revenue-splitter-validator-logic-revenuesplittercontract)
    - [7.1 Shared helpers (`info`, `ownInput`, `inputAda`)](#71-shared-helpers-info-owninput-inputada)
    - [7.2 Core invariants: "sum of shares == input ADA"](#72-core-invariants-sum-of-shares--input-ada)
      - [`RevenueDatum` and the share list](#revenuedatum-and-the-share-list)
      - [Summing the shares](#summing-the-shares)
      - [Comparing with the input ADA](#comparing-with-the-input-ada)
    - [7.3 Recipient payment checks (`valuePaidTo` each recipient)](#73-recipient-payment-checks-valuepaidto-each-recipient)
      - [`valuePaidTo ti pkh`](#valuepaidto-ti-pkh)
      - [Underpayment check](#underpayment-check)
    - [7.4 Untyped wrapper and compiled validator](#74-untyped-wrapper-and-compiled-validator)
  - [8. Producing `revenue-splitter.plutus`](#8-producing-revenue-splitterplutus)
    - [8.1 `revenue-splitter-exe` (validator writer)](#81-revenue-splitter-exe-validator-writer)
    - [8.2 Script hash and Bech32 script address output](#82-script-hash-and-bech32-script-address-output)
      - [8.2.1 Plutus-style validator hash](#821-plutus-style-validator-hash)
      - [8.2.2 Bech32 script address (for CLI \& wallets)](#822-bech32-script-address-for-cli--wallets)
  - [9. Testing the Contract](#9-testing-the-contract)
    - [9.1 What `RevenueSplitterSpec` tests](#91-what-revenuesplitterspec-tests)
      - [9.1.1 Valid split passes when totals and outputs match](#911-valid-split-passes-when-totals-and-outputs-match)
      - [9.1.2 Fails when sum of shares does **not** match input ADA](#912-fails-when-sum-of-shares-does-not-match-input-ada)
      - [9.1.3 Fails when one recipient is underpaid](#913-fails-when-one-recipient-is-underpaid)
    - [9.2 Running the tests](#92-running-the-tests)
  - [10. Glossary of Terms](#10-glossary-of-terms)
    - [10.1 Revenue pot / pool](#101-revenue-pot--pool)
    - [10.2 Share / allocation (in lovelace)](#102-share--allocation-in-lovelace)
    - [10.3 Recipient](#103-recipient)
    - [10.4 Event ID (`rdEventId`)](#104-event-id-rdeventid)
    - [10.5 Datum (`RevenueDatum`)](#105-datum-revenuedatum)
    - [10.6 Redeemer (`RevenueRedeemer`)](#106-redeemer-revenueredeemer)
    - [10.7 Validator](#107-validator)
    - [10.8 Script UTxO](#108-script-utxo)
    - [10.9 Script address](#109-script-address)
    - [10.10 Text envelope (`.plutus` file)](#1010-text-envelope-plutus-file)
    - [10.11 How these concepts connect (revenue distribution diagram)](#1011-how-these-concepts-connect-revenue-distribution-diagram)

## 1. Overview

`RevenueSplitterContract` is a **Plutus V2 validator** that models a simple but powerful pattern:

> **Lock a pot of ADA at a script address, then atomically split it among a list of recipients according to pre-agreed shares.**

Each UTxO at this script represents **one revenue pool** for a specific event or context:

- The **datum** (`RevenueDatum`) stores:
  - an **event ID** (`rdEventId`) – a label like `"CONCERT-2025-JHB"` or `"MATCH-001"`,
  - a list of **recipients and their shares** (`rdRecipients :: [(PubKeyHash, Integer)]`),  
    where each share is an amount in **lovelace**.

- The **value** locked at the script is the **total ADA to be distributed**.

When it’s time to pay everyone, a single transaction:

- **spends** this script UTxO,
- uses the **`Distribute`** redeemer,
- creates outputs paying ADA to each recipient.

The validator checks:

1. The **sum of all shares** in the datum equals the **ADA locked in the script input**, and
2. Each recipient is paid **at least** their share.

If all conditions hold, the transaction is valid and the revenue is split correctly in one shot.

This validator is used alongside the **Sports Tickets** contract:

- Tickets handle **who buys / owns / uses** seats.
- **RevenueSplitter** handles **how the money is divided** once the event is over.

---

## 2. What Problem This Contract Solves

In a typical event (sports, concert, festival), money has to be shared between several parties:

- the **organiser**,
- the **venue**,
- **artists / teams**,
- **promoters**,
- maybe a **platform** or **ticketing partner**.

Off-chain, this is often done with:

- spreadsheets,
- manual calculations,
- ad-hoc bank transfers.

That leads to several problems:

1. **Calculation errors**

   - Manual summing and percentage calculations are easy to get wrong.
   - A single typo can underpay or overpay someone.

2. **Lack of transparency**

   - Recipients have to **trust** the organiser’s spreadsheet.
   - It’s hard to prove that:
     - “The pot was really X ADA.”
     - “I really got my correct cut.”

3. **Fragmented payments**

   - Multiple separate transactions from a central wallet.
   - Hard to audit the exact link between **“this pot of money”** and **“these final payouts”**.

4. **Race conditions / partial payouts**

   - Some people might get paid earlier, others later.
   - If something goes wrong mid-way, it’s unclear what still needs to be paid out.

---

### How `RevenueSplitter` fixes this on-chain

The Revenue Splitter contract encodes the **payout agreement** directly into the UTxO:

1. **Locking the pot**

   - Off-chain, once ticket sales are done, the organiser sends **all ADA to be split** into **one script UTxO** at the `RevenueSplitterContract` address.
   - The attached `RevenueDatum` lists:
     - **who** is to be paid (`PubKeyHash`),
     - **how much** each should receive (exact amount in lovelace),
     - and the **event ID** as context.

2. **Single atomic distribution**

   - A **single transaction** spends that UTxO with redeemer `Distribute`.
   - The validator enforces:

     ```haskell
     sum (shares in rdRecipients) == ADA in script input
     each recipient gets at least their share
     ```

   - If any recipient is underpaid or the totals don’t match, the transaction is **invalid**.

3. **Auditability**

   - On-chain, anyone can see:

     - the **input UTxO** (the total pot),
     - the **datum** (who should be paid what),
     - the **outputs** (who actually got paid).

   - This gives a clear, immutable link:

     > “These are the revenue shares we agreed on”  
     > **→** “Here is the exact transaction that enforced it.”

4. **Generic and reusable**

   Even though it’s used in your **Sports & Entertainment** dApp, the pattern is generic:

   - any **DAO treasury payout**,
   - any **profit-sharing agreement**,
   - any **multi-party revenue split**

   can reuse the same `RevenueDatum` + `Distribute` logic.

In short:

> Instead of trusting the organiser’s spreadsheet, everyone can trust the **on-chain validator** to enforce the split precisely and atomically.

## 3. High-Level Flow (Lock Revenue → Distribute Shares)

At a high level, the Revenue Splitter flow looks like this:

1. **Agree the split** off-chain:
   - Decide the **event ID** and the list of **(recipient, share)** pairs.
2. **Lock the pot**:
   - Send all ADA to be shared into **one UTxO** at the `RevenueSplitterContract` address, with a matching `RevenueDatum`.
3. **Distribute**:
   - Build a single transaction that:
     - **spends** that script UTxO,
     - uses redeemer `Distribute`,
     - pays each recipient at least their share.
   - The validator enforces that the **total shares** equal the **input ADA**, and that **no one is underpaid**.

If anything doesn’t line up (wrong total, underpayment, etc.), the on-chain validator rejects the transaction.

---

### 3.1 Setup: event ID and recipient shares
Before touching the blockchain, some off-chain agreement has to happen:

1. **Choose an event ID**

   A simple label such as:

   - `"MATCH-001"`,
   - `"CONCERT-2025-JHB"`,
   - `"FESTIVAL-DAY-3"`.

   This is stored in `rdEventId :: BuiltinByteString` and acts as a **link** between:

   - ticket sales / business logic off-chain, and
   - this **revenue pool** on-chain.

2. **Define the recipients**

   Decide who must receive ADA:

   ```haskell
   rdRecipients :: [(PubKeyHash, Integer)]
   ```
    Each pair is:

    * `PubKeyHash` – recipient’s wallet identity,
    * `Integer` – share in **lovelace** (not percentage).

    Example:

    ```haskell
    [ (organiserPkh, 6_000_000)   -- 6 ADA
    , (venuePkh,     3_000_000)   -- 3 ADA
    , (performerPkh, 1_000_000)   -- 1 ADA
    ]
    ```

3. **Check that the math balances (off-chain)**

   You’ll typically compute:

   ```haskell
   totalShares = sum (map snd rdRecipients)
   ```

   This `totalShares` is the **exact ADA** that needs to be locked at the script later.

   > 💡 The validator will **re-check** this on-chain by comparing:
   >
   > `sum (shares in rdRecipients)` vs. `inputAda ctx`.

---

### 3.2 Locking the revenue pot at the script
Once the split is agreed, the organiser (or dApp) creates a **funding transaction** that:

* Sends a single UTxO to the **RevenueSplitter script address**.
* Attaches a `RevenueDatum` that encodes the agreed split.

**Off-chain pattern:**

1. Construct a `RevenueDatum`:

   ```haskell
   datum = RevenueDatum
     { rdEventId    = "CONCERT-2025-JHB"
     , rdRecipients =
         [ (organiserPkh, 6_000_000)
         , (venuePkh,     3_000_000)
         , (performerPkh, 1_000_000)
         ]
     }
   ```

2. Compute `totalShares` off-chain:

   ```haskell
   totalShares = 6_000_000 + 3_000_000 + 1_000_000  -- 10 ADA in lovelace
   ```

3. Build a transaction with:

   * **Output**:

     * Address: `revenueSplitterScriptAddress`
     * Value: `totalShares` ADA
     * Datum: `datum` (inline or attached, depending on your off-chain code)

4. Submit the transaction.

On-chain, this is just a normal UTxO creation. The validator does **not** run yet; it will only run when that UTxO is later **spent** with redeemer `Distribute`.

After this step:

```text
+--------------------------------------------------------+
|  Script UTxO at RevenueSplitter address                |
|                                                        |
|  Value:   totalShares ADA                              |
|  Datum:   RevenueDatum { rdEventId, rdRecipients }     |
+--------------------------------------------------------+
```

You now have a **locked revenue pool** that everyone can see on-chain.

---

### 3.3 Distribution transaction (on-chain `Distribute` branch)

When it’s time to actually pay everyone, the dApp builds the **distribution transaction**.

This is where the validator logic in `mkRevenueValidator` runs.

**Off-chain pattern for distribution:**

The transaction:

* **Inputs**:

  * The single script UTxO at `RevenueSplitterContract` containing:

    * value: `inputAda` (total ADA pot),
    * datum: `RevenueDatum { rdEventId, rdRecipients }`.
* **Redeemer**:

  * `Distribute`.
* **Outputs**:

  * One **payment output per recipient**, each sending at least `share` lovelace to the corresponding `PubKeyHash`.
  * Optional **change** output(s) if you’re also bringing other inputs to pay fees, etc.

There is **no continuing output** at the script — the pot is fully consumed.

**What the validator enforces in `mkRevenueValidator`:**

```haskell
mkRevenueValidator :: RevenueDatum -> RevenueRedeemer -> ScriptContext -> Bool
mkRevenueValidator dat _ ctx =
       traceIfFalse "share sum != input ADA" sharesMatchInput
    && traceIfFalse "some recipient underpaid" recipientsPaid
```

1. **Shares match the input ADA**

   ```haskell
   requiredTotal :: Integer
   requiredTotal = sum (fmap snd (rdRecipients dat))

   inputTotal :: Integer
   inputTotal = inputAda ctx  -- ADA locked in the script input

   sharesMatchInput :: Bool
   sharesMatchInput = inputTotal == requiredTotal
   ```

   * It recomputes `requiredTotal` from the datum.

   * It reads how much ADA is in the **script input**.

   * If they are not **exactly equal**, the transaction is invalid.

   > This guarantees:
   > “The pot being distributed matches the exact agreed shares.”

2. **Each recipient is paid at least their share**

   ```haskell
   recipientsPaid :: Bool
   recipientsPaid =
     all recipientsOk (rdRecipients dat)

   recipientsOk :: (PubKeyHash, Integer) -> Bool
   recipientsOk (pkh, share) =
     let vPaid = valuePaidTo ti pkh
         ada   = valueOf vPaid adaSymbol adaToken
     in ada >= share
   ```

   * For each `(pkh, share)` in `rdRecipients`:

     * Compute all ADA paid to `pkh` in this transaction (`valuePaidTo`).
     * Ensure it’s **≥ share**.

   * If **any** recipient gets less than their share, the whole script fails.

   > This means you can overpay someone (e.g. give them a tip),
   > but you can never underpay relative to the datum.

3. **Atomicity**

   Because this is a single UTxO spent in one transaction:

   * Either **all recipients are paid correctly** and the script passes,
   * Or **none of them are paid** (transaction is invalid, never on-chain).

   There’s no “half-distributed” state stored on-chain.

**Result of the distribution tx:**

```text
Before:

+--------------------------------------------------------+
| Script UTxO @ RevenueSplitter address                  |
|  Value:   totalShares ADA                              |
|  Datum:   rdRecipients = [(pkh1,a1),(pkh2,a2),...]      |
+--------------------------------------------------------+

After (if valid):

- Script UTxO is consumed (no longer exists).
- Outputs to:
    pkh1: at least a1 ADA
    pkh2: at least a2 ADA
    ...
- Optional: change outputs, fees, etc.
```

Anyone inspecting the ledger can clearly see:

1. The **original pot** and agreed distribution (from the datum).
2. The **distribution transaction** that enforced those shares.
3. The final **payouts** for each recipient.

This closes the loop: **Lock Revenue → Distribute Shares** in a transparent, auditable, and atomic way.


## 4. On-Chain Data Types

The Revenue Splitter contract works with **one datum type** and **one redeemer constructor**:

- `RevenueDatum` – describes how a single **revenue pot** must be split.
- `RevenueRedeemer` – tells the validator which action is being taken (currently only `Distribute`).

These types live in `RevenueSplitterContract.hs` and are what get encoded as on-chain `Data`.

---

### 4.1 `RevenueDatum`

```haskell
data RevenueDatum = RevenueDatum
  { rdEventId    :: BuiltinByteString          -- ^ Event identifier
  , rdRecipients :: [(PubKeyHash, Integer)]    -- ^ (recipient, share in lovelace)
  }
PlutusTx.unstableMakeIsData ''RevenueDatum
````

#### Fields

1. **`rdEventId :: BuiltinByteString`**

   A short identifier that **labels which event this pot belongs to**, for example:

   * `"MATCH-001"`,
   * `"CONCERT-2025-JHB"`,
   * `"FEST-OPENING-NIGHT"`.

   On-chain, it’s just metadata, but it’s very useful:

   * Off-chain code can **group** pots / distributions by event.
   * Explorers or dashboards can show:
     “This UTxO holds revenue for **Event X**.”

2. **`rdRecipients :: [(PubKeyHash, Integer)]`**

   A list of **(recipient, share)** pairs, where:

   * `PubKeyHash` – the wallet identity of a recipient.
   * `Integer` – their **share in lovelace** (1 ADA = 1_000_000 lovelace).

   Example:

   ```haskell
   rdRecipients =
     [ (organiserPkh, 6_000_000)   --  6 ADA
     , (venuePkh,     3_000_000)   --  3 ADA
     , (performerPkh, 1_000_000)   --  1 ADA
     ]
   ```

   This list is the **source of truth** for:

   * How much ADA each address should get.
   * What the validator will enforce during `Distribute`.

#### Why `unstableMakeIsData`?

```haskell
PlutusTx.unstableMakeIsData ''RevenueDatum
```

* Generates on-chain `IsData` instances so that:

  * `RevenueDatum` can be encoded into `BuiltinData`,
  * decoded from `BuiltinData` (via `unsafeFromBuiltinData` in the untyped wrapper).

* This is what allows `RevenueDatum` to live **in the datum field** of the script UTxO.

In other words: without this TH line, you couldn’t attach `RevenueDatum` as on-chain data to the revenue pot.

---

### 4.2 `RevenueRedeemer`

```haskell
data RevenueRedeemer = Distribute
PlutusTx.unstableMakeIsData ''RevenueRedeemer
```

The redeemer tells the script **which action** the transaction is trying to perform when it spends the revenue UTxO.

Right now, the design is intentionally simple:

* There is only **one action**: `Distribute`.

#### `Distribute`

* Meaning:

  > “Spend the pot UTxO and distribute its ADA according to `rdRecipients`.”

* When the script sees redeemer `Distribute`, it:

  1. Reads the `RevenueDatum` from the input UTxO.

  2. Recomputes the **expected total**:

     ```haskell
     requiredTotal = sum (fmap snd (rdRecipients dat))
     ```

  3. Reads how much ADA is actually locked in the script input (`inputAda ctx`).

  4. Verifies:

     * `requiredTotal == inputAda ctx`
     * and each `PubKeyHash` in `rdRecipients` is paid at least its `share`.

No other behaviour is allowed:

* There is no partial “update” redeemer.
* There is no “change my mind” redeemer.
* The pot goes from:

  * **locked**, to
  * **fully paid out**,
    in a single atomic transaction.

Again, `unstableMakeIsData` is used:

```haskell
PlutusTx.unstableMakeIsData ''RevenueRedeemer
```

so that `Distribute` can be sent as on-chain `BuiltinData` in the redeemer field and decoded in:

```haskell
mkRevenueValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
```

---

> Summary:
> * `RevenueDatum` = **Who** should be paid and **how much** for a specific event.
> * `RevenueRedeemer` = **What** we are doing with this pot (currently only: *distribute it according to the datum*).

## 5. Language Extensions (Why they’re here)

Both `RevenueSplitterContract.hs` (on-chain validator) and `RevenueSplitter.hs` (off-chain writer for the `.plutus` file) use a “standard” Plutus extension set:

```haskell
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE TypeApplications    #-}
````

Let’s briefly unpack **what each one does**, **why it’s needed here**, and **what would break** if you removed it.

---

### 5.1 `DataKinds`

**What it does**

* Promotes certain values/constructors to the **type level** (kind `Symbol`, `Nat`, promoted constructors, etc.).

**Why it’s here**

* Plutus libraries and TH-generated code often rely on `DataKinds` behind the scenes.
* It’s a safe default for on-chain modules like `RevenueSplitterContract`, especially when using Template Haskell and ledger types.

**If removed**

* In this file, you might *initially* be fine, but:

  * Future refactors or more advanced typed APIs may stop compiling.
  * Many Plutus examples just keep `DataKinds` on by default to avoid subtle type issues.

---

### 5.2 `NoImplicitPrelude`

**What it does**

* Stops GHC from automatically importing the standard `Prelude`.

**Why it’s here**

* On-chain Plutus code must use **`PlutusTx.Prelude`**, not the normal Haskell `Prelude`, because:

  * It’s deterministic and subsetted for on-chain.
  * It provides `Bool`, `Integer`, `traceIfFalse`, `(==)`, `(&&)`, etc., in a Plutus-safe way.

* In `RevenueSplitterContract.hs` we explicitly import:

  ```haskell
  import PlutusTx.Prelude hiding (Semigroup(..), unless)
  ```

* In `RevenueSplitter.hs` (the writer executable) we import base `Prelude` explicitly:

  ```haskell
  import Prelude (IO, FilePath, String, putStrLn, (<>))
  import qualified Prelude as P
  ```

  so it’s *very clear* where off-chain `IO` stuff is coming from.

**If removed**

* Normal `Prelude` would sneak into the on-chain module.
* You could accidentally use unsupported or non-deterministic functions (e.g. standard `foldr`, `show`, `print`) inside validator logic.
* The Plutus plugin might reject or miscompile such code.

---

### 5.3 `TemplateHaskell`

**What it does**

* Enables compile-time metaprogramming using splices like `$(...)` and `$$(...)`.

**Why it’s here**

In `RevenueSplitterContract.hs`, you use Template Haskell in two crucial ways:

1. **Deriving IsData** for your custom types:

   ```haskell
   PlutusTx.unstableMakeIsData ''RevenueDatum
   PlutusTx.unstableMakeIsData ''RevenueRedeemer
   ```

   This generates the plumbing needed to turn your Haskell types into on-chain `Data` and back.

2. **Compiling the validator to Plutus Core**:

   ```haskell
   validator :: Validator
   validator =
     mkValidatorScript $$(PlutusTx.compile [|| mkRevenueValidatorUntyped ||])
   ```

   * `PlutusTx.compile` turns your Haskell validator into Plutus Core.
   * `$$( ... )` splices the compiled script at compile time.

**If removed**

* You would lose:

  * auto-derived `IsData` instances,
  * the ability to compile `mkRevenueValidatorUntyped` into a `Validator`.
* The whole `validator` script and the on-chain representation of `RevenueDatum`/`RevenueRedeemer` would fail to build.

---

### 5.4 `ScopedTypeVariables`

**What it does**

* Makes explicit type variables in a function’s signature available throughout the function body.

**Why it’s here**

In the untyped wrapper:

```haskell
{-# INLINABLE mkRevenueValidatorUntyped #-}
mkRevenueValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkRevenueValidatorUntyped d r c =
  let dat = unsafeFromBuiltinData @RevenueDatum    d
      red = unsafeFromBuiltinData @RevenueRedeemer r
      ctx = unsafeFromBuiltinData @ScriptContext   c
  in if mkRevenueValidator dat red ctx
        then ()
        else error ()
```

* We use `TypeApplications` (`@RevenueDatum`, `@RevenueRedeemer`, `@ScriptContext`) to **fix the type** we want to decode to.
* `ScopedTypeVariables` ensures those type variables are understood consistently inside the function body.

**If removed**

* GHC would often complain about ambiguous types when using `unsafeFromBuiltinData @SomeType`.
* You’d need either:

  * more verbose local type annotations, or
  * to avoid `TypeApplications` and rely on less explicit inference.

---

### 5.5 `OverloadedStrings`

**What it does**

* Allows string literals like `"hello"` to be interpreted as different string-like types, e.g. `Text`, `ByteString`, `BuiltinByteString`, etc.

**Why it’s here**

* In the writer executable `RevenueSplitter.hs`, you have:

  ```haskell
  description :: C.TextEnvelopeDescr
  description = "Revenue Splitter Plutus Validator"
  ```

  and Cardano API types often use `Text` under the hood, so this saves you from `T.pack`.

* In on-chain code or parameter definitions, you might also want to write things like:

  ```haskell
  rdEventId = "CONCERT-2025-JHB"
  ```

  directly as a `BuiltinByteString` if the surrounding types expect it.

**If removed**

* Every time you use a string literal for `Text` or `BuiltinByteString`, you’d need to manually convert, e.g.:

  ```haskell
  description = T.pack "Revenue Splitter Plutus Validator"
  ```

* Not wrong—just more boilerplate.

---

### 5.6 `TypeApplications`

**What it does**

* Lets you explicitly supply type arguments using the `@Type` syntax.

**Why it’s here**

* In the untyped wrapper we saw earlier:

  ```haskell
  dat = unsafeFromBuiltinData @RevenueDatum    d
  red = unsafeFromBuiltinData @RevenueRedeemer r
  ctx = unsafeFromBuiltinData @ScriptContext   c
  ```

  This pattern is standard in Plutus validators:

  * It makes it **crystal clear** which type each `BuiltinData` is being decoded into.
  * It plays nicely with `ScopedTypeVariables` to avoid ambiguity.

**If removed**

* You’d have to write something like:

  ```haskell
  let dat :: RevenueDatum
      dat = unsafeFromBuiltinData d
  ```

  which is more verbose and sometimes still trickier for the typechecker.
* Using `@Type` is the cleanest and most idiomatic Plutus pattern for these untyped wrappers.

---

> Summary of Section 5
> These extensions are not “random GHC flags”; they form the **standard toolkit** that makes your Revenue Splitter:
>
> * safely separated between on-chain (`PlutusTx.Prelude`) and off-chain (`Prelude`) code,
> * serialisable to and from on-chain `Data`,
> * compilable to Plutus Core (`TemplateHaskell`),
> * explicit and unambiguous in its type-level plumbing (`ScopedTypeVariables` + `TypeApplications`),
> * ergonomic to work with (`OverloadedStrings`, `DataKinds`).

## 6. Imports (What each one is for)

Your Revenue Splitter code is split into **two main modules**:

1. `RevenueSplitterContract.hs` – **on-chain validator logic** only (pure Plutus, no IO).
2. `RevenueSplitter.hs` – **off-chain executable** that:
   - compiles the validator,
   - writes `revenue-splitter.plutus`,
   - prints the script hash and addresses.

Each module uses a different set of imports, depending on whether it’s on-chain or off-chain.

---

### 6.1 Module structure (`RevenueSplitterContract`, `RevenueSplitter`)

#### `RevenueSplitterContract.hs`

```haskell
module RevenueSplitterContract
  ( RevenueDatum(..)
  , RevenueRedeemer(..)
  , mkRevenueValidator
  , mkRevenueValidatorUntyped
  , validator
  ) where
````

* Exports:

  * **`RevenueDatum`** – datum describing eventId + recipients/shares.
  * **`RevenueRedeemer`** – redeemer type (`Distribute`).
  * **`mkRevenueValidator`** – *typed* validator:

    ```haskell
    RevenueDatum -> RevenueRedeemer -> ScriptContext -> Bool
    ```
  * **`mkRevenueValidatorUntyped`** – untyped wrapper:

    ```haskell
    BuiltinData -> BuiltinData -> BuiltinData -> ()
    ```
  * **`validator`** – compiled `Validator` ready for serialization.

* This module is **pure on-chain Plutus**:

  * No `IO`.
  * Uses `PlutusTx.Prelude`.
  * Compiled to Plutus Core via `PlutusTx.compile`.

#### `RevenueSplitter.hs`

```haskell
module Main where
```

* This is an **executable** whose job is to:

  * Serialize `RevenueSplitterContract.validator` to CBOR.
  * Wrap it in a **text envelope** (`.plutus` file).
  * Derive Bech32 script address.

* It **imports** the on-chain `validator` as a normal Haskell value:

  ```haskell
  import RevenueSplitterContract (validator)
  ```

* Then uses **Cardano API** + serialization libraries to bridge from:

  > *Plutus validator value* → *CLI-friendly `.plutus` file* + *script address*

---

### 6.2 `Prelude` and `qualified Prelude as P`

In `RevenueSplitterContract.hs`:

* You do **not** import base `Prelude` at all (because of `NoImplicitPrelude`).
* Instead you use:

  ```haskell
  import PlutusTx.Prelude hiding (Semigroup(..), unless)
  ```

  for all on-chain operations (`Bool`, `Integer`, `(==)`, `traceIfFalse`, `error`, `sum`, `all`, etc.).

In `RevenueSplitter.hs`:

```haskell
import Prelude (IO, FilePath, String, putStrLn, (<>))
import qualified Prelude as P
```

* This is the **off-chain** side:

  * `IO`, `FilePath`, `String` – needed for the `main` function and file writing.
  * `putStrLn` – for printing debug/info lines to the console.
  * `( <>)` – string concatenation when printing.

* `qualified Prelude as P` gives you:

  ```haskell
  P.show vh
  ```

  without polluting the global namespace.
  This makes it obvious when you’re using “normal Haskell” versus `PlutusTx.Prelude`.

**Separation rule of thumb:**

* **On-chain module** → only `PlutusTx.Prelude`.
* **Off-chain writer/executable** → `Prelude` + Cardano API + serialization.

---

### 6.3 Plutus core imports

#### In `RevenueSplitterContract.hs` (on-chain validator)

```haskell
import Plutus.V2.Ledger.Api
  ( Validator
  , ScriptContext(..)
  , TxInfo(..)
  , TxOut(..)
  , TxInInfo(..)
  , BuiltinData
  , PubKeyHash
  , Value
  , mkValidatorScript
  )
import Plutus.V2.Ledger.Contexts
  ( scriptContextTxInfo
  , findOwnInput
  , valuePaidTo
  )
import Plutus.V1.Ledger.Value
  ( valueOf
  , adaSymbol
  , adaToken
  )

import PlutusTx
import PlutusTx.Prelude hiding (Semigroup(..), unless)
```

**What each group is for:**

* **`Plutus.V2.Ledger.Api`**

  * Core types:

    * `Validator` – final compiled script type.
    * `ScriptContext`, `TxInfo`, `TxOut`, `TxInInfo` – transaction context types.
    * `BuiltinData` – raw on-chain data used by untyped validators.
    * `PubKeyHash`, `Value` – key and value types.
  * `mkValidatorScript` – wraps compiled Plutus Core into a `Validator` value.

* **`Plutus.V2.Ledger.Contexts`**

  * Helper functions to inspect the `ScriptContext`:

    * `scriptContextTxInfo` – extract `TxInfo`.
    * `findOwnInput` – get the script’s own input UTxO (the one being spent).
    * `valuePaidTo` – total `Value` paid to a given `PubKeyHash` in the outputs.

  These are used to implement:

  * `info :: ScriptContext -> TxInfo`
  * `ownInput`
  * `inputAda`
  * Recipient payout checks.

* **`Plutus.V1.Ledger.Value`**

  * `valueOf` – extract the amount of a given currency/token from a `Value`.
  * `adaSymbol`, `adaToken` – identify the ADA asset.
  * In `RevenueSplitter` you use these to:

    * read ADA from the input UTxO (`inputAda`),
    * read ADA paid to each recipient (`valuePaidTo + valueOf`).

* **`PlutusTx`**

  * Provides Template Haskell helpers and typeclass machinery:

    * `PlutusTx.unstableMakeIsData ''RevenueDatum`
    * `PlutusTx.unstableMakeIsData ''RevenueRedeemer`
    * `unsafeFromBuiltinData` in the untyped wrapper.
    * `PlutusTx.compile` used (indirectly) in the `validator` definition.

* **`PlutusTx.Prelude`**

  * Replaces base Prelude on-chain; provides:

    * `Bool`, `Integer`, `Maybe`, lists, `(==)`, `(&&)`, arithmetic,
    * `traceIfFalse`, `traceError`, `sum`, `all`, etc.

  All your validator logic uses these definitions.

#### In `RevenueSplitter.hs` (writer executable)

```haskell
import Plutus.V2.Ledger.Api
  ( Validator
  , Address(..)
  , Credential(..)
  )
import qualified Plutus.V2.Ledger.Api as PlutusV2
import PlutusTx.Prelude hiding (Semigroup(..), unless)
import qualified PlutusTx.Builtins as Builtins
```

* `Validator` – type of the compiled validator that you import from `RevenueSplitterContract`.

* `Address`, `Credential` – used to construct the **Plutus-level script address**:

  ```haskell
  Address (ScriptCredential (plutusValidatorHash validator)) Nothing
  ```

* `PlutusV2` alias – so you can write `PlutusV2.ValidatorHash` etc.

* `PlutusTx.Prelude` + `Builtins` – for `BuiltinByteString` and conversions:

  * `Builtins.toBuiltin`, `Builtins.fromBuiltin` used inside `plutusValidatorHash`.

---

### 6.4 Serialization stack

In `RevenueSplitter.hs`:

```haskell
import qualified Codec.Serialise       as Serialise
import qualified Data.ByteString.Lazy  as LBS
import qualified Data.ByteString.Short as SBS
```

These are used to convert the Haskell `Validator` into raw bytes that Cardano can understand:

1. **Serialise to CBOR**:

   ```haskell
   let bytes = Serialise.serialise val :: LBS.ByteString
   ```

2. **Convert lazy → strict → short**:

   ```haskell
   strict   = LBS.toStrict bytes        -- ByteString
   short    = SBS.toShort strict        -- ShortByteString
   ```

3. **Use those bytes in two places**:

   * `plutusValidatorHash v`:

     ```haskell
     strictBS = SBS.fromShort short
     builtin  = Builtins.toBuiltin strictBS
     PlutusV2.ValidatorHash builtin
     ```

     to get a **Plutus-level script hash**.

   * `writeValidator`:

     ```haskell
     plutusScript = CS.PlutusScriptSerialised short
     C.writeFileTextEnvelope path (Just description) plutusScript
     ```

     to get a **Cardano API script** that can be written to a `.plutus` file.

Without this stack, you couldn’t:

* derive the Plutus `ValidatorHash`,
* nor produce the Cardano-compatible text envelope.

---

### 6.5 Cardano API imports

In `RevenueSplitter.hs`:

```haskell
import qualified Cardano.Api          as C
import qualified Cardano.Api.Shelley  as CS
```

These imports handle the **bridge between Plutus and Cardano CLI**:

#### Text envelope `.plutus` file

```haskell
writeValidator :: FilePath -> Validator -> IO ()
writeValidator path val = do
  let serialised :: SBS.ShortByteString
      serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      description :: C.TextEnvelopeDescr
      description = "Revenue Splitter Plutus Validator"

  result <- C.writeFileTextEnvelope path (Just description) plutusScript
  ...
```

* `C.PlutusScript C.PlutusScriptV2` – Cardano’s notion of a Plutus V2 script.
* `CS.PlutusScriptSerialised` – wraps the raw bytes.
* `C.writeFileTextEnvelope` – writes a JSON-style `.plutus` file with:

  * `type: "PlutusScriptV2"`,
  * `description`,
  * `cborHex`.

This `.plutus` file is what you pass to:

```bash
cardano-cli transaction build \
  --tx-in-script-file revenue-splitter.plutus \
  ...
```

#### Script hash & Bech32 address

```haskell
toBech32ScriptAddress :: C.NetworkId -> Validator -> String
toBech32ScriptAddress network val =
  let serialised = ...
      plutusScript = CS.PlutusScriptSerialised serialised
      scriptHash :: C.ScriptHash
      scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)

      shelleyAddr :: C.AddressInEra C.BabbageEra
      shelleyAddr =
        C.makeShelleyAddressInEra
          network
          (C.PaymentCredentialByScript scriptHash)
          C.NoStakeAddress
  in T.unpack (C.serialiseAddress shelleyAddr)
```

* `C.NetworkId`, `C.Testnet (C.NetworkMagic 1)` – network you’re targeting.
* `C.hashScript` – compute **script hash** (policy ID for spending scripts).
* `C.PaymentCredentialByScript` + `C.makeShelleyAddressInEra` – build a Shelley-style **script address**.
* `C.serialiseAddress` – convert address to Bech32 text.

This gives your dApp users:

* A Bech32 **script address** to send the revenue pot UTxO to.
* A `.plutus` script file to use in CLI transactions.

---

> Summary of Section 6
>
> * `RevenueSplitterContract` is the **pure on-chain** module (no IO, only Plutus imports).
> * `RevenueSplitter` is the **off-chain writer** that serialises the validator and prints addresses.
> * Plutus imports handle **validator logic**, Cardano API + serialization imports handle **exporting** that validator into the real Cardano world as a `.plutus` file and Bech32 script address.

## 7. Revenue Splitter Validator Logic (`RevenueSplitterContract`)

The **Revenue Splitter** validator is intentionally very small and focused:

> *“Given some ADA locked at this script, and a list of `(recipient, share)` pairs in the datum, only allow spending if:*
> 
> 1. *The total ADA in the script input equals the sum of all shares.*  
> 2. *Each recipient is paid at least their share in the outputs.”*

There is only **one** redeemer constructor:

```haskell
data RevenueRedeemer = Distribute
````

So the validator only has a single “mode”: **distribute and close** (no continuing output).

---

### 7.1 Shared helpers (`info`, `ownInput`, `inputAda`)

To keep the validator readable, we factor out common pieces:

```haskell
{-# INLINABLE info #-}
info :: ScriptContext -> TxInfo
info = scriptContextTxInfo
```

* `info ctx` is just shorthand for `scriptContextTxInfo ctx`.
* It gives you the `TxInfo`, which contains:

  * inputs, outputs,
  * minting, fees,
  * withdrawals, certificates,
  * valid time range,
  * signatories, datums, etc.

---

```haskell
{-# INLINABLE ownInput #-}
ownInput :: ScriptContext -> TxOut
ownInput ctx =
  case findOwnInput ctx of
    Nothing -> traceError "own input not found"
    Just i  -> txInInfoResolved i
```

* `findOwnInput ctx` looks through the transaction inputs for the UTxO that is being spent **from this script address**.
* If it can’t find it:

  * The script fails with `traceError "own input not found"` (this should never happen in a well-formed spending tx).
* If it finds it:

  * `txInInfoResolved i` gives the actual `TxOut` (address, value, datum) being consumed.

This is the **revenue pot** UTxO: the ADA we are splitting.

---

```haskell
{-# INLINABLE inputAda #-}
inputAda :: ScriptContext -> Integer
inputAda ctx =
  let v :: Value
      v = txOutValue (ownInput ctx)
  in valueOf v adaSymbol adaToken
```

* `ownInput ctx` is the script’s input UTxO.
* `txOutValue` extracts its `Value`.
* `valueOf v adaSymbol adaToken` returns **how much ADA** (in lovelace) is locked there.

This is the `inputTotal` we compare against the sum of all shares.

> If someone tries to sneak in extra ADA under a different asset, it doesn’t matter for this validator: it only cares about ADA.

---

### 7.2 Core invariants: "sum of shares == input ADA"

The heart of the validator lives in:

```haskell
{-# INLINABLE mkRevenueValidator #-}
mkRevenueValidator :: RevenueDatum -> RevenueRedeemer -> ScriptContext -> Bool
mkRevenueValidator dat _ ctx =
       traceIfFalse "share sum != input ADA" sharesMatchInput
    && traceIfFalse "some recipient underpaid" recipientsPaid
  where
    ti :: TxInfo
    ti = info ctx

    requiredTotal :: Integer
    requiredTotal = sum (fmap snd (rdRecipients dat))

    inputTotal :: Integer
    inputTotal = inputAda ctx

    sharesMatchInput :: Bool
    sharesMatchInput = inputTotal == requiredTotal
```

Let’s unpack the invariant:

#### `RevenueDatum` and the share list

From earlier:

```haskell
data RevenueDatum = RevenueDatum
  { rdEventId    :: BuiltinByteString
  , rdRecipients :: [(PubKeyHash, Integer)]
  }
```

* `rdRecipients` is a **list of pairs**:

  ```haskell
  [(pkh1, share1), (pkh2, share2), ...]
  ```
* Each `share :: Integer` is a promised payout in **lovelace** (ADA).

#### Summing the shares

```haskell
requiredTotal = sum (fmap snd (rdRecipients dat))
```

* `fmap snd` extracts just the share amounts.
* `sum` adds them up to give the **total promised ADA**.

#### Comparing with the input ADA

```haskell
inputTotal = inputAda ctx
sharesMatchInput = inputTotal == requiredTotal
```

* `inputAda ctx` is how much ADA is locked at the script **in the consumed UTxO**.
* The validator enforces:

> **Invariant:** `sum of all shares == ADA in script input`.

If this fails:

```haskell
traceIfFalse "share sum != input ADA" sharesMatchInput
```

the transaction is rejected with that failure message.

This guarantees:

* No **overpayment** or **under-allocation** vs the actual pot,
* Whoever constructs the datum **must** keep it in sync with the locked ADA amount.

---

### 7.3 Recipient payment checks (`valuePaidTo` each recipient)

The second part of the validator enforces that **each recipient actually receives their share**:

```haskell
    recipientsPaid :: Bool
    recipientsPaid =
      all recipientsOk (rdRecipients dat)

    recipientsOk :: (PubKeyHash, Integer) -> Bool
    recipientsOk (pkh, share) =
      let vPaid = valuePaidTo ti pkh
          ada   = valueOf vPaid adaSymbol adaToken
      in ada >= share
```

#### `valuePaidTo ti pkh`

* Built-in helper from `Plutus.V2.Ledger.Contexts`:

  * It scans **all outputs** in the transaction.
  * Sums up the `Value` paid to the given `PubKeyHash`.

So:

```haskell
vPaid = valuePaidTo ti pkh
ada   = valueOf vPaid adaSymbol adaToken
```

* `vPaid` is the combined `Value` across **all** outputs to that recipient.
* `valueOf vPaid adaSymbol adaToken` extracts their total ADA (in lovelace).

#### Underpayment check

For each `(pkh, share)`:

```haskell
ada >= share
```

* Means:

  > “The total ADA paid to this recipient in this transaction must be at least their share.”

* Note: `>=`, not `==`:

  * The dApp could decide to tip someone more; the contract doesn’t forbid that.
  * It only insists on **minimum** guarantees.

Finally:

```haskell
recipientsPaid =
  all recipientsOk (rdRecipients dat)
```

* If **any** recipient is underpaid, `recipientsPaid` is `False` and the whole validator fails with:

  ```haskell
  traceIfFalse "some recipient underpaid" recipientsPaid
  ```

> Combined with `sharesMatchInput`, this enforces:
>
> 1. The total input pot equals the promised shares.
> 2. Every recipient gets **at least** their promised ADA.

---

### 7.4 Untyped wrapper and compiled validator

On-chain validators are ultimately exposed as **untyped** functions taking `BuiltinData`:

```haskell
BuiltinData -> BuiltinData -> BuiltinData -> ()
```

To bridge from our nice typed function to that shape, we use an **untyped wrapper**:

```haskell
{-# INLINABLE mkRevenueValidatorUntyped #-}
mkRevenueValidatorUntyped :: BuiltinData -> BuiltinData -> BuiltinData -> ()
mkRevenueValidatorUntyped d r c =
  let dat = unsafeFromBuiltinData @RevenueDatum    d
      red = unsafeFromBuiltinData @RevenueRedeemer r
      ctx = unsafeFromBuiltinData @ScriptContext   c
  in if mkRevenueValidator dat red ctx
        then ()
        else error ()
```

Step-by-step:

1. **Decode** `BuiltinData` to typed values using `unsafeFromBuiltinData` and `TypeApplications`:

   ```haskell
   dat = unsafeFromBuiltinData @RevenueDatum    d
   red = unsafeFromBuiltinData @RevenueRedeemer r
   ctx = unsafeFromBuiltinData @ScriptContext   c
   ```

   * This assumes the datum, redeemer, and context are encoded correctly.
   * If not, decoding will fail and the script will error.

2. **Call the typed validator**:

   ```haskell
   mkRevenueValidator dat red ctx
   ```

   * Returns `True` if the transaction respects the revenue splitting rules.
   * Returns `False` (or traces) if not.

3. **Map Bool to unit/error**:

   ```haskell
   if mkRevenueValidator dat red ctx
      then ()
      else error ()
   ```

   * In Plutus, a validator of type `BuiltinData -> ... -> ()` **must not fail** (returning `()` means success).
   * We signal failure by calling `error ()`.

Finally, we compile it to a `Validator`:

```haskell
validator :: Validator
validator =
  mkValidatorScript $$(PlutusTx.compile [|| mkRevenueValidatorUntyped ||])
```

* `PlutusTx.compile [|| mkRevenueValidatorUntyped ||]`:

  * Uses Template Haskell to turn `mkRevenueValidatorUntyped` into Plutus Core.
* `mkValidatorScript`:

  * Wraps that Plutus Core program into a `Validator` value.

This `validator` is what you import in `RevenueSplitter.hs` and then:

* Serialize to CBOR,
* Wrap in a text envelope `.plutus` file,
* Derive the script hash & Bech32 address.

> In short, Section 7 is where the **actual guarantees** of the Revenue Splitter live:
>
> * correct total pot,
> * each recipient gets their due,
> * compiled into a proper Plutus V2 `Validator` ready for use on Cardano.

## 8. Producing `revenue-splitter.plutus`

The **on-chain logic** for the Revenue Splitter lives in:

- `RevenueSplitterContract.hs` (validator definition)

But to actually **use** it with `cardano-cli` and wallets, we need to:

1. Compile it to Plutus Core,
2. Serialise it to CBOR,
3. Wrap it in a **text envelope** `.plutus` file,
4. Compute the **script hash** and **Bech32 script address**.

All of that is done in the small executable module:

- `RevenueSplitter.hs`

---

### 8.1 `revenue-splitter-exe` (validator writer)

In `RevenueSplitter.hs`, the main IO helper is:

```haskell
writeValidator :: FilePath -> Validator -> IO ()
writeValidator path val = do
  let serialised :: SBS.ShortByteString
      serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      description :: C.TextEnvelopeDescr
      description = "Revenue Splitter Plutus Validator"

  result <- C.writeFileTextEnvelope path (Just description) plutusScript
  case result of
    Left err  -> putStrLn $ "Error writing validator: " <> C.displayError err
    Right ()  -> putStrLn $ "Validator written to: " <> path
````

Step-by-step:

1. **Serialise the validator to CBOR**

   ```haskell
   serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val
   ```

   * `Serialise.serialise val` turns the `Validator` into lazy CBOR bytes.
   * `LBS.toStrict` converts lazy → strict `ByteString`.
   * `SBS.toShort` turns it into a compact `ShortByteString` required by `cardano-api`.

2. **Wrap as a `PlutusScriptV2`**

   ```haskell
   plutusScript = CS.PlutusScriptSerialised serialised
   ```

   * This tells `cardano-api` “these bytes are a Plutus V2 script”.

3. **Choose a text envelope description**

   ```haskell
   description = "Revenue Splitter Plutus Validator"
   ```

   * Human-readable label.
   * Appears inside the `.plutus` file as `"description": "Revenue Splitter Plutus Validator"`.

4. **Write the text envelope to disk**

   ```haskell
   result <- C.writeFileTextEnvelope path (Just description) plutusScript
   ```

   * `path` is typically `"revenue-splitter.plutus"`.
   * On success, you get a file containing:

     * `type: "PlutusScriptV2"`
     * `description: "Revenue Splitter Plutus Validator"`
     * `cborHex: "<hex-encoded script bytes>"`.

5. **Log success or failure**

   ```haskell
   case result of
     Left err  -> putStrLn $ "Error writing validator: " <> C.displayError err
     Right ()  -> putStrLn $ "Validator written to: " <> path
   ```

   * Failures show a descriptive error (e.g. IO issues).
   * Success prints the file path.

---

The `main` function wires it all together:

```haskell
main :: IO ()
main = do
  let network = C.Testnet (C.NetworkMagic 1)

  writeValidator "revenue-splitter.plutus" validator

  let vh      = plutusValidatorHash validator
      onchain = plutusScriptAddress
      bech32  = toBech32ScriptAddress network validator

  putStrLn "\n--- Revenue Splitter Validator Info ---"
  putStrLn $ "Validator Hash (Plutus): " <> P.show vh
  putStrLn $ "Plutus Script Address:    " <> P.show onchain
  putStrLn $ "Bech32 Script Address:    " <> bech32
  putStrLn "----------------------------------------"
  putStrLn "Revenue splitter validator generated successfully."
```

* Uses the `validator :: Validator` imported from `RevenueSplitterContract`.
* Writes `revenue-splitter.plutus` in the project root.
* Prints hashes and addresses for quick reference.

To run it from the project root:

```bash
cabal run revenue-splitter-exe
```

You should see:

* `revenue-splitter.plutus` created,
* Script hash + addresses printed to stdout.

---

### 8.2 Script hash and Bech32 script address output

Besides writing the `.plutus` file, `RevenueSplitter.hs` also computes:

1. A **Plutus-style validator hash**,
2. A **Plutus-style script address**,
3. A full **Bech32 script address** for the chosen network.

#### 8.2.1 Plutus-style validator hash

```haskell
plutusValidatorHash :: PlutusV2.Validator -> PlutusV2.ValidatorHash
plutusValidatorHash v =
  let bytes    = Serialise.serialise v
      strict   = LBS.toStrict bytes
      short    = SBS.toShort strict
      builtin  = Builtins.toBuiltin (SBS.fromShort short)
  in PlutusV2.ValidatorHash builtin
```

* This:

  1. Serialises the validator to CBOR,
  2. Converts to `BuiltinByteString`,
  3. Wraps it in `ValidatorHash`.

* This hash is used to construct a **Plutus address**:

  ```haskell
  plutusScriptAddress :: PlutusV2.Address
  plutusScriptAddress =
    Address (ScriptCredential (plutusValidatorHash validator)) Nothing
  ```

* This is the pure Plutus ledger representation (not Bech32, not network-tagged).

#### 8.2.2 Bech32 script address (for CLI & wallets)


```haskell
toBech32ScriptAddress :: C.NetworkId -> Validator -> String
toBech32ScriptAddress network val =
  let serialised :: SBS.ShortByteString
      serialised = SBS.toShort . LBS.toStrict $ Serialise.serialise val

      plutusScript :: C.PlutusScript C.PlutusScriptV2
      plutusScript = CS.PlutusScriptSerialised serialised

      scriptHash :: C.ScriptHash
      scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)

      shelleyAddr :: C.AddressInEra C.BabbageEra
      shelleyAddr =
        C.makeShelleyAddressInEra
          network
          (C.PaymentCredentialByScript scriptHash)
          C.NoStakeAddress
  in T.unpack (C.serialiseAddress shelleyAddr)
```

Step-by-step:

1. **Serialise validator** just like for the `.plutus` file.

2. **Wrap as `PlutusScriptV2`** so Cardano API understands the script type.

3. **Hash the script**:

   ```haskell
   scriptHash = C.hashScript (C.PlutusScript C.PlutusScriptV2 plutusScript)
   ```

   * Gives a `ScriptHash` suitable for addresses.

4. **Build a Shelley-era script address**:

   ```haskell
   shelleyAddr =
     C.makeShelleyAddressInEra
       network
       (C.PaymentCredentialByScript scriptHash)
       C.NoStakeAddress
   ```

   * `network` is `Testnet (NetworkMagic 1)` in your current code.
   * `PaymentCredentialByScript scriptHash` says: this is a **script address**, not a pubkey.
   * `NoStakeAddress` means no staking credential attached.

5. **Serialise to Bech32**:

   ```haskell
   T.unpack (C.serialiseAddress shelleyAddr)
   ```

   * Produces a Bech32 **string** you can use in `cardano-cli`, wallets, and tooling.
   * For testnet, it will start with something like `addr_test1...`.

---

When you run `revenue-splitter-exe`, you see:

```text
--- Revenue Splitter Validator Info ---
Validator Hash (Plutus): <...>
Plutus Script Address:    <...>
Bech32 Script Address:    addr_test1...
----------------------------------------
Revenue splitter validator generated successfully.
```

These values are used as follows:

* **`.plutus` file** – passed to `cardano-cli` with `--tx-in-script-file revenue-splitter.plutus` when spending from the script.
* **Bech32 script address** – used to **lock ADA** into the Revenue Splitter contract (e.g., from the organiser’s wallet).
* **Validator hash / Plutus address** – useful for on-chain reasoning, emulator tests, or inspecting the ledger state at a lower level.

> Summary: `revenue-splitter-exe` turns your `RevenueSplitterContract` validator into **real-world artifacts**:
>
> * a deployable `.plutus` file
> * a script address where you lock revenue
> * and clear, human-readable console output for integration and debugging.

## 9. Testing the Contract

You wired the Revenue Splitter tests into `wspace-tests` via:

- `tests/RevenueSplitterSpec.hs`
- `test-suite wspace-tests` in `wspace.cabal`

So whenever you run:

```bash
cabal test wspace-tests
```

you’re not just compiling the validator, you’re also exercising a small **spec suite** that checks the core invariants of `mkRevenueValidator`.

---

### 9.1 What `RevenueSplitterSpec` tests

The test group usually looks like something along the lines of:

```haskell
testGroup "RevenueSplitter (on-chain)"
  [ testCase "valid split passes when totals and outputs match" ...
  , testCase "fails when sum of shares does not match input ADA" ...
  , testCase "fails when one recipient is underpaid" ...
  ]
```

Conceptually, you’re testing three key behaviours:

---

#### 9.1.1 Valid split passes when totals and outputs match

**Scenario:**

* Script input UTxO at `RevenueSplitter` holds **some ADA** (e.g. 10 ADA).

* Datum:

  ```haskell
  RevenueDatum
    { rdEventId    = "EVENT-001"
    , rdRecipients =
        [ (pkhA, 3_000_000)  -- 3 ADA
        , (pkhB, 7_000_000)  -- 7 ADA
        ]
    }
  ```

* Redeemer: `Distribute`.

* Transaction:

  * Spends that script UTxO.
  * Pays **exactly** 3 ADA to `pkhA` and 7 ADA to `pkhB`.
  * No extra constraints like who signs – the logic only cares about **amounts** and **targets**.

**Test asserts:**

```haskell
mkRevenueValidator dat Distribute ctx == True
```

This confirms that when:

* `sum shares == inputAda`, and
* each recipient is paid **at least** their share,

the validator succeeds.

---

#### 9.1.2 Fails when sum of shares does **not** match input ADA

**Scenario:**

* Script input UTxO holds, say, **10 ADA**.

* Datum expects:

  ```haskell
  rdRecipients =
    [ (pkhA, 3_000_000)
    , (pkhB, 8_000_000)
    ]
  -- total = 11 ADA
  ```

* Or the other way around: input has 11 ADA but shares sum to 10 ADA.

**Validator invariant:**

```haskell
requiredTotal :: Integer
requiredTotal = sum (fmap snd (rdRecipients dat))

inputTotal :: Integer
inputTotal = inputAda ctx

sharesMatchInput :: Bool
sharesMatchInput = inputTotal == requiredTotal
```

* If `sharesMatchInput == False`, then:

  ```haskell
  traceIfFalse "share sum != input ADA" sharesMatchInput
  ```

  fails and the transaction is invalid.

**Test asserts:**

```haskell
mkRevenueValidator dat Distribute ctx == False
```

This ensures you **cannot** misconfigure the datum (or accidentally lock the wrong ADA amount) and still pass validation. The contract forces a **clean equality** between:

* what’s locked in the script, and
* what you’ve promised to split in the datum.

---

#### 9.1.3 Fails when one recipient is underpaid

**Scenario:**

* Script input UTxO: 10 ADA.

* Datum:

  ```haskell
  rdRecipients =
    [ (pkhA, 3_000_000)
    , (pkhB, 7_000_000)
    ]
  ```

* Transaction:

  * Pays **3 ADA** to `pkhA` (correct).
  * Pays only **6 ADA** (instead of 7) to `pkhB`.
  * Still consumes the script input.

Even though:

* `sharesMatchInput` is **true** (3 + 7 = 10, inputAda = 10),

the per-recipient check must fail:

```haskell
recipientsPaid :: Bool
recipientsPaid =
  all recipientsOk (rdRecipients dat)

recipientsOk :: (PubKeyHash, Integer) -> Bool
recipientsOk (pkh, share) =
  let vPaid = valuePaidTo ti pkh
      ada   = valueOf vPaid adaSymbol adaToken
  in ada >= share
```

* For `pkhB`, `ada == 6_000_000` but `share == 7_000_000` ⇒ `recipientsOk` is `False`.
* Therefore:

  ```haskell
  traceIfFalse "some recipient underpaid" recipientsPaid
  ```

  fails and the transaction is rejected.

**Test asserts:**

```haskell
mkRevenueValidator dat Distribute ctx == False
```

This shows the script does **not** just check totals – it enforces **fairness per recipient**.

---

### 9.2 Running the tests

From the project root (inside your Nix dev shell if you’re using one):

```bash
# enter dev shell if needed
nix develop       # optional, depending on your setup

# run all wspace tests (including RevenueSplitterSpec)
cabal test wspace-tests
```

You’ll see a section in the output like:

```text
RevenueSplitter (on-chain)
  valid split passes when totals and outputs match:          OK
  fails when sum of shares does not match input ADA:         OK
  fails when one recipient is underpaid:                     OK
```

This confirms:

1. Your **happy path** works.
2. Bad configurations (wrong sum) are **rejected**.
3. Attempts to underpay any recipient are **rejected**.

> Together with the Sports Tickets tests, this gives you a solid safety net:
>
> * Tickets enforce fair & capped resale + honest gate usage
> * RevenueSplitter enforces exact distribution of the event pot to all stakeholders

## 10. Glossary of Terms

### 10.1 Revenue pot / pool

The **revenue pot** (or **revenue pool**) is the **total ADA** locked at the RevenueSplitter script address for a given event.

In this contract:

* It is the **value in the script input UTxO** being spent:

  * `inputAda ctx` reads “how much ADA is in the script’s own input”.
* This pot is what gets split among recipients according to `rdRecipients`.

Think of it as:

> “All the money collected for this event that now needs to be shared.”

---

### 10.2 Share / allocation (in lovelace)

A **share** (or **allocation**) is a **concrete ADA amount in lovelace** assigned to a recipient.

In the datum:

```haskell
rdRecipients :: [(PubKeyHash, Integer)]
```

Each pair `(pkh, share)` means:

* `pkh` must receive **at least** `share` lovelace in the distribution transaction.

The validator enforces two things:

1. Sum of all shares == total input ADA.
2. Each recipient gets **at least** their share.

---

### 10.3 Recipient

A **recipient** is a **Cardano wallet** (identified by `PubKeyHash`) that should receive a portion of the revenue pot.

In `RevenueDatum`:

* Each entry in `rdRecipients` is a **recipient** and their share:

  ```haskell
  (PubKeyHash, Integer)
  ```

Examples of recipients:

* Event organiser / promoter.
* Venue owner.
* Artist / performers.
* Partners or sponsors.

---

### 10.4 Event ID (`rdEventId`)

`rdEventId :: BuiltinByteString` is a **label** linking this revenue UTxO to a specific event.

* Used mainly for **off-chain bookkeeping** and indexing.
* On-chain, the validator does **not** enforce uniqueness – it just carries this field through as metadata.

Examples:

* `"CONCERT-2025-05-01-JHB"`
* `"MATCH-LEAGUE-CUP-FINAL-01"`

---

### 10.5 Datum (`RevenueDatum`)

The **datum** is the on-chain data attached to the script UTxO that tells the validator **how to split the funds**.

```haskell
data RevenueDatum = RevenueDatum
  { rdEventId    :: BuiltinByteString
  , rdRecipients :: [(PubKeyHash, Integer)]
  }
```

It answers:

* **Which event** is this pot for? → `rdEventId`
* **Who should be paid, and how much?** → `rdRecipients`

Every script UTxO at the RevenueSplitter should carry exactly one `RevenueDatum` that fully describes the desired split.

---

### 10.6 Redeemer (`RevenueRedeemer`)

The **redeemer** is the value provided **when spending** the script UTxO. It chooses which path the validator follows.

```haskell
data RevenueRedeemer = Distribute
```

In this contract:

* There is **only one action**: `Distribute`.
* That means: “We are now executing the revenue split as defined by the datum.”

Later, you could extend this type with more actions (e.g. `Cancel`, `UpdateShares`), but in this tutorial it’s intentionally simple.

---

### 10.7 Validator

The **validator** is the Plutus function that decides if a transaction spending the revenue pot is valid:

```haskell
mkRevenueValidator
  :: RevenueDatum
  -> RevenueRedeemer
  -> ScriptContext
  -> Bool
```

It enforces:

1. **Sum invariant** – total shares in `rdRecipients` must equal the ADA in the script input.
2. **Payment invariant** – each `(pkh, share)` must receive at least `share` lovelace in the outputs.

If any check fails → transaction is invalid → the pot cannot be spent that way.

---

### 10.8 Script UTxO

A **script UTxO** is a UTxO locked by a **script address** (not a normal pubkey address).

For the RevenueSplitter:

* The script UTxO:

  * lives at the RevenueSplitter **script address**,
  * holds the revenue pot ADA,
  * carries a `RevenueDatum` with the share configuration.

It can only be spent by a transaction that satisfies `mkRevenueValidator`.

---

### 10.9 Script address

The **script address** is derived from the **hash of the validator**.

* Built using `plutusValidatorHash` + `Address (ScriptCredential ...)`.
* Represented as:

  * a Plutus address (for on-chain types),
  * a Bech32 address string (for wallet/CLI use).

You:

* Send the **revenue pot** to this address.
* Later, build a transaction that **spends from this address** with redeemer `Distribute`.

---

### 10.10 Text envelope (`.plutus` file)

A `.plutus` file is a **text envelope** wrapping the compiled Plutus script for use with `cardano-cli`.

Produced by `revenue-splitter-exe` using:

```haskell
C.writeFileTextEnvelope
  "revenue-splitter.plutus"
  (Just "Revenue Splitter Plutus Validator")
  plutusScript
```

It contains:

* `type`: `"PlutusScriptV2"`,
* `description`: the human-readable label,
* `cborHex`: hex-encoded CBOR of the validator.

You pass this file as `--tx-in-script-file revenue-splitter.plutus` when building distribution transactions.

---

### 10.11 How these concepts connect (revenue distribution diagram)

```text
1. Setup (off-chain configuration)
----------------------------------

  Off-chain / admin / dApp:

    - Decide event ID:
        rdEventId = "CONCERT-2025-05-01-JHB"

    - Decide recipients and shares:
        rdRecipients =
          [ (pkhOrganiser, 5_000_000)
          , (pkhArtist,   3_000_000)
          , (pkhVenue,    2_000_000)
          ]
        -- Sum = 10_000_000 lovelace

    - Build RevenueDatum:
        RevenueDatum { rdEventId, rdRecipients }


2. Lock revenue pot at script
-----------------------------

  Tx: Lock revenue

    Inputs:
      - Event revenue UTxOs from sale logic (normal addresses)

    Outputs:
      - 10_000_000 lovelace to:
          Address = RevenueSplitter script address
          Datum   = RevenueDatum { rdEventId, rdRecipients }

  Result on-chain:

    +-------------------------------------------------------+
    | Script UTxO at RevenueSplitter address               |
    |   Value: 10_000_000 lovelace (ADA)                   |
    |   Datum: { rdEventId, rdRecipients }                 |
    +-------------------------------------------------------+


3. Distribution transaction (on-chain Distribute)
-------------------------------------------------

  Tx: Distribute revenue

    Inputs:
      - Script UTxO (revenue pot) with RevenueDatum

    Redeemer:
      - Distribute

    Outputs:
      - pkhOrganiser: 5_000_000 lovelace
      - pkhArtist:    3_000_000 lovelace
      - pkhVenue:     2_000_000 lovelace
      - (optionally) change / fees from other inputs, etc.

  Validator (mkRevenueValidator) checks:
    - sum shares in rdRecipients == inputAda (10_000_000)
    - valuePaidTo pkhOrganiser >= 5_000_000
    - valuePaidTo pkhArtist    >= 3_000_000
    - valuePaidTo pkhVenue     >= 2_000_000

  If all pass:
    - Script UTxO is consumed
    - Each recipient has received their share
    - Revenue for that event is cleanly settled on-chain
```
