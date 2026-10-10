param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [switch]$Development,
    [string]$MakeNSIS = 'makensis',
    [string]$SignTool = 'signtool'
)
$ErrorActionPreference = 'Stop'
$backend = Split-Path $PSScriptRoot -Parent
if (!$Development -and (!$env:WINDOWS_SIGN_THUMBPRINT -or !$env:WINDOWS_TIMESTAMP_URL)) {
    throw 'Set WINDOWS_SIGN_THUMBPRINT and WINDOWS_TIMESTAMP_URL, or pass -Development for an unsigned test installer.'
}
function Sign-Artifact([string]$Path) {
    & $SignTool sign /sha1 $env:WINDOWS_SIGN_THUMBPRINT /fd SHA256 /tr $env:WINDOWS_TIMESTAMP_URL /td SHA256 $Path
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $Path" }
    & $SignTool verify /pa $Path
    if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $Path" }
}
& (Join-Path $PSScriptRoot 'build.ps1') -Runtime $Runtime
$payload = Join-Path $backend 'dist'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('marinus-installer-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    # Use a clean payload, so old build artifacts or installers cannot be bundled recursively.
    $staged = Join-Path $temporary 'payload'
    New-Item -ItemType Directory -Path $staged | Out-Null
    foreach ($name in @('marinus.exe', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'licenses')) {
        Copy-Item -Path (Join-Path $payload $name) -Destination $staged -Recurse
    }
    if (!$Development) { Sign-Artifact (Join-Path $staged 'marinus.exe') }
    $manifest = Join-Path $temporary 'uninstall.nsh'
    $lines = @()
    foreach ($file in Get-ChildItem $staged -File -Recurse) {
        $relative = $file.FullName.Substring($staged.Length + 1)
        $lines += 'Delete "$INSTDIR\' + $relative + '"'
    }
    foreach ($directory in (Get-ChildItem $staged -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending)) {
        $relative = $directory.FullName.Substring($staged.Length + 1)
        $lines += 'RMDir "$INSTDIR\' + $relative + '"'
    }
    [IO.File]::WriteAllLines($manifest, $lines)
    $suffix = if ($Development) { '-development' } else { '' }
    $output = Join-Path $payload "marinus-cli-0.1.0-$Runtime$suffix-setup.exe"
    # NSIS signs the embedded uninstaller before it is compressed into the installer.
    $signArguments = @()
    if (!$Development) {
        $uninstallerSign = '"' + $SignTool + '" sign /sha1 ' + $env:WINDOWS_SIGN_THUMBPRINT + ' /fd SHA256 /tr ' + $env:WINDOWS_TIMESTAMP_URL + ' /td SHA256 "%1"'
        $signArguments = @("/X!uninstfinalize '$uninstallerSign' = 0")
    }
    & $MakeNSIS "/DPAYLOAD=$staged" "/DOUTPUT=$output" "/DUNINSTALL_MANIFEST=$manifest" @signArguments (Join-Path $backend 'packaging\cli.nsi')
    if ($LASTEXITCODE -ne 0) { throw 'NSIS installer build failed' }
    if (!$Development) { Sign-Artifact $output }
    Write-Output "Created $output"
} finally { Remove-Item $temporary -Recurse -Force }
