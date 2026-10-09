$ErrorActionPreference = 'Stop'
$gameExe = 'D:\Steam\steamapps\common\Kingdom Rush Frontiers\Kingdom Rush Frontiers.exe'
$backupExe = 'D:\Steam\steamapps\common\Kingdom Rush Frontiers\codex-frontiers-trainer-backup-20261010\Kingdom Rush Frontiers.exe'
$reportPath = Join-Path $PSScriptRoot 'install-report.json'
if (Get-Process -Name 'Kingdom Rush Frontiers' -ErrorAction SilentlyContinue) {
    throw 'Close Kingdom Rush Frontiers before restoring.'
}
$report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentHash = (Get-FileHash -LiteralPath $gameExe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($currentHash -eq $report.original_sha256) { Write-Host 'Already original.'; exit 0 }
if ($currentHash -ne $report.installed_sha256) { throw 'Game was updated or changed. Refusing to overwrite.' }
if ((Get-FileHash -LiteralPath $backupExe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.original_sha256) {
    throw 'Backup integrity check failed.'
}
Copy-Item -LiteralPath $backupExe -Destination $gameExe -Force
if ((Get-FileHash -LiteralPath $gameExe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $report.original_sha256) {
    throw 'Restored executable integrity check failed.'
}
Write-Host 'Original game restored. Your current save files were preserved.'
