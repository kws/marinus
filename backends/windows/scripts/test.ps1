param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$backend = Split-Path $PSScriptRoot -Parent
$repo = (Resolve-Path (Join-Path $backend '..\..')).Path
$fixtures = Join-Path $backend 'results\fixtures'
dotnet run --project (Join-Path $backend 'tests\Marinus.Windows.Tests') -c Release -- --emit-fixtures $fixtures
if ($LASTEXITCODE -ne 0) { throw 'Windows synthetic tests failed' }
& $Python (Join-Path $repo 'scripts\check-contracts.py') $fixtures
if ($LASTEXITCODE -ne 0) { throw 'Windows output validation failed' }
