#Requires -Version 5.1
<#
.SYNOPSIS
    New-CertificateRequest.ps1 - Creates certificate signing requests (.req) via
    certreq.exe, including import of issued certificates and PFX export.

.DESCRIPTION
    Generates a certreq INF file from CN/SAN input (either as direct parameters or via
    a JSON file, single or batch entry) and calls "certreq -new" to produce the actual
    .req file. The CN is always automatically included as a SAN entry as well.

    In addition, the script supports four further, mutually exclusive modes:
      - Import only, for a certificate received from the CA into the local certificate
        store (-CompleteRequest)
      - Import and immediate PFX export in a single call (-CompleteAndExport)
      - PFX export only, for a certificate already present in the local store
        (-ExportPfx)
      - Generate one or more request JSON files from the data of existing
        certificates - a .cer file, a certificate in the local store (by thumbprint),
        or the certificate presented by a remote server (-ExportRequestJson)

    It can also generate an annotated example JSON file (-GenerateExampleJSON).

    IMPORTANT (encoding): the generated .inf file is deliberately NOT saved as UTF-8,
    but as Unicode (UTF-16 LE), because certreq.exe does not reliably parse UTF-8 INF
    files. This is a deliberate exception to the usual UTF-8-with-BOM standard for
    .ps1 files - it only applies to this intermediate .inf file read by certreq.

.PARAMETER CN
    Common Name of the certificate (single mode, alternative to -ImportFile).

.PARAMETER SAN
    Additional Subject Alternative Names (single mode). The CN is automatically added
    if it is not already included here.

.PARAMETER ImportFile
    Path to a JSON file containing one or more request definitions (batch mode).
    See -GenerateExampleJSON for an example.

.PARAMETER Exportable
    Whether the private key should be exportable. MANDATORY in request mode, has
    deliberately NO default and must always be specified explicitly
    (-Exportable:$true or -Exportable:$false).

.PARAMETER KeyLength
    Key length in bits (RSA). Default: 4096. Ignored when -KeyAlgorithm is ECDSA;
    in that case -ECCurve determines the effective key strength.

.PARAMETER KeyAlgorithm
    RSA or ECDSA. Default: RSA.

.PARAMETER ECCurve
    Curve for ECDSA keys (P256, P384, P521). Default: P256. Only relevant when
    -KeyAlgorithm is ECDSA.

.PARAMETER KeyStorageProvider
    CNG (Key Storage Provider, modern) or Legacy (classic CSP). Default: CNG.

.PARAMETER ProviderName
    Specific CSP/KSP provider name. If not specified, a sensible default is chosen
    based on -KeyStorageProvider.

.PARAMETER HashAlgorithm
    Signature hash algorithm. Default: SHA256.

.PARAMETER KeyUsage
    List of key usage flags (DigitalSignature, NonRepudiation, KeyEncipherment,
    DataEncipherment, KeyAgreement, KeyCertSign, CRLSign, EncipherOnly).
    Default: DigitalSignature, KeyEncipherment.

.PARAMETER EnhancedKeyUsage
    List of EKU OIDs or known short names (ServerAuthentication, ClientAuthentication,
    CodeSigning, EmailProtection). Default: ServerAuthentication.

.PARAMETER Organization
    Organization (O=). Global fallback for JSON entries without their own field.

.PARAMETER OrganizationalUnit
    Department (OU=). Global fallback for JSON entries without their own field.

.PARAMETER Locality
    City (L=). Global fallback for JSON entries without their own field.

.PARAMETER State
    State/province (S=). Global fallback for JSON entries without their own field.

.PARAMETER Country
    Country, 2-letter ISO code (C=). Global fallback for JSON entries without their
    own field.

.PARAMETER MachineContext
    Create/look up the key in the machine (true) or user context (false).
    Default: true. Also applies to -CompleteRequest / -CompleteAndExport / -ExportPfx.

.PARAMETER KeepInf
    Do not delete the generated .inf file after the request.

.PARAMETER Force
    Overwrite existing .req/.inf/.json/.pfx files with the same name.

.PARAMETER GenerateExampleJSON
    Writes an example JSON file (single and batch example) and exits the script.

.PARAMETER CompleteRequest
    Path to a .cer file received from the CA. Imports the certificate into the local
    certificate store via "certreq -accept" (the matching pending request is found
    automatically via the public key).

.PARAMETER CompleteAndExport
    Same as -CompleteRequest, but immediately exports the imported certificate as PFX
    afterwards (the thumbprint is picked up automatically, -Thumbprint is not needed
    here).

.PARAMETER ExportPfx
    Exports a certificate already present in the store as PFX.
    Requires -Thumbprint.

.PARAMETER Thumbprint
    Thumbprint of the certificate to export. Required with -ExportPfx.

.PARAMETER IncludeChain
    Include the certificate chain in the PFX export (ChainOption BuildChain).
    Default: false (end-entity certificate only).

.PARAMETER ExportRequestJson
    Generates one request JSON file per source certificate (named after its CN),
    ready to be used as -ImportFile for a new request (e.g. for renewals with the
    same subject/SAN). Requires exactly one of -SourceCerFile, -SourceThumbprint,
    or -SourceUrl (each accepts multiple values).

.PARAMETER SourceCerFile
    One or more paths to .cer files to read certificate data from.

.PARAMETER SourceThumbprint
    One or more thumbprints of certificates in the local certificate store
    (see -MachineContext for which store) to read certificate data from.

.PARAMETER SourceUrl
    One or more remote hosts to connect to (format "host", "host:port", or a full
    URL) in order to read the certificate presented during the TLS handshake.
    Default port: 443. Trust/validity errors (expired, self-signed, hostname
    mismatch, ...) only produce a warning - the certificate is read regardless,
    since the goal is to capture its data, not to validate the connection.

.PARAMETER OutputPath
    Target directory for all generated files (.req/.inf/.json/.pfx).
    Default: current directory.

.EXAMPLE
    .\New-CertificateRequest.ps1 -CN "server01.contoso.local" -SAN "server01" -Exportable:$false
    Creates a single request with the CN automatically added as a SAN entry.

.EXAMPLE
    .\New-CertificateRequest.ps1 -ImportFile ".\requests.json" -Exportable:$false
    Creates one or more requests from a JSON file (single or batch).

.EXAMPLE
    .\New-CertificateRequest.ps1 -GenerateExampleJSON
    Writes example-request.json to the current directory.

.EXAMPLE
    .\New-CertificateRequest.ps1 -CompleteRequest "C:\Certs\server01.cer"
    Imports the received certificate into the local certificate store.

.EXAMPLE
    .\New-CertificateRequest.ps1 -CompleteAndExport "C:\Certs\server01.cer"
    Imports and exports the certificate in one step (interactive password prompt).

.EXAMPLE
    .\New-CertificateRequest.ps1 -ExportPfx -Thumbprint "AB12CD34..." -IncludeChain
    Exports an existing certificate including the chain as PFX.

.EXAMPLE
    .\New-CertificateRequest.ps1 -ExportRequestJson -SourceCerFile "C:\Certs\server01.cer"
    Writes server01.contoso.local.json, derived from the certificate file.

.EXAMPLE
    .\New-CertificateRequest.ps1 -ExportRequestJson -SourceThumbprint "AB12CD34...","EF56AB78..."
    Writes one JSON file per certificate found in the local store for the given thumbprints.

.EXAMPLE
    .\New-CertificateRequest.ps1 -ExportRequestJson -SourceUrl "server01.contoso.local:443"
    Connects to the host, reads the presented certificate, and writes its JSON definition.

.NOTES
    History:
    - Initial version, Max Droege. Architecture/parameters agreed upfront (modes as
      independent, mutually exclusive switches - pattern analogous to LogCleanup.ps1).

    Requires: certreq.exe (part of Windows), access to the local certificate store for
    -CompleteRequest / -CompleteAndExport / -ExportPfx.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
Param(
    # --- Request creation (default mode) ---
    [string]$CN,
    [string[]]$SAN,
    [string]$ImportFile,

    [bool]$Exportable,

    [int]$KeyLength = 4096,
    [ValidateSet('RSA', 'ECDSA')]
    [string]$KeyAlgorithm = 'RSA',
    [ValidateSet('P256', 'P384', 'P521')]
    [string]$ECCurve = 'P256',
    [ValidateSet('CNG', 'Legacy')]
    [string]$KeyStorageProvider = 'CNG',
    [string]$ProviderName,
    [ValidateSet('SHA256', 'SHA384', 'SHA512', 'SHA1')]
    [string]$HashAlgorithm = 'SHA256',

    [string[]]$KeyUsage = @('DigitalSignature', 'KeyEncipherment'),
    [string[]]$EnhancedKeyUsage = @('ServerAuthentication'),

    [string]$Organization,
    [string]$OrganizationalUnit,
    [string]$Locality,
    [string]$State,
    [string]$Country,

    [bool]$MachineContext = $true,

    [switch]$KeepInf,
    [switch]$Force,

    # --- Other modes ---
    [switch]$GenerateExampleJSON,
    [string]$CompleteRequest,
    [string]$CompleteAndExport,
    [switch]$ExportPfx,
    [string]$Thumbprint,
    [switch]$IncludeChain,

    [switch]$ExportRequestJson,
    [string[]]$SourceCerFile,
    [string[]]$SourceThumbprint,
    [string[]]$SourceUrl,

    # --- Global ---
    [string]$OutputPath = (Get-Location).Path
)

#region Helper functions

function ConvertTo-SafeFileName {
    param([Parameter(Mandatory)][string]$Name)
    $safe = [Regex]::Replace($Name, '[\\\/:\*\?"<>\|]', '_')
    return $safe.Trim()
}

function Resolve-KeyUsageHex {
    param([string[]]$Usages)

    $map = @{
        'DigitalSignature'  = 0x80
        'NonRepudiation'    = 0x40
        'KeyEncipherment'   = 0x20
        'DataEncipherment'  = 0x10
        'KeyAgreement'      = 0x08
        'KeyCertSign'       = 0x04
        'CRLSign'           = 0x02
        'EncipherOnly'      = 0x01
    }

    $value = 0
    foreach ($u in $Usages) {
        $key = ($u -replace '\s', '')
        if (-not $map.ContainsKey($key)) {
            throw "Unknown KeyUsage value: '$u'. Valid values are: $($map.Keys -join ', ')"
        }
        $value = $value -bor $map[$key]
    }
    return ('0x{0:X2}' -f $value)
}

function Resolve-EkuOid {
    param([string[]]$Values)

    $map = @{
        'ServerAuthentication' = '1.3.6.1.5.5.7.3.1'
        'ClientAuthentication' = '1.3.6.1.5.5.7.3.2'
        'CodeSigning'          = '1.3.6.1.5.5.7.3.3'
        'EmailProtection'      = '1.3.6.1.5.5.7.3.4'
    }

    $result = foreach ($v in $Values) {
        $key = ($v -replace '\s', '')
        if ($map.ContainsKey($key)) { $map[$key] }
        elseif ($v -match '^\d+(\.\d+)+$') { $v }
        else { throw "Unknown EnhancedKeyUsage value: '$v'. Valid values are OIDs or: $($map.Keys -join ', ')" }
    }
    return $result
}

function Get-DefaultProviderName {
    param(
        [string]$KeyStorageProvider,
        [string]$KeyAlgorithm
    )
    if ($KeyStorageProvider -eq 'CNG') {
        return 'Microsoft Software Key Storage Provider'
    }
    else {
        return 'Microsoft Enhanced RSA and AES Cryptographic Provider'
    }
}

function Merge-SanWithCn {
    param(
        [Parameter(Mandatory)][string]$CN,
        [string[]]$SAN
    )

    $all = @($CN) + @($SAN)
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $merged = @()
    foreach ($entry in $all) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $trimmed = $entry.Trim()
        if ($seen.Add($trimmed)) { $merged += $trimmed }
    }

    $classified = foreach ($entry in $merged) {
        $ipAddr = $null
        if ([System.Net.IPAddress]::TryParse($entry, [ref]$ipAddr)) {
            [PSCustomObject]@{ Type = 'ipaddress'; Value = $entry }
        }
        else {
            [PSCustomObject]@{ Type = 'dns'; Value = $entry }
        }
    }
    return $classified
}

function New-ExampleJsonFile {
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$Force
    )

    $path = Join-Path $OutputPath 'example-request.json'
    if ((Test-Path $path) -and -not $Force) {
        throw "File already exists: $path (use -Force to overwrite)"
    }

    $example = @(
        [ordered]@{
            CN                 = 'server01.contoso.local'
            SAN                = @('server01', '10.0.0.5')
            Organization       = 'Contoso GmbH'
            OrganizationalUnit = 'IT'
            Locality           = 'Hamburg'
            State              = 'Hamburg'
            Country            = 'DE'
            FriendlyName       = 'server01 Webcert 2026'
        },
        [ordered]@{
            CN  = 'server02.contoso.local'
            SAN = @('server02.contoso.local')
        }
    )

    $json = $example | ConvertTo-Json -Depth 5
    if ($PSCmdlet.ShouldProcess($path, 'Write example JSON file')) {
        [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)
    }
    Write-Host "Example JSON written: $path" -ForegroundColor Green
    return $path
}

function Import-CertRequestDefinitions {
    param(
        [string]$CN,
        [string[]]$SAN,
        [string]$ImportFile,
        [hashtable]$GlobalDefaults
    )

    if ($ImportFile) {
        if (-not (Test-Path $ImportFile)) {
            throw "ImportFile not found: $ImportFile"
        }
        $raw = Get-Content -Path $ImportFile -Raw | ConvertFrom-Json
        $entries = @($raw)
    }
    else {
        $entries = @([PSCustomObject]@{ CN = $CN; SAN = $SAN })
    }

    $normalized = foreach ($entry in $entries) {
        if (-not $entry.CN) {
            throw "An entry in the request definition has no CN."
        }
        [PSCustomObject]@{
            CN                 = $entry.CN
            SAN                = @($entry.SAN)
            Organization       = if ($entry.Organization)       { $entry.Organization }       else { $GlobalDefaults.Organization }
            OrganizationalUnit = if ($entry.OrganizationalUnit) { $entry.OrganizationalUnit }  else { $GlobalDefaults.OrganizationalUnit }
            Locality           = if ($entry.Locality)           { $entry.Locality }            else { $GlobalDefaults.Locality }
            State              = if ($entry.State)              { $entry.State }               else { $GlobalDefaults.State }
            Country            = if ($entry.Country)            { $entry.Country }             else { $GlobalDefaults.Country }
            FriendlyName       = $entry.FriendlyName
        }
    }
    return $normalized
}

function New-CertRequestInfContent {
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][bool]$Exportable,
        [int]$KeyLength,
        [string]$KeyAlgorithm,
        [string]$ECCurve,
        [string]$KeyStorageProvider,
        [string]$ProviderName,
        [string]$HashAlgorithm,
        [string[]]$KeyUsage,
        [string[]]$EnhancedKeyUsage,
        [bool]$MachineContext
    )

    $subjectParts = @()
    $subjectParts += "CN=$($Definition.CN)"
    if ($Definition.OrganizationalUnit) { $subjectParts += "OU=$($Definition.OrganizationalUnit)" }
    if ($Definition.Organization)       { $subjectParts += "O=$($Definition.Organization)" }
    if ($Definition.Locality)           { $subjectParts += "L=$($Definition.Locality)" }
    if ($Definition.State)              { $subjectParts += "S=$($Definition.State)" }
    if ($Definition.Country)            { $subjectParts += "C=$($Definition.Country)" }
    $subject = $subjectParts -join ', '

    $isCng = ($KeyStorageProvider -eq 'CNG')
    $resolvedProviderName = if ($ProviderName) { $ProviderName } else { Get-DefaultProviderName -KeyStorageProvider $KeyStorageProvider -KeyAlgorithm $KeyAlgorithm }

    $keyUsageHex = Resolve-KeyUsageHex -Usages $KeyUsage
    $exportableStr = if ($Exportable) { 'TRUE' } else { 'FALSE' }
    $machineKeySetStr = if ($MachineContext) { 'TRUE' } else { 'FALSE' }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('[Version]')
    $lines.Add('Signature = "$Windows NT$"')
    $lines.Add('')
    $lines.Add('[NewRequest]')
    $lines.Add("Subject = `"$subject`"")
    $lines.Add("Exportable = $exportableStr")
    $lines.Add("MachineKeySet = $machineKeySetStr")
    $lines.Add('SMIME = FALSE')
    $lines.Add('PrivateKeyArchive = FALSE')
    $lines.Add('UserProtected = FALSE')
    $lines.Add('UseExistingKeySet = FALSE')
    $lines.Add("ProviderName = `"$resolvedProviderName`"")
    $lines.Add("HashAlgorithm = $HashAlgorithm")
    $lines.Add("KeyUsage = $keyUsageHex")
    $lines.Add('RequestType = PKCS10')

    if ($isCng) {
        $lines.Add('KeySpec = 0')
        if ($KeyAlgorithm -eq 'ECDSA') {
            $lines.Add("KeyAlgorithm = ECDSA_$ECCurve")
        }
        else {
            $lines.Add('KeyAlgorithm = RSA')
            $lines.Add("KeyLength = $KeyLength")
        }
    }
    else {
        # Legacy CSP: RSA only, no CNG-specific KeyAlgorithm/KeySpec=0
        $lines.Add('KeySpec = 1')
        $lines.Add('ProviderType = 24')
        $lines.Add("KeyLength = $KeyLength")
    }

    $sanEntries = Merge-SanWithCn -CN $Definition.CN -SAN $Definition.SAN
    $lines.Add('')
    $lines.Add('[Extensions]')
    $lines.Add('2.5.29.17 = "{text}"')
    foreach ($san in $sanEntries) {
        $lines.Add("_continue_ = `"$($san.Type)=$($san.Value)&`"")
    }

    if ($EnhancedKeyUsage -and $EnhancedKeyUsage.Count -gt 0) {
        $oids = Resolve-EkuOid -Values $EnhancedKeyUsage
        $lines.Add('')
        $lines.Add('[EnhancedKeyUsageExtension]')
        foreach ($oid in $oids) {
            $lines.Add("OID = $oid")
        }
    }

    return ($lines -join "`r`n")
}

function Save-InfFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content,
        [switch]$Force
    )

    if ((Test-Path $Path) -and -not $Force) {
        throw "File already exists: $Path (use -Force to overwrite)"
    }

    # Deliberately Unicode (UTF-16 LE) instead of UTF-8 - certreq.exe expects this
    # encoding for the .inf file, regardless of the usual UTF-8-BOM standard for
    # .ps1 script files.
    if ($PSCmdlet.ShouldProcess($Path, 'Write INF file')) {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::Unicode)
    }
}

function Invoke-CertReq {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$InfPath,
        [Parameter(Mandatory)][string]$ReqPath
    )

    if (-not $PSCmdlet.ShouldProcess($ReqPath, 'certreq -new (generate CSR)')) {
        return [PSCustomObject]@{ Success = $true; Output = '(WhatIf - not executed)' }
    }

    $output = & certreq.exe -new -q $InfPath $ReqPath 2>&1
    $success = ($LASTEXITCODE -eq 0)
    return [PSCustomObject]@{ Success = $success; Output = ($output -join "`n") }
}

function Complete-CertRequest {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$CerFile,
        [bool]$MachineContext = $true
    )

    if (-not (Test-Path $CerFile)) {
        throw "Certificate file not found: $CerFile"
    }

    $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerFile)
    $expectedThumbprint = $certObj.Thumbprint

    if ($PSCmdlet.ShouldProcess($CerFile, 'certreq -accept (import into certificate store)')) {
        $output = & certreq.exe -accept -q $CerFile 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "certreq -accept failed (ExitCode $LASTEXITCODE): $($output -join ' ')"
        }
    }
    else {
        return $expectedThumbprint
    }

    $storeLocation = if ($MachineContext) { 'Cert:\LocalMachine\My' } else { 'Cert:\CurrentUser\My' }
    $imported = Get-ChildItem -Path $storeLocation | Where-Object { $_.Thumbprint -eq $expectedThumbprint }
    if (-not $imported) {
        Write-Warning "certreq accepted the certificate, but it could not be found under $storeLocation (context mismatch? see -MachineContext)."
    }

    return $expectedThumbprint
}

function Export-CertRequestPfx {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)][string]$Thumbprint,
        [bool]$MachineContext = $true,
        [switch]$IncludeChain,
        [string]$OutputPath = (Get-Location).Path,
        [switch]$Force
    )

    $storeLocation = if ($MachineContext) { 'Cert:\LocalMachine\My' } else { 'Cert:\CurrentUser\My' }
    $cert = Get-ChildItem -Path $storeLocation | Where-Object { $_.Thumbprint -eq $Thumbprint }
    if (-not $cert) {
        throw "Certificate with thumbprint '$Thumbprint' was not found under $storeLocation."
    }
    if (-not $cert.HasPrivateKey) {
        throw "Certificate with thumbprint '$Thumbprint' has no private key and cannot be exported as PFX."
    }

    $cnPart = ($cert.Subject -split ',')[0] -replace '^CN=', ''
    $safeName = ConvertTo-SafeFileName -Name $cnPart
    $pfxPath = Join-Path $OutputPath "$safeName.pfx"

    if ((Test-Path $pfxPath) -and -not $Force) {
        throw "File already exists: $pfxPath (use -Force to overwrite)"
    }

    $securePwd1 = Read-Host -Prompt "Password for PFX export ($safeName)" -AsSecureString
    $securePwd2 = Read-Host -Prompt 'Confirm password' -AsSecureString

    $bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd1)
    $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd2)
    try {
        $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1)
        $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
        if ($plain1 -ne $plain2) {
            throw 'The passwords entered do not match.'
        }
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
        Remove-Variable plain1, plain2 -ErrorAction SilentlyContinue
    }

    $chainOption = if ($IncludeChain) { 'BuildChain' } else { 'EndEntityCertOnly' }

    if ($PSCmdlet.ShouldProcess($pfxPath, 'Export-PfxCertificate')) {
        Export-PfxCertificate -Cert $cert.PSPath -FilePath $pfxPath -Password $securePwd1 -ChainOption $chainOption | Out-Null
    }

    return $pfxPath
}

function ConvertFrom-CertificateToDefinition {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    # Parse the Subject DN into its RDN components (CN/OU/O/L/S/C), respecting
    # escaped commas within a value (e.g. "O=Contoso\, Inc.").
    $subjectDict = @{}
    foreach ($rdn in ($Certificate.Subject -split '(?<!\\),')) {
        $parts = $rdn.Trim() -split '=', 2
        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim().ToUpperInvariant()
            $value = $parts[1].Trim()
            if (-not $subjectDict.ContainsKey($key)) { $subjectDict[$key] = $value }
        }
    }

    $cn = $subjectDict['CN']
    if (-not $cn) {
        throw "Certificate has no CN in its subject: $($Certificate.Subject)"
    }

    # Read the SAN extension (OID 2.5.29.17) value-based rather than label-based,
    # since .NET only exposes it as a formatted, UI-culture-dependent string
    # (e.g. "DNS Name=..." on English Windows vs. "DNS-Name=..." on German Windows).
    # Classifying by the value's shape (looks like an IP -> IP, otherwise DNS) avoids
    # any dependency on the OS locale.
    $sanList = @()
    $sanExt = $Certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
    if ($sanExt) {
        $formatted = $sanExt.Format($true)
        $tokens = $formatted -split "(`r`n|,)" | Where-Object { $_ -match '=' }
        foreach ($token in $tokens) {
            $value = ($token -split '=', 2)[1]
            if ($value) { $sanList += $value.Trim() }
        }
    }

    # The CN is dropped from the SAN list here - New-CertRequestInfContent adds it
    # back automatically on the next request run (Merge-SanWithCn), so there is no
    # need to carry it over explicitly.
    $sanList = $sanList | Where-Object { $_ -and ($_ -ne $cn) } | Select-Object -Unique

    [PSCustomObject]@{
        CN                 = $cn
        SAN                = @($sanList)
        Organization       = $subjectDict['O']
        OrganizationalUnit = $subjectDict['OU']
        Locality           = $subjectDict['L']
        State              = $subjectDict['S']
        Country            = $subjectDict['C']
        FriendlyName       = $Certificate.FriendlyName
    }
}

function Get-CertificateFromUrl {
    param(
        [Parameter(Mandatory)][string]$UrlOrHost
    )

    $targetHost = $UrlOrHost
    $port = 443

    # Accepts "host", "host:port", or a full URL ("https://host:port/...")
    if ($targetHost -match '^[a-zA-Z]+://') {
        $uri = [Uri]$targetHost
        $targetHost = $uri.Host
        $port = if ($uri.Port -gt 0) { $uri.Port } else { 443 }
    }
    elseif ($targetHost -match '^(.+):(\d+)$') {
        $targetHost = $matches[1]
        $port = [int]$matches[2]
    }

    $script:LastSslPolicyErrors = [System.Net.Security.SslPolicyErrors]::None
    $validationCallback = {
        param($sender, $certificate, $chain, $sslPolicyErrors)
        $script:LastSslPolicyErrors = $sslPolicyErrors
        # Always accept - the goal here is to read the certificate's data, not to
        # validate the connection. Trust/validity issues are reported as a warning
        # by the caller instead of aborting the read.
        return $true
    }

    $tcpClient = New-Object System.Net.Sockets.TcpClient
    try {
        $tcpClient.Connect($targetHost, $port)
        $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false, $validationCallback)
        try {
            $sslStream.AuthenticateAsClient($targetHost)
            $remoteCert = $sslStream.RemoteCertificate
            if (-not $remoteCert) {
                throw "No certificate received from ${targetHost}:${port}."
            }
            if ($script:LastSslPolicyErrors -ne [System.Net.Security.SslPolicyErrors]::None) {
                Write-Warning "Certificate from ${targetHost}:${port} did not pass trust validation ($($script:LastSslPolicyErrors)). Reading its data anyway."
            }
            return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($remoteCert)
        }
        finally {
            $sslStream.Dispose()
        }
    }
    finally {
        $tcpClient.Dispose()
    }
}

function Save-RequestJsonFile {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$OutputPath,
        [switch]$Force
    )

    $safeName = ConvertTo-SafeFileName -Name $Definition.CN
    $jsonPath = Join-Path $OutputPath "$safeName.json"

    if ((Test-Path $jsonPath) -and -not $Force) {
        throw "File already exists: $jsonPath (use -Force to overwrite)"
    }

    $ordered = [ordered]@{
        CN  = $Definition.CN
        SAN = @($Definition.SAN)
    }
    if ($Definition.Organization)       { $ordered.Organization       = $Definition.Organization }
    if ($Definition.OrganizationalUnit) { $ordered.OrganizationalUnit = $Definition.OrganizationalUnit }
    if ($Definition.Locality)           { $ordered.Locality           = $Definition.Locality }
    if ($Definition.State)              { $ordered.State              = $Definition.State }
    if ($Definition.Country)            { $ordered.Country            = $Definition.Country }
    if ($Definition.FriendlyName)       { $ordered.FriendlyName       = $Definition.FriendlyName }

    $json = @($ordered) | ConvertTo-Json -Depth 5

    if ($PSCmdlet.ShouldProcess($jsonPath, 'Write request JSON file')) {
        [System.IO.File]::WriteAllText($jsonPath, $json, [System.Text.Encoding]::UTF8)
    }

    return $jsonPath
}

function Write-FailedResultDetails {
    param(
        [Parameter(Mandatory)]$Results,
        [string]$IdentifierProperty = 'CN'
    )

    $failedResults = @($Results | Where-Object { -not $_.Success })
    if ($failedResults.Count -eq 0) { return }

    Write-Host ''
    Write-Host 'Details for failed entries (full, untruncated message):' -ForegroundColor Yellow
    foreach ($item in $failedResults) {
        Write-Host '---' -ForegroundColor Yellow
        Write-Host "$($IdentifierProperty): $($item.$IdentifierProperty)"
        Write-Host "Message: $($item.Message)"
    }
    Write-Host ''
}

function Get-RequestMode {
    $modes = @()
    if ($GenerateExampleJSON) { $modes += 'GenerateExampleJSON' }
    if ($CompleteRequest)     { $modes += 'CompleteRequest' }
    if ($CompleteAndExport)   { $modes += 'CompleteAndExport' }
    if ($ExportPfx)           { $modes += 'ExportPfx' }
    if ($ExportRequestJson)   { $modes += 'ExportRequestJson' }

    if ($modes.Count -gt 1) {
        throw "The modes $($modes -join ', ') are mutually exclusive. Please specify only one."
    }
    if ($modes.Count -eq 0) { return 'NewRequest' }
    return $modes[0]
}

function Test-InputParameters {
    param([string]$Mode)

    switch ($Mode) {
        'NewRequest' {
            if ($CN -and $ImportFile) {
                throw "-CN and -ImportFile are mutually exclusive."
            }
            if (-not $CN -and -not $ImportFile) {
                throw "Please specify either -CN (single mode) or -ImportFile (batch mode)."
            }
            if (-not $PSBoundParameters.ContainsKey('Exportable') -and -not $script:ExportableBound) {
                throw "-Exportable must be specified explicitly (no default). Example: -Exportable:`$false"
            }
        }
        'ExportPfx' {
            if (-not $Thumbprint) {
                throw "-ExportPfx requires -Thumbprint."
            }
        }
        'CompleteRequest' {
            if (-not (Test-Path $CompleteRequest)) {
                throw "File for -CompleteRequest not found: $CompleteRequest"
            }
        }
        'CompleteAndExport' {
            if (-not (Test-Path $CompleteAndExport)) {
                throw "File for -CompleteAndExport not found: $CompleteAndExport"
            }
        }
        'ExportRequestJson' {
            $provided = @()
            if ($SourceCerFile)    { $provided += 'SourceCerFile' }
            if ($SourceThumbprint) { $provided += 'SourceThumbprint' }
            if ($SourceUrl)        { $provided += 'SourceUrl' }

            if ($provided.Count -eq 0) {
                throw "-ExportRequestJson requires exactly one of -SourceCerFile, -SourceThumbprint, or -SourceUrl."
            }
            if ($provided.Count -gt 1) {
                throw "Please specify only one of -SourceCerFile, -SourceThumbprint, or -SourceUrl (found: $($provided -join ', '))."
            }
        }
    }
}

#endregion

#region Main

try {
    # Tracks whether -Exportable was actually bound in the original call
    # ($PSBoundParameters from the script scope applies here directly, no sub-scope issue).
    $script:ExportableBound = $PSBoundParameters.ContainsKey('Exportable')

    $Mode = Get-RequestMode
    Test-InputParameters -Mode $Mode

    if (-not (Test-Path $OutputPath)) {
        throw "OutputPath not found: $OutputPath"
    }

    switch ($Mode) {

        'GenerateExampleJSON' {
            New-ExampleJsonFile -OutputPath $OutputPath -Force:$Force
        }

        'CompleteRequest' {
            $tp = Complete-CertRequest -CerFile $CompleteRequest -MachineContext $MachineContext
            Write-Host "Certificate imported. Thumbprint: $tp" -ForegroundColor Green
        }

        'CompleteAndExport' {
            $tp = Complete-CertRequest -CerFile $CompleteAndExport -MachineContext $MachineContext
            Write-Host "Certificate imported. Thumbprint: $tp" -ForegroundColor Green
            $pfxPath = Export-CertRequestPfx -Thumbprint $tp -MachineContext $MachineContext -IncludeChain:$IncludeChain -OutputPath $OutputPath -Force:$Force
            Write-Host "PFX exported: $pfxPath" -ForegroundColor Green
        }

        'ExportPfx' {
            $pfxPath = Export-CertRequestPfx -Thumbprint $Thumbprint -MachineContext $MachineContext -IncludeChain:$IncludeChain -OutputPath $OutputPath -Force:$Force
            Write-Host "PFX exported: $pfxPath" -ForegroundColor Green
        }

        'ExportRequestJson' {
            $sourceType = if ($SourceCerFile) { 'CerFile' } elseif ($SourceThumbprint) { 'Thumbprint' } else { 'Url' }
            $storeLocation = if ($MachineContext) { 'Cert:\LocalMachine\My' } else { 'Cert:\CurrentUser\My' }

            $sourceValues = switch ($sourceType) {
                'CerFile'    { $SourceCerFile }
                'Thumbprint' { $SourceThumbprint }
                'Url'        { $SourceUrl }
            }

            $results = foreach ($sourceValue in $sourceValues) {
                $resultObj = [PSCustomObject]@{
                    Source   = $sourceValue
                    CN       = ''
                    JsonPath = ''
                    Success  = $false
                    Message  = ''
                }

                try {
                    $cert = switch ($sourceType) {
                        'CerFile' {
                            if (-not (Test-Path $sourceValue)) { throw "Certificate file not found: $sourceValue" }
                            New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sourceValue)
                        }
                        'Thumbprint' {
                            $found = Get-ChildItem -Path $storeLocation | Where-Object { $_.Thumbprint -eq $sourceValue }
                            if (-not $found) { throw "Certificate with thumbprint '$sourceValue' was not found under $storeLocation." }
                            $found
                        }
                        'Url' {
                            Get-CertificateFromUrl -UrlOrHost $sourceValue
                        }
                    }

                    $def = ConvertFrom-CertificateToDefinition -Certificate $cert
                    $jsonPath = Save-RequestJsonFile -Definition $def -OutputPath $OutputPath -Force:$Force

                    $resultObj.CN       = $def.CN
                    $resultObj.JsonPath = $jsonPath
                    $resultObj.Success  = $true
                }
                catch {
                    $resultObj.Message = $_.Exception.Message
                }

                $resultObj
            }

            $results | Format-Table Source, CN, JsonPath, Success, Message -AutoSize | Out-Host
            Write-FailedResultDetails -Results $results -IdentifierProperty 'Source'

            $failed = ($results | Where-Object { -not $_.Success }).Count
            Write-Host "Total: $($results.Count) certificate(s) processed, $failed failed." -ForegroundColor $(if ($failed -gt 0) { 'Yellow' } else { 'Green' })

            $results
        }

        'NewRequest' {
            $globalDefaults = @{
                Organization       = $Organization
                OrganizationalUnit = $OrganizationalUnit
                Locality           = $Locality
                State              = $State
                Country            = $Country
            }

            if ($KeyAlgorithm -eq 'ECDSA' -and $PSBoundParameters.ContainsKey('KeyLength')) {
                Write-Warning "-KeyLength is ignored when -KeyAlgorithm is ECDSA. -ECCurve ($ECCurve) determines the key strength instead."
            }

            $definitions = Import-CertRequestDefinitions -CN $CN -SAN $SAN -ImportFile $ImportFile -GlobalDefaults $globalDefaults

            $results = foreach ($def in $definitions) {
                $safeName = ConvertTo-SafeFileName -Name $def.CN
                $infPath  = Join-Path $OutputPath "$safeName.inf"
                $reqPath  = Join-Path $OutputPath "$safeName.req"

                $resultObj = [PSCustomObject]@{
                    CN      = $def.CN
                    ReqPath = $reqPath
                    Success = $false
                    Message = ''
                }

                try {
                    $infContent = New-CertRequestInfContent -Definition $def -Exportable $Exportable `
                        -KeyLength $KeyLength -KeyAlgorithm $KeyAlgorithm -ECCurve $ECCurve `
                        -KeyStorageProvider $KeyStorageProvider -ProviderName $ProviderName `
                        -HashAlgorithm $HashAlgorithm -KeyUsage $KeyUsage -EnhancedKeyUsage $EnhancedKeyUsage `
                        -MachineContext $MachineContext

                    Save-InfFile -Path $infPath -Content $infContent -Force:$Force

                    $crResult = Invoke-CertReq -InfPath $infPath -ReqPath $reqPath
                    $resultObj.Success = $crResult.Success
                    $resultObj.Message = $crResult.Output

                    if (-not $KeepInf -and (Test-Path $infPath)) {
                        Remove-Item -Path $infPath -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    $resultObj.Message = $_.Exception.Message
                }

                $resultObj
            }

            $results | Format-Table CN, ReqPath, Success, Message -AutoSize | Out-Host
            Write-FailedResultDetails -Results $results -IdentifierProperty 'CN'

            $failed = ($results | Where-Object { -not $_.Success }).Count
            Write-Host "Total: $($results.Count) request(s), $failed failed." -ForegroundColor $(if ($failed -gt 0) { 'Yellow' } else { 'Green' })

            $results
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

#endregion
