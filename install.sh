#!/bin/zsh
# Wire claudinho into ~/.zshrc and set up ~/.config/claudinho.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
line="source \"$here/claudinho.zsh\""
rc="$HOME/.zshrc"
dir="$HOME/.config/claudinho"

if ! grep -qF "$line" "$rc" 2>/dev/null; then
  printf '\n# claudinho: Claude Code on a switchable model provider\n%s\n' "$line" >> "$rc"
  echo "added to $rc: $line"
else
  echo "already in $rc"
fi

mkdir -p "$dir/providers"
for f in "$here"/providers/*.env; do
  name="$(basename "$f")"
  [[ "$name" == template.env ]] && continue
  if [[ ! -f "$dir/providers/$name" ]]; then
    cp "$f" "$dir/providers/$name"; chmod 600 "$dir/providers/$name"
    echo "created $dir/providers/$name — put the API key there"
  fi
done
if [[ ! -f "$dir/current" ]]; then
  first="$(ls "$dir/providers" | head -1)"
  echo "${first%.env}" > "$dir/current"
  echo "active provider: ${first%.env}"
fi
echo "now run: source ~/.zshrc && claudinho-switch"
