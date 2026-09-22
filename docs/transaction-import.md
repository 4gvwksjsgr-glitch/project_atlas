# Transaction import

Import of cash transactions from a CSV or XLSX file into the **active company**. Available to roles that satisfy `canManageTransactions`; the screen redirects to `/transactions` for everyone else.

Entry point: `/transactions/import`, reachable from the *Importa movimenti* button on the transactions list.

## Limits

| Limit | Value | Enforced by |
| --- | --- | --- |
| File size | 2 MB | `TabularImportSource.maxFileBytes`, checked before parsing |
| Data rows | 500 | `TabularImportSource.maxDataRows`, and again by the RPC |
| Excel sheets | 20 | `TabularImportSource.maxSheets` |
| Sheets per import | 1 | the user picks one sheet; there is no multi-sheet merge |

A file over 2 MB is rejected before it is decoded, so an oversized workbook is never expanded in memory.

## Supported columns

Only these fields are imported: **date**, **description**, **amount**, **reference**, **notes**. Everything else in the file is ignored.

The direction of the movement is never asked for directly. It is derived from the amount:

- a single signed column: a negative value is an expense, a positive value is income;
- a debit/credit pair: a value in the debit column is an expense, a value in the credit column is income.

A column mapped as debit or credit may not carry a sign, and a row may not fill both — either case would make the direction ambiguous, so the row is rejected. Debit and credit cells valued at zero count as empty, which is how bank statements usually export them.

## Nothing ambiguous is resolved silently

Two classes of value can legitimately be read in more than one way, and the wizard refuses to guess:

- **Decimal separator.** `1.234` is either one thousand two hundred thirty-four or one and a fraction. Ambiguous rows are flagged and the whole plan is blocked until the user picks a separator.
- **Day/month order.** `03/04/2026` is either 3 April or 4 March. Same treatment.

Both choices are re-applied to the entire file, not per row. Two-digit years are not supported at all: no century rule is invented.

Excel formula cells are rejected rather than evaluated.

## Duplicate handling

Two different fingerprints, both SHA-256 over a canonical form (see `TransactionImportFingerprint`):

- **Row fingerprint** — `date | kind | amount | normalized description | reference?`. Used to *detect* repeats *within the file*: the first occurrence is selected by default, later ones are flagged as `duplicateInFile` and excluded unless the user explicitly includes them. Also sent to the server as non-unique provenance metadata (`row_fingerprint`).
- **Existing match key** — same shape without the reference. Compared against the transactions already in the company. A match makes the row a **possible duplicate**: it is flagged and excluded by default, and the user can include it row by row. Nothing is deleted or merged automatically.

Description comparison is case-insensitive and collapses whitespace, so `Incasso  Cliente` and `incasso cliente` are the same movement.

**Identity within a batch is `source_row`, not fingerprint.** The database does **not** enforce uniqueness on operational fields or on `row_fingerprint` within a batch, so two legitimate bank lines with identical content can both be imported when the user includes them. Failed/rolled-back imports leave no batch row, so a file SHA does not permanently block a retry after failure.

The existing transactions used for this comparison are read through `transactionImportExistingTransactionsProvider`, which deliberately ignores the filters active on the transactions list — otherwise a filtered list would hide duplicates.

## Server side

`import_transactions` is a `SECURITY DEFINER` RPC that writes the batch, the transactions, and the per-row provenance in one transaction. The client sends `company_id` only as an RPC parameter: individual rows never carry `company_id` or `id`.

The file's SHA-256 is sent as `source_file_sha256`. Re-importing the same bytes into the same company fails with `ATLAS_IMPORT_FILE_ALREADY_IMPORTED`, and the user is told explicitly that nothing was duplicated.

The response carries `batch_id`, `imported_count`, `skipped_invalid_count`, `skipped_duplicate_count`, and `transaction_ids`.

Import error codes are translated by `TransactionErrorMapper` into Italian copy that never contains SQL, payload fragments, or transaction data. The granular `ATLAS_IMPORT_<field>_INVALID` codes all map to "payload invalid" rather than a retry prompt, because retrying the same file cannot help.

## In-memory file handling

The picked bytes live in controller state only as long as the wizard needs them, and the reference is dropped on success, reset, and dispose. That makes them eligible for garbage collection — it is **not** a secure wipe from RAM.

A late RPC response never updates a superseded or disposed session: the controller compares a generation counter and the company id before applying any result. The in-flight RPC itself is not cancelled.

## Deferred

Not part of this step, and not partially implemented anywhere:

- **Bank API connections.** No direct feed from banks or aggregators; import is file-based only.
- **Fiscal treatment.** No VAT, withholding, or any tax computation on imported rows.
- **Reverse import.** No undo of a completed batch. `batch_id` and the provenance rows are recorded so that a future step can build it, but there is no UI or RPC to roll a batch back.
