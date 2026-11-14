# Wire claudinho into the PowerShell profile and set up ~\.config\claudinho.
# Windows port of install.sh. Run from the clone:
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
# Keep this file ASCII (see claudinho.ps1).
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
$line = ". `"$here\claudinho.ps1`""
$rc = $PROFILE.CurrentUserCurrentHost
$dir = Join-Path $HOME '.config\claudinho'

New-Item -ItemType Directory -Force -Path (Split-Path $rc) | Out-Null
if (-not (Test-Path -LiteralPath $rc)) { New-Item -ItemType File -Path $rc | Out-Null }
if (-not (Select-String -LiteralPath $rc -SimpleMatch $line -Quiet)) {
  Add-Content -LiteralPath $rc -Value "`r`n# claudinho: Claude Code on a switchable model provider`r`n$line"
  "added to ${rc}: $line"
} else {
  "already in $rc"
}

New-Item -ItemType Directory -Force -Path (Join-Path $dir 'providers') | Out-Null
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $here 'providers') -Filter '*.env' -File) {
  if ($f.Name -eq 'template.env') { continue }
  $dest = Join-Path $dir "providers\$($f.Name)"
  if (-not (Test-Path -LiteralPath $dest)) {
    Copy-Item -LiteralPath $f.FullName -Destination $dest
    icacls $dest /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
    "created $dest - put the API key there"
  }
}

$current = Join-Path $dir 'current'
if (-not (Test-Path -LiteralPath $current)) {
  $first = Get-ChildItem -LiteralPath (Join-Path $dir 'providers') -Filter '*.env' -File | Sort-Object Name | Select-Object -First 1
  if ($first) {
    [IO.File]::WriteAllText($current, "$($first.BaseName)`n")
    "active provider: $($first.BaseName)"
  }
}
"now open a new PowerShell window and run: claudinho-switch"
