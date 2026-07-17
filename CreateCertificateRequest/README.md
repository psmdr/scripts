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
- `-WhatIf` support for all file-writing and `certreq`/store-modifying operations

## Requirements

- Windows with `certreq.exe` (built-in)
- PowerShell 5.1 or later
- Local admin rights are **not** required by the script itself, but the target
  certificate store operations (`-CompleteRequest`, `-ExportPfx`, etc.) require access
  to the relevant certificate store (LocalMachine vs. CurrentUser, see `-MachineContext`)

## Modes

The script has four mutually exclusive modes. If none of the mode switches below is
used, it defaults to creating a new request.

| Mode | Switch | Purpose |
|---|---|---|
| New request (default) | `-CN` / `-SAN` or `-ImportFile` | Create one or more CSRs |
| Generate example JSON | `-GenerateExampleJSON` | Write an example import file and exit |
| Complete request | `-CompleteRequest <file.cer>` | Import an issued certificate into the store |
| Complete and export | `-CompleteAndExport <file.cer>` | Import, then immediately export as PFX |
| Export PFX | `-ExportPfx -Thumbprint <thumbprint>` | Export an existing certificate as PFX |

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
| `-MachineContext` | `$true` | Machine vs. user context/store |
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

Output file names (`.req`, `.inf`, `.pfx`) are derived from the certificate's CN,
with characters invalid in Windows file names replaced by `_`.
