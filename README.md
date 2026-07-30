# scripts

This repository contains a collection of PowerShell scripts for use in an
on-premises Exchange Server / Active Directory environment. Each script is
self-contained, lives in its own folder, and comes with a dedicated
`README.md` covering requirements, parameters, and usage examples.

## Scripts

| Script | Description |
|---|---|
| [ExchangeReport](ExchangeReport/README.md) | Collects health and capacity information about an on-premises Exchange Server environment (mailbox counts, database status, replication, disk space, message queues, certificates, critical services) and emails a summarized HTML report, with an optional copy saved to disk. Fully configurable via an external JSON file and can register itself as a Scheduled Task. |
| [New-CertificateRequest](CreateCertificateRequest/README.md) | Generates Windows certificate signing requests (CSR) via `certreq.exe`, for a single certificate or in batch from a JSON file. Also supports importing an issued certificate into the local store, exporting it as PFX, and generating request JSON from existing certificates for renewals. |
| [LogCleanup](LogCleaner/README.md) | Cleans up outdated log files, including IIS logs and Exchange IMAP4/POP3 logs, plus any custom log directories. Supports configurable retention periods, `-WhatIf` dry runs, and self-registration as a Scheduled Task. |

See each script's own README for full details.
