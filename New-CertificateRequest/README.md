# New-CertificateRequest.ps1

A PowerShell script to generate Windows certificate signing requests (CSR / `.req`) via
`certreq.exe`, with additional support for importing issued certificates and exporting
them as PFX.

## Features

- Generates a `certreq`-compatible `.inf` file and calls `certreq -new` to produce a `.req` CSR
- Single certificate (via `-CN` / `-SAN`) or batch mode (via `-ImportFile`, JSON, one or many entries)
- CN is always automatically added to the SAN list (deduplicated, no need to repeat it)
- Automatic DNS vs. IP classification for SAN entries
- Supports RSA (configurable key length) and ECDSA (P256 / P384 / P521)
- CNG (Key Storage Provider) and Legacy CSP support
- Import of an issued certificate into the local certificate store (`certreq -accept`)
- PFX export of a certificate already in the store, with interactive password prompt
  (password is never passed as plain text or stored)
- Combined "import and export" mode
- Generates request JSON files from existing certificates - a `.cer` file, a
  certificate in the local store (by thumbprint), or the certificate presented by a
  remote server over TLS - useful for renewals with an identical subject/SAN
- SAN extraction (both on read and on write) is locale-independent: it classifies
  entries by their value's shape (IP vs. DNS name) rather than by parsing
  OS-language-dependent labels
- `-WhatIf` support for all file-writing and `certreq`/store-modifying operations
- Result objects for each run are returned on the pipeline (e.g. capture with
  `$r = .\New-CertificateRequest.ps1 ...`), and full, untruncated error messages for
  any failed entries are printed separately below the summary table

## Requirements

- Windows with `certreq.exe` (built-in)
- PowerShell 5.1 or later
- Local admin rights are **not** required by the script itself, but the target
  certificate store operations (`-CompleteRequest`, `-ExportPfx`, etc.) require access
  to the relevant certificate store (LocalMachine vs. CurrentUser, see `-MachineContext`)

## Modes

The script has five mutually exclusive modes. If none of the mode switches below is
used, it defaults to creating a new request.

| Mode | Switch | Purpose |
|---|---|---|
| New request (default) | `-CN` / `-SAN` or `-ImportFile` | Create one or more CSRs |
| Generate example JSON | `-GenerateExampleJSON` | Write an example import file and exit |
| Complete request | `-CompleteRequest <file.cer>` | Import an issued certificate into the store |
| Complete and export | `-CompleteAndExport <file.cer>` | Import, then immediately export as PFX |
| Export PFX | `-ExportPfx -Thumbprint <thumbprint>` | Export an existing certificate as PFX |
| Export request JSON | `-ExportRequestJson -Source...` | Generate request JSON file(s) from existing certificate data |

## Usage

### Create a single request

```powershell
.\New-CertificateRequest.ps1 -CN "server01.contoso.local" -SAN "server01","10.0.0.5" -Exportable:$false
```

### Create requests from a JSON file (single or batch)

```powershell
.\New-CertificateRequest.ps1 -ImportFile ".\requests.json" -Exportable:$false
```

Generate an example file to see the expected JSON structure:

```powershell
.\New-CertificateRequest.ps1 -GenerateExampleJSON
```

Example structure (`example-request.json`):

```json
[
  {
    "CN": "server01.contoso.local",
    "SAN": ["server01", "10.0.0.5"],
    "Organization": "Contoso GmbH",
    "OrganizationalUnit": "IT",
    "Locality": "Hamburg",
    "State": "Hamburg",
    "Country": "DE",
    "FriendlyName": "server01 Webcert 2026"
  },
  {
    "CN": "server02.contoso.local",
    "SAN": ["server02.contoso.local"]
  }
]
```

Fields other than `CN` are optional per entry. If omitted, the script falls back to
the corresponding global parameter (`-Organization`, `-OrganizationalUnit`, `-Locality`,
`-State`, `-Country`) for that entry.

### Import an issued certificate

```powershell
.\New-CertificateRequest.ps1 -CompleteRequest "C:\Certs\server01.cer"
```

### Import and export in one step

```powershell
.\New-CertificateRequest.ps1 -CompleteAndExport "C:\Certs\server01.cer" -IncludeChain
```

### Export an existing certificate from the store

```powershell
.\New-CertificateRequest.ps1 -ExportPfx -Thumbprint "AB12CD34EF56..." -IncludeChain
```

### Generate a request JSON file from an existing certificate

From a `.cer` file:

```powershell
.\New-CertificateRequest.ps1 -ExportRequestJson -SourceCerFile "C:\Certs\server01.cer"
```

From one or more certificates already in the local store:

```powershell
.\New-CertificateRequest.ps1 -ExportRequestJson -SourceThumbprint "AB12CD34...","EF56AB78..."
```

From the certificate presented by a remote server over TLS (host, `host:port`, or a
full URL; default port 443):

```powershell
.\New-CertificateRequest.ps1 -ExportRequestJson -SourceUrl "server01.contoso.local:443"
```

Exactly one of `-SourceCerFile`, `-SourceThumbprint`, or `-SourceUrl` must be
specified per run (each accepts multiple values). One JSON file is written per
certificate, named after its CN - ready to be used directly as `-ImportFile` for a
new request, e.g. for renewals with the same subject/SAN.

For `-SourceUrl`, trust or validity errors (expired, self-signed, hostname mismatch,
etc.) do not stop the read - the certificate's data is captured regardless, and a
warning is printed instead. The goal is to capture the data of the certificate
currently in use, including ones that are expiring or already invalid.

### Working with the result objects

Every run of the request-creation and `-ExportRequestJson` modes returns its result
objects on the pipeline, in addition to printing a summary table. Capture them to
inspect failures in full or process them further:

```powershell
$r = .\New-CertificateRequest.ps1 -ImportFile ".\requests.json" -Exportable:$false
$r | Where-Object { -not $_.Success } | Format-List *
$r | Export-Csv ".\results.csv" -NoTypeInformation
```

Any failed entry also has its full, untruncated error message printed directly below
the summary table (the table itself truncates long text due to `Format-Table`'s
column-width behavior).

## Parameters

### Request creation

| Parameter | Default | Description |
|---|---|---|
| `-CN` | – | Common Name (single mode, alternative to `-ImportFile`) |
| `-SAN` | – | Additional Subject Alternative Names (single mode) |
| `-ImportFile` | – | Path to a JSON file with one or more request definitions |
| `-Exportable` | **required, no default** | Whether the private key is exportable. Must always be specified explicitly, e.g. `-Exportable:$false` |
| `-KeyLength` | `4096` | RSA key length in bits. Ignored for ECDSA |
| `-KeyAlgorithm` | `RSA` | `RSA` or `ECDSA` |
| `-ECCurve` | `P256` | `P256` / `P384` / `P521`, only relevant for ECDSA |
| `-KeyStorageProvider` | `CNG` | `CNG` or `Legacy` |
| `-ProviderName` | auto-selected | Overrides the CSP/KSP provider name |
| `-HashAlgorithm` | `SHA256` | `SHA256` / `SHA384` / `SHA512` / `SHA1` |
| `-KeyUsage` | `DigitalSignature`, `KeyEncipherment` | One or more key usage flags |
| `-EnhancedKeyUsage` | `ServerAuthentication` | OIDs or short names (`ServerAuthentication`, `ClientAuthentication`, `CodeSigning`, `EmailProtection`) |
| `-Organization`, `-OrganizationalUnit`, `-Locality`, `-State`, `-Country` | – | Global fallback values for JSON entries without their own field |
| `-MachineContext` | `$true` | Machine vs. user context/store. Also determines which store `-CompleteRequest`, `-ExportPfx`, and `-ExportRequestJson -SourceThumbprint` read from |
| `-KeepInf` | `$false` | Keep the generated `.inf` file instead of deleting it |
| `-Force` | `$false` | Overwrite existing output files |

### Other modes

| Parameter | Description |
|---|---|
| `-GenerateExampleJSON` | Writes `example-request.json` and exits |
| `-CompleteRequest <path>` | Path to a `.cer` file to import via `certreq -accept` |
| `-CompleteAndExport <path>` | Import, then export as PFX in the same run |
| `-ExportPfx` | Export mode; requires `-Thumbprint` |
| `-Thumbprint` | Thumbprint of the certificate to export |
| `-IncludeChain` | Include the certificate chain in the PFX export (default: end-entity certificate only) |
| `-ExportRequestJson` | Generate request JSON file(s) from existing certificate data; requires exactly one of the three `-Source...` parameters below |
| `-SourceCerFile <path[]>` | One or more `.cer` files to read certificate data from |
| `-SourceThumbprint <thumbprint[]>` | One or more thumbprints of certificates in the local store to read data from |
| `-SourceUrl <host[]>` | One or more remote hosts (`host`, `host:port`, or a full URL) to read the presented TLS certificate from; default port 443 |

### Global

| Parameter | Default | Description |
|---|---|---|
| `-OutputPath` | current directory | Target directory for all generated files (`.req`, `.inf`, `.json`, `.pfx`) |

## Notes on encoding

The generated `.inf` file is intentionally written as **Unicode (UTF-16 LE)**, not
UTF-8, since `certreq.exe` does not reliably parse UTF-8 `.inf` files. This is a
deliberate exception and only applies to that intermediate file, not to the script
itself.

## Security notes

- `-Exportable` has no default on purpose — it must be a conscious decision per request
- PFX export always prompts for a password interactively (entered twice, compared, then
  cleared from memory); no plain-text password parameter exists
- No private key material or password is ever written to disk in plain text by this script

## File naming

Output file names (`.req`, `.inf`, `.pfx`, and JSON files from `-ExportRequestJson`)
are derived from the certificate's CN, with characters invalid in Windows file names
replaced by `_`.
