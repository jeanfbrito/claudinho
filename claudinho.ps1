# claudinho for Windows: Claude Code on a switchable model provider.
#
# Windows PowerShell 5.1 and PowerShell 7 port of claudinho.zsh. It has the
# same commands and reads the same provider files.
#
# Dot-source this file from $PROFILE (install.ps1 adds this line):
#   . "C:\path\to\clone\claudinho.ps1"
#
# Commands:
#   claudinho [args]            run Claude Code on the active provider, with
#                               --dangerously-skip-permissions --chrome
#   codexinho [args]            run Claude Code on the cx provider
#   grokinho [args]             run Claude Code on the grok provider
#   claudinho-switch            show providers and which one is active
#   claudinho-switch <name>     make <name> the active provider
#   claudinho-switch show       print the active provider file
#   claudinho-switch add <name> create a provider file from the template
#   claudinho-switch bin|dir    paths in use
#
# Providers are files in ~\.config\claudinho\providers\<name>.env. The file
# format is the zsh one: lines of `export NAME="value"`, with optional
# trailing `# comments`. Values are literal: no $VAR expansion.
# The active name is stored in ~\.config\claudinho\current.
# $env:CLAUDINHO_PROVIDER = '<name>' runs one provider without switching.
# `claude` itself is never touched.
#
# Keep this file ASCII: Windows PowerShell 5.1 reads a file without a BOM
# in the ANSI code page.

$script:ClaudinhoRepo = $PSScriptRoot
$script:ClaudinhoDefaultFlags = @('--dangerously-skip-permissions', '--chrome')

function _claudinho_err([string]$msg) { [Console]::Error.WriteLine("claudinho: $msg") }

function _claudinho_dir {
  if ($env:CLAUDINHO_DIR) { return $env:CLAUDINHO_DIR }
  Join-Path $HOME '.config\claudinho'
}

function _claudinho_file([string]$name) { Join-Path (_claudinho_dir) "providers\$name.env" }

# Get-Command -CommandType Application skips aliases and functions, like
# `whence -p` in zsh.
function _claudinho_bin {
  $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { _claudinho_err 'cannot find the claude binary in PATH'; return $null }
  $c.Source
}

function _claudinho_current {
  if ($env:CLAUDINHO_PROVIDER) { return $env:CLAUDINHO_PROVIDER }
  $f = Join-Path (_claudinho_dir) 'current'
  if (Test-Path -LiteralPath $f) { return (Get-Content -LiteralPath $f -Raw).Trim() }
  $null
}

# A provider name is a file name: letters, digits, dot, dash, underscore.
function _claudinho_valid([string]$name) {
  if ($name -cnotmatch '^[A-Za-z0-9_-][A-Za-z0-9._-]*$') {
    _claudinho_err "bad provider name '$name'. Use letters, digits, '.', '-' or '_'."
    return $false
  }
  $true
}

function _claudinho_names {
  $p = Join-Path (_claudinho_dir) 'providers'
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  @(Get-ChildItem -LiteralPath $p -Filter '*.env' -File | Sort-Object Name | ForEach-Object { $_.BaseName })
}

# Parse `export NAME=value` lines into an ordered table.
function _claudinho_read([string]$file) {
  $vars = [ordered]@{}
  foreach ($line in Get-Content -LiteralPath $file) {
    if ($line -notmatch '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { continue }
    $k = $Matches[1]
    $v = $Matches[2].TrimStart()
    if ($v.StartsWith('"') -or $v.StartsWith("'")) {
      $q = $v[0]
      $end = $v.IndexOf($q, 1)
      if ($end -gt 0) { $v = $v.Substring(1, $end - 1) } else { $v = $v.Substring(1) }
    } else {
      $v = ($v -split '[\s#]', 2)[0]
    }
    $vars[$k] = $v
  }
  $vars
}

# Make the file readable by the current user only (the chmod 600 of zsh).
function _claudinho_private([string]$file) {
  icacls $file /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
}

function claudinho {
  $name = _claudinho_current
  if (-not $name) {
    _claudinho_err 'no active provider. Run: claudinho-switch <name>'
    claudinho-switch
    return
  }
  if (-not (_claudinho_valid $name)) { return }
  $file = _claudinho_file $name
  if (-not (Test-Path -LiteralPath $file)) { _claudinho_err "provider '$name' has no file at $file"; return }
  $bin = _claudinho_bin
  if (-not $bin) { return }

  $vars = _claudinho_read $file
  if (-not $vars['ANTHROPIC_AUTH_TOKEN']) { _claudinho_err "ANTHROPIC_AUTH_TOKEN is empty in $file"; return }

  # Flags: the provider file wins, then $env:CLAUDINHO_FLAGS, then the default.
  if ($vars.Contains('CLAUDINHO_FLAGS')) { $flagText = $vars['CLAUDINHO_FLAGS'] }
  elseif (Test-Path env:CLAUDINHO_FLAGS) { $flagText = $env:CLAUDINHO_FLAGS }
  else { $flagText = $null }
  if ($null -eq $flagText) { $flags = $script:ClaudinhoDefaultFlags }
  else { $flags = @($flagText -split '\s+' | Where-Object { $_ }) }

  # PowerShell has no subshell for a native command. Set the variables in
  # this process and restore them after Claude Code exits, so they never
  # stay in the calling shell.
  $names = @($vars.Keys) + @('ANTHROPIC_API_KEY', 'CLAUDINHO_FLAGS')
  $saved = @{}
  foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
  try {
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $null, 'Process')
    [Environment]::SetEnvironmentVariable('CLAUDINHO_FLAGS', $null, 'Process')
    foreach ($k in $vars.Keys) {
      if ($k -ne 'CLAUDINHO_FLAGS') { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process') }
    }
    & $bin @flags @args
  } finally {
    foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process') }
  }
}

function _claudinho_with([string]$provider, [object[]]$rest) {
  $old = $env:CLAUDINHO_PROVIDER
  $env:CLAUDINHO_PROVIDER = $provider
  try { claudinho @rest }
  finally { [Environment]::SetEnvironmentVariable('CLAUDINHO_PROVIDER', $old, 'Process') }
}

function codexinho { _claudinho_with 'cx' $args }
function grokinho { _claudinho_with 'grok' $args }

function claudinho-switch {
  $argv = @($args)
  $cmd = if ($argv.Count -gt 0) { [string]$argv[0] } else { '' }
  $dir = _claudinho_dir
  $current = _claudinho_current

  switch -CaseSensitive ($cmd) {
    { $_ -eq '' -or $_ -eq 'list' } {
      $names = _claudinho_names
      if ($names.Count -eq 0) {
        "no providers in $dir\providers. Run: claudinho-switch add <name>"
        return
      }
      foreach ($n in $names) {
        $v = _claudinho_read (_claudinho_file $n)
        $mark = if ($n -eq $current) { '*' } else { ' ' }
        $tok = if ($v['ANTHROPIC_AUTH_TOKEN']) { 'ok' } else { 'MISSING' }
        '{0} {1,-12} key:{2,-3} {3}  {4}' -f $mark, $n, $tok, $v['ANTHROPIC_BASE_URL'], $v['ANTHROPIC_MODEL']
      }
      return
    }
    'show' {
      if (-not $current) { _claudinho_err 'no active provider'; return }
      if (-not (_claudinho_valid $current)) { return }
      $f = _claudinho_file $current
      "# $f"
      Get-Content -LiteralPath $f | ForEach-Object {
        $_ -replace '^(\s*export\s+ANTHROPIC_AUTH_TOKEN=).*', '$1"<hidden>"'
      }
      return
    }
    'add' {
      $name = if ($argv.Count -gt 1) { [string]$argv[1] } else { '' }
      if (-not $name) { _claudinho_err 'usage: claudinho-switch add <name>'; return }
      if (-not (_claudinho_valid $name)) { return }
      $f = _claudinho_file $name
      if (Test-Path -LiteralPath $f) { _claudinho_err "$f already exists"; return }
      New-Item -ItemType Directory -Force -Path (Join-Path $dir 'providers') | Out-Null
      $template = if ($env:CLAUDINHO_TEMPLATE) { $env:CLAUDINHO_TEMPLATE } else { Join-Path $script:ClaudinhoRepo 'providers\template.env' }
      Copy-Item -LiteralPath $template -Destination $f
      _claudinho_private $f
      "created $f. Edit it, then: claudinho-switch $name"
      return
    }
    'bin' { _claudinho_bin; return }
    'dir' { $dir; return }
    default {
      $name = $cmd
      if (-not (_claudinho_valid $name)) { return }
      if (-not (Test-Path -LiteralPath (_claudinho_file $name))) {
        _claudinho_err "no provider '$name'. Known:"
        _claudinho_names | ForEach-Object { [Console]::Error.WriteLine($_) }
        return
      }
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      [IO.File]::WriteAllText((Join-Path $dir 'current'), "$name`n")
      "claudinho -> $name"
    }
  }
}
