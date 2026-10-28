# claudinho

Claude Code on a switchable model provider. `claudinho` starts Claude Code
with `--dangerously-skip-permissions --chrome` on whichever provider is
active. `claudinho-switch` changes the provider.
Plain `claude` is never touched.

```sh
claudinho-switch          # list providers, * marks the active one
claudinho-switch cx       # make cx active
claudinho                 # run Claude Code on cx
claudinho-switch <name>   # make another provider active
claudinho                 # same command, now on that provider
```

The repo ships one provider, `cx`. Add others with `claudinho-switch add`.

## Files

| Path | Purpose |
| --- | --- |
| `claudinho.zsh` | The `claudinho` and `claudinho-switch` functions. Sourced from `~/.zshrc`. |
| `providers/cx.env` | Provider for the local cx proxy with the GPT-6 and GPT-6.1 models. |
| `providers/template.env` | Starting point for a new provider. |
| `install.sh` | Adds the `source` line to `~/.zshrc` and seeds `~/.config/claudinho`. |

Runtime state lives outside the repo:

| Path | Purpose |
| --- | --- |
| `~/.config/claudinho/providers/<name>.env` | One file per provider, mode 600, with its API key. |
| `~/.config/claudinho/current` | Name of the active provider. |

## Install

1. Clone the repo and run `install.sh` from the clone. It appends one
   `source` line to `~/.zshrc`, copies each provider from `providers/` that
   does not exist yet, and makes the first one active.
2. Put the API key in `~/.config/claudinho/providers/cx.env` on the
   `ANTHROPIC_AUTH_TOKEN` line.
3. Open a new shell, or run `source ~/.zshrc`.
4. Run `claudinho-switch`. The active provider shows `key:ok`.

## Commands

| Command | Effect |
| --- | --- |
| `claudinho [args]` | Run Claude Code on the active provider. Arguments pass through. |
| `claudinho-switch` | List providers with key state, URL and default model. |
| `claudinho-switch <name>` | Make `<name>` active. Persists across shells. |
| `claudinho-switch show` | Print the active provider file with the token hidden. |
| `claudinho-switch add <name>` | Create `<name>.env` from the template, mode 600. |
| `claudinho-switch bin` | Path of the real `claude` binary. |
| `claudinho-switch dir` | Path of the config folder. |

To run one provider once without switching:

```sh
CLAUDINHO_PROVIDER=<name> claudinho
```

## Provider files

A provider file is a list of plain `export` lines. `claudinho` sources it
in a subshell right before it starts Claude Code, so the variables exist
only for that run and never reach your shell. The usual contents:

| Variable | Meaning |
| --- | --- |
| `ANTHROPIC_BASE_URL` | The service's Anthropic-compatible endpoint. |
| `ANTHROPIC_AUTH_TOKEN` | The API key. Required. |
| `ANTHROPIC_MODEL` | Session default model. |
| `ANTHROPIC_DEFAULT_OPUS_MODEL`, `_SONNET_MODEL`, `_HAIKU_MODEL`, `_FABLE_MODEL` | Model for each `/model` alias. Haiku also covers background calls. |
| `ANTHROPIC_SMALL_FAST_MODEL` | Fallback for older Claude Code builds. Set to the haiku value. |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | Real window of the model, for models above 200K. |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Compact at this size, for cost or gateway limits. |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` stops telemetry, error reports, update and fast mode checks for the run. |
| `CLAUDINHO_FLAGS` | Replaces the default `--dangerously-skip-permissions --chrome`. Set to `""` for no flags. |

### Add a provider

```sh
claudinho-switch add <name>
$EDITOR ~/.config/claudinho/providers/<name>.env
claudinho-switch <name>
claudinho
```

Fill in the URL, key and models from the service's docs. Nothing else in
the repo changes.

### The cx provider

`cx` points to a local Anthropic-compatible proxy at
`http://localhost:20128` that serves the OpenAI GPT-6 and GPT-6.1 Codex
models. Change the URL and key if your proxy is somewhere else. A model id
is `cx/gpt-<version>-<tier>-<effort>`, for example `cx/gpt-6.1-sol-high`.
The tiers are Astra, Sol, Terra and Luna, from strongest to cheapest. The
effort suffix is `low`, `medium`, `high`, `xhigh`, `max` or `ultra`.
The proxy rejects an unknown suffix with a catalog error.

| Slot | Model |
| --- | --- |
| Session default | `cx/gpt-6.1-sol-high` |
| opus | `cx/gpt-6.1-sol-xhigh` |
| fable | `cx/gpt-6-astra-high` |
| sonnet | `cx/gpt-6.1-terra-medium` |
| haiku and background | `cx/gpt-6-luna-low` |

Sol is the coding default at a fifth of Astra's price. So the opus slot
stays on Sol at `xhigh`, and only the fable slot escalates to Astra. Luna
is 20 times cheaper than Sol and handles background calls. Terra costs half
of Sol, so the sonnet slot, which runs most subagents, uses Terra.

Sol and Terra have 6.1 versions, so their slots use 6.1. Astra and Luna
have no 6.1 version yet, so they stay on 6.

The file also sets the window to 1M tokens. All four models have about
1.05M, and the proxy accepted a 260K-token request in a test.
Auto-compact runs at 270K, because OpenAI bills input above 272K at a
higher rate. Non-essential traffic is off, so a GPT-6 session sends
nothing to Anthropic. Updates still happen when plain `claude` runs.

## How it works

`claudinho` reads the active name from `~/.config/claudinho/current`, or
from `CLAUDINHO_PROVIDER` when set. It finds the real `claude` binary with
`whence -p`, which skips aliases and functions. Then it opens a subshell,
unsets `ANTHROPIC_API_KEY`, sources the provider file, and `exec`s Claude
Code with the flags. When Claude Code exits, the subshell ends and the
variables are gone.

## Troubleshooting

**`command not found: claudinho`**
The file is not sourced in this shell. Run `source ~/.zshrc`.

**`no active provider`**
Run `claudinho-switch <name>` with one of the listed names.

**`ANTHROPIC_AUTH_TOKEN is empty`**
Put the key in the provider file named in the message.

**`cannot find the claude binary in PATH`**
Claude Code is not installed, or its folder is not in `PATH`.

**Connection or authentication errors**
Check the URL and key in the provider file. `claudinho-switch show` prints
the active file with the token hidden.

## Check without spending tokens

Put a stub `claude` script first in `PATH` and run `claudinho`. The stub
prints the flags and environment it received:

```sh
mkdir -p /tmp/stub && cat > /tmp/stub/claude <<'STUB'
#!/bin/sh
echo "args: $*"; env | grep -E '^(ANTHROPIC_|CLAUDE_CODE_)' | sort
STUB
chmod +x /tmp/stub/claude
PATH=/tmp/stub:$PATH claudinho
```
