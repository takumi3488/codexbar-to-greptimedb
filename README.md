# codexbar-to-greptimedb

[日本語 README](README.ja.md)

`codexbar-to-greptimedb` exports usage and credit snapshots from your configured CodexBar providers to GreptimeDB.

## Requirements

- A GreptimeDB instance with the HTTP SQL API enabled
- CodexBar configured for the providers you want to export
- One of the supported installation targets:
  - Homebrew: macOS Sonoma (14) or later, Apple Silicon or Intel
  - Release installer: macOS arm64 / x86_64 or Linux x86_64

Linux release binaries require `curl` (for `libcurl`) and `libsqlite3` at runtime.

## Install

### Homebrew (macOS)

```sh
brew install smartcrabai/tap/codexbar-to-greptimedb
```

### Release installer

Install the latest release to `$HOME/.local/bin`:

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh | sh
```

If `$HOME/.local/bin` is not already on your `PATH`, add it in your shell startup file. For the current shell:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Pin an installation to a version or choose a different destination by downloading the installer:

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh \
  -o install.sh

# Inspect install.sh before running it.
sh install.sh --version 0.1.0 --install-dir "$HOME/.local/bin"
```

## Configure CodexBar

When `--provider` is omitted, the exporter uses the providers enabled in your CodexBar configuration. It reads the same configuration locations as CodexBar, in this order:

1. `CODEXBAR_CONFIG`
2. `XDG_CONFIG_HOME/codexbar/config.json`
3. `~/.config/codexbar/config.json`
4. `~/.codexbar/config.json`

`--source` or `CODEXBAR_SOURCE` overrides the source configured for a provider. Otherwise the configured source, or `auto`, is used.

## Export Usage

Set the GreptimeDB connection details, then run the exporter. One-shot export is the default.

```sh
export GREPTIMEDB_URL='https://<greptime-host>'
export GREPTIMEDB_USERNAME='<username>'
export GREPTIMEDB_PASSWORD='<password>'

codexbar-to-greptimedb --provider claude
```

Set both `GREPTIMEDB_USERNAME` and `GREPTIMEDB_PASSWORD` to use HTTP Basic authentication. Prefer environment variables to `--password` so secrets do not enter shell history.

Provider examples:

```sh
# Providers enabled in CodexBar configuration
codexbar-to-greptimedb

# Codex and Claude
codexbar-to-greptimedb --provider both

# Every registered provider
codexbar-to-greptimedb --provider all

# Force Codex's CLI source
codexbar-to-greptimedb --provider codex --source cli
```

## Run Every Minute

Run continuously in the foreground:

```sh
codexbar-to-greptimedb --every-minute
```

`--once` forces one-shot behavior even when an interval is configured. During periodic operation, transient CodexBar or GreptimeDB failures are written to standard error and retried at the next interval; one-shot operation exits nonzero on failure.

### Homebrew service

The Homebrew formula creates `$(brew --prefix)/etc/codexbar-to-greptimedb.env` with `GREPTIMEDB_URL=http://localhost:4000`. It preserves the file across upgrades and enforces mode `0600` because it can contain credentials.

```sh
nano "$(brew --prefix)/etc/codexbar-to-greptimedb.env"
```

For example:

```sh
GREPTIMEDB_URL='https://<greptime-host>'
GREPTIMEDB_USERNAME='<username>'
GREPTIMEDB_PASSWORD='<password>'
```

Start the background service. It reads this file and runs the enabled CodexBar providers with `--every-minute`.

```sh
brew services start smartcrabai/tap/codexbar-to-greptimedb
```

Restart it after changing the configuration:

```sh
brew services restart smartcrabai/tap/codexbar-to-greptimedb
```

## Options and Environment Variables

| CLI option | Environment variable | Default | Description |
| --- | --- | --- | --- |
| `--greptime-url URL` | `GREPTIMEDB_URL` | Required | GreptimeDB HTTP base URL |
| `--database NAME` | `GREPTIMEDB_DATABASE` | `public` | Target database |
| `--table NAME` | `GREPTIMEDB_TABLE` | `llm_usage_snapshots` | Target table |
| `--username NAME` | `GREPTIMEDB_USERNAME` | None | HTTP Basic username |
| `--password VALUE` | `GREPTIMEDB_PASSWORD` | None | HTTP Basic password |
| `--provider ID` | `CODEXBAR_PROVIDER` | Enabled CodexBar providers | A provider ID, alias, `both`, or `all` |
| `--source SOURCE` | `CODEXBAR_SOURCE` | Configured source or `auto` | `auto`, `web`, `cli`, `oauth`, or `api` |
| `--interval-seconds N` | `CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS` | One-shot | Run every positive `N` seconds |
| `--watch`, `--every-minute` | None | None | Run every 60 seconds |
| `--once` | None | None | Force one-shot behavior |

CLI options override their equivalent environment variables. `--database` and `--table` must be simple SQL identifiers: they begin with a letter or `_` and contain only letters, numbers, and `_`.

## Stored Data

On the first write, the exporter creates the target table with `append_mode=true` through GreptimeDB's HTTP SQL API.

| Column | Type | Description |
| --- | --- | --- |
| `ts` | `TIMESTAMP(3)` | Export capture time; the time index |
| `provider`, `provider_source`, `account_key`, `usage_window` | `STRING` | Time-series tags |
| `account_email`, `account_organization` | `STRING` | Account identity returned by CodexBar |
| `used_percent`, `window_minutes`, `resets_at` | Numeric and timestamp | Usage-window values |
| `usage_updated_at`, `credits_remaining` | Timestamp and numeric | Source update time and available credits |

Each provider and account receives a `usage_window = 'snapshot'` row. Standard `primary`, `secondary`, and `tertiary` windows are stored as separate rows; additional windows use `usage_window = 'extra:<id>'`.

Example query:

```sql
SELECT
  ts, provider, provider_source, account_email, usage_window,
  used_percent, window_minutes, resets_at, credits_remaining
FROM llm_usage_snapshots
ORDER BY ts DESC
LIMIT 100;
```
