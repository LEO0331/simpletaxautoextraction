# Document coverage and local imports

The document inventory records evidence by financial year, account, ticker/property and document family. Add expected evidence, including missing documents. A required missing, available or insufficient item blocks finalisation until reviewed or explicitly marked not applicable with a reason. Each known transaction and fund statement requires its own linked evidence; one account-level document does not prove the completeness of a year's history.

PDFs remain local. Only reviewed references, SHA-256 fingerprints, selected page ranges and linked record IDs are persisted. Edits retain immutable revisions and advance the workspace generation, invalidating older workpapers. Multiple documents may share a year/account/ticker/family. Opening and closing holdings observations use exact units and a civil observation date; replayed holdings mismatches require review rather than invented acquisitions.

## Broker CSV

Open **Review broker CSV**. Supported files have explicit columns:

```csv
tradeDate,direction,ticker,account,confirmationNumber,units,consideration,brokerage,totalCost,currency,broker
2024-07-01,BUY,TEST,SYNTHETIC,EXAMPLE-1,2,20.00,1.00,21.00,AUD,CommSec
```

`tradeDate` accepts YYYY-MM-DD or DD/MM/YYYY. `direction` is BUY/SELL (BOUGHT/SOLD also accepted). `totalCost` is gross plus brokerage for acquisitions and net settlement after brokerage for sales. Existing canonical aliases are accepted when unambiguous. Unknown column layouts, duplicate aliases, missing values and inconsistent settlement amounts require correction or manual review. The parser never assumes zero brokerage. Non-AUD rows are rejected; missing currency requires an explicit AUD confirmation.

All rows open the existing transaction review screen before saving. Broker `CommSec` uses the same account/confirmation identity namespace as CommSec PDF confirmations; matching trades are not added twice. Files are limited to 5 MB and 1,000 transactions per import. A multi-row file fingerprint is provenance, not the transaction identity.

## DRP advice

Choose one or two pages of a local PDF in **DRP advice review**. Betashares/Link distribution advice uses conservative, unique label extraction. Payment and record dates accept explicit ISO dates or full English month dates. Ambiguous or unsupported fields remain blank. In particular, an **amount available** is not automatically treated as an amount reinvested because residual cash may differ.

Review exact allotted units, reinvestment consideration, payment/acquisition date and residual cash, then select an existing reviewed BUY. Units, consideration and acquisition date must match. Linking advice stores evidence and creates no new acquisition parcel. Add the existing BUY reference to the annual fund statement DRP list for cash/DRP reconciliation. Multiple advice records can be linked independently.

The combined confidential sample informed label recognition on pages 111–112. No original PDF pages, personal values or extracted text are included in repository fixtures; parser tests use invented examples.
