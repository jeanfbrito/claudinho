# claudinho: Claude Code on a switchable model provider.
#
# Source this file from ~/.zshrc:
#   source /path/to/clone/claudinho.zsh   (install.sh adds this line)
#
# Commands:
#   claudinho [args]            run Claude Code on the active provider, with
#                               --dangerously-skip-permissions --chrome
#   claudinho-switch            show providers and which one is active
#   claudinho-switch <name>     make <name> the active provider
#   claudinho-switch show       print the active provider file
#   claudinho-switch add <name> create a provider file from the template
#   claudinho-switch bin|dir    paths in use
#
# Providers are files in ~/.config/claudinho/providers/<name>.env. Each one
# exports the ANTHROPIC_* and CLAUDE_CODE_* variables for that service.
# The active name is stored in ~/.config/claudinho/current.
# CLAUDINHO_PROVIDER=<name> claudinho   runs one provider without switching.
# `claude` itself is never touched.

CLAUDINHO_DIR="${CLAUDINHO_DIR:-$HOME/.config/claudinho}"
CLAUDINHO_DEFAULT_FLAGS=(--dangerously-skip-permissions --chrome)

_claudinho_bin() {
  emulate -L zsh
  local bin
  bin="$(whence -p claude 2>/dev/null)"
  if [[ -z "$bin" ]]; then
    echo "claudinho: cannot find the claude binary in PATH" >&2
    return 1
  fi
  printf '%s' "$bin"
}

_claudinho_current() {
  emulate -L zsh
  if [[ -n "$CLAUDINHO_PROVIDER" ]]; then
    printf '%s' "$CLAUDINHO_PROVIDER"
  elif [[ -r "$CLAUDINHO_DIR/current" ]]; then
    tr -d '[:space:]' < "$CLAUDINHO_DIR/current"
  fi
}

_claudinho_file() { emulate -L zsh; printf '%s' "$CLAUDINHO_DIR/providers/$1.env"; }

# A provider name is a file name: letters, digits, dot, dash, underscore.
_claudinho_valid() {
  emulate -L zsh
  if [[ ! "$1" =~ '^[A-Za-z0-9_-][A-Za-z0-9._-]*$' ]]; then
    echo "claudinho: bad provider name '$1'. Use letters, digits, '.', '-' or '_'." >&2
    return 1
  fi
}

_claudinho_names() {
  emulate -L zsh
  local f
  for f in "$CLAUDINHO_DIR"/providers/*.env(N); do
    printf '%s\n' "${${f:t}%.env}"
  done
}

claudinho() {
  emulate -L zsh
  local name file bin
  name="$(_claudinho_current)"
  if [[ -z "$name" ]]; then
    echo "claudinho: no active provider. Run: claudinho-switch <name>" >&2
    claudinho-switch >&2
    return 1
  fi
  _claudinho_valid "$name" || return 1
  file="$(_claudinho_file "$name")"
  if [[ ! -r "$file" ]]; then
    echo "claudinho: provider '$name' has no file at $file" >&2
    return 1
  fi
  bin="$(_claudinho_bin)" || return 1

  # Subshell: the provider's variables never reach the calling shell.
  (
    unset ANTHROPIC_API_KEY
    source "$file"
    if [[ -z "$ANTHROPIC_AUTH_TOKEN" ]]; then
      echo "claudinho: ANTHROPIC_AUTH_TOKEN is empty in $file" >&2
      exit 1
    fi
    local -a flags
    if [[ -n "${CLAUDINHO_FLAGS+x}" ]]; then flags=(${=CLAUDINHO_FLAGS}); else flags=("${CLAUDINHO_DEFAULT_FLAGS[@]}"); fi
    unset CLAUDINHO_FLAGS
    exec "$bin" "${flags[@]}" "$@"
  )
}

claudinho-switch() {
  emulate -L zsh
  local cmd="$1" name file current
  current="$(_claudinho_current)"
  case "$cmd" in
    ""|list)
      local -a names; names=($(_claudinho_names))
      local mark tok
      if (( ${#names} == 0 )); then
        echo "no providers in $CLAUDINHO_DIR/providers. Run: claudinho-switch add <name>"
        return 1
      fi
      for name in "${names[@]}"; do
        mark=" "; [[ "$name" == "$current" ]] && mark="*"
        # The path goes in as $1, so no quote in it can break the command.
        tok="$(zsh -fc 'source "$1"; printf %s "${ANTHROPIC_AUTH_TOKEN:+ok}"' _ "$(_claudinho_file "$name")")"
        printf '%s %-12s key:%-3s %s\n' "$mark" "$name" "${tok:-MISSING}" \
          "$(zsh -fc 'source "$1"; printf "%s  %s" "$ANTHROPIC_BASE_URL" "$ANTHROPIC_MODEL"' _ "$(_claudinho_file "$name")")"
      done
      ;;
    show)
      [[ -z "$current" ]] && { echo "no active provider" >&2; return 1; }
      _claudinho_valid "$current" || return 1
      echo "# $(_claudinho_file "$current")"
      sed -E 's/^(export ANTHROPIC_AUTH_TOKEN=).*/\1"<hidden>"/' "$(_claudinho_file "$current")"
      ;;
    add)
      name="$2"
      [[ -z "$name" ]] && { echo "usage: claudinho-switch add <name>" >&2; return 1; }
      _claudinho_valid "$name" || return 1
      file="$(_claudinho_file "$name")"
      [[ -e "$file" ]] && { echo "$file already exists" >&2; return 1; }
      mkdir -p "$CLAUDINHO_DIR/providers"
      cp "${CLAUDINHO_TEMPLATE:-${${(%):-%x}:A:h}/providers/template.env}" "$file"
      chmod 600 "$file"
      echo "created $file. Edit it, then: claudinho-switch $name"
      ;;
    bin)  _claudinho_bin; echo ;;
    dir)  echo "$CLAUDINHO_DIR" ;;
    *)
      name="$cmd"
      _claudinho_valid "$name" || return 1
      file="$(_claudinho_file "$name")"
      if [[ ! -r "$file" ]]; then
        echo "claudinho: no provider '$name'. Known:" >&2
        _claudinho_names >&2
        return 1
      fi
      mkdir -p "$CLAUDINHO_DIR"
      printf '%s\n' "$name" > "$CLAUDINHO_DIR/current"
      echo "claudinho -> $name"
      ;;
  esac
}
