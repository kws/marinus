param(
    [string]$Runtime = 'win-x64',
    [switch]$FrameworkDependent
)
$ErrorActionPreference = 'Stop'
$backend = Split-Path $PSScriptRoot -Parent
$selfContained = (!$FrameworkDependent).ToString().ToLowerInvariant()
dotnet publish (Join-Path $backend 'src\Marinus.Cli\Marinus.Cli.csproj') -c Release -r $Runtime `
    --self-contained $selfContained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -o (Join-Path $backend 'dist') --nologo
if ($LASTEXITCODE -ne 0) { throw 'Windows CLI publish failed' }
Write-Output ('CLI: ' + (Join-Path $backend 'dist\marinus.exe'))
