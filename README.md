# codexbar-to-greptimedb

[Japanese README](README.ja.md)

`codexbar-to-greptimedb` is a Swift CLI that uses CodexBar's public `CodexBarCore` library to persist LLM usage snapshots in GreptimeDB.

It does not launch the `codexbar` executable as a child process. The CLI resolves CodexBar provider descriptors, configuration, credential sources, and the active token account in process, then writes typed `UsageSnapshot` and `CreditsSnapshot` values to GreptimeDB.

## Requirements

- Source builds require Swift 6.2+ on macOS 14+ or Linux.
- Prebuilt releases support `macos-x86_64`, `macos-arm64`, `linux-x86_64`, and `linux-arm64`.
- Linux releases target the Ubuntu 22.04 baseline (`glibc` 2.35+) and require `curl` (which provides `libcurl`) and `libsqlite3` at runtime.
- A GreptimeDB instance with the HTTP SQL API enabled
- CodexBar configuration for the providers to fetch

The Swift package pins CodexBar v0.42.1 at signed commit `3e05988f5c5fc1dff70c7a58bd659208cf34c840`. CodexBar is currently a 0.x dependency, so this project intentionally does not track its `main` branch.

Build the release binary from source:

```sh
swift build -c release
```

The binary is available at `.build/release/codexbar-to-greptimedb`.

## Install a Release

Install the latest release to `$HOME/.local/bin`:

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh | sh
```

The installer selects the native release archive, downloads its adjacent SHA-256 checksum, verifies it, then atomically replaces the executable. It requires `curl`, `tar`, `awk`, `install`, `mktemp`, and either `sha256sum` or `shasum`.

Pin an installation to a release version:

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh \
  | CODEXBAR_TO_GREPTIMEDB_VERSION=0.1.0 sh
```

Install to a different directory:

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh \
  | CODEXBAR_TO_GREPTIMEDB_INSTALL_DIR=/usr/local/bin sh
```

For reviewable installation, download the installer first and inspect it before running `sh install.sh`. The same options are available as `--version` and `--install-dir`.

### Publishing a Release

Push a version tag to create a GitHub Release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

`.github/workflows/release-cli.yml` runs unit tests and builds the four native archives on matching GitHub-hosted runners. Linux binaries use `--static-swift-stdlib` and are smoke-tested in a clean Ubuntu 22.04 container with the installer runtime prerequisites. The workflow verifies every checksum, creates or resumes a draft release, uploads every asset, and publishes the release only after all uploads succeed.

## CodexBar Configuration Resolution

The application uses `CodexBarConfigStore` and resolves the same configuration locations as CodexBar:

1. `CODEXBAR_CONFIG`
2. `XDG_CONFIG_HOME/codexbar/config.json`
3. `~/.config/codexbar/config.json`
4. Existing `~/.codexbar/config.json`

It applies the following configuration data:

- Enabled providers when `--provider` is omitted
- Per-provider `source`
- API keys, secrets, workspace settings, and provider environment overrides
- Manual cookie headers and cookie sources
- The active token account through `clampedActiveIndex()` and `ProviderFetchContext.selectedTokenAccountID`

`--source` and `CODEXBAR_SOURCE` override the source configured by CodexBar. If neither is set, the provider uses `auto`.

## Usage

### One-shot Export

One-shot export is the default behavior.

```sh
export GREPTIMEDB_URL='https://<greptime-host>'
export GREPTIMEDB_USERNAME='<username>'
export GREPTIMEDB_PASSWORD='<password>'

.build/release/codexbar-to-greptimedb --provider claude
```

When both `GREPTIMEDB_USERNAME` and `GREPTIMEDB_PASSWORD` are set, the application sends HTTP Basic authentication. Prefer environment variables to `--password` so secrets do not enter shell history.

Provider selection examples:

```sh
# Providers enabled in CodexBar configuration
.build/release/codexbar-to-greptimedb

# Codex and Claude
.build/release/codexbar-to-greptimedb --provider both

# Every registered provider
.build/release/codexbar-to-greptimedb --provider all

# Force Codex's CLI source
.build/release/codexbar-to-greptimedb --provider codex --source cli
```

### Periodic Export

Run every minute:

```sh
.build/release/codexbar-to-greptimedb --provider all --every-minute
```

Or configure the interval through the environment:

```sh
CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS=60 \
GREPTIMEDB_URL='http://localhost:4000' \
.build/release/codexbar-to-greptimedb
```

`--once` forces one-shot behavior even when an interval environment variable is set. In periodic mode, transient CodexBarCore or GreptimeDB failures are written to standard error and retried on the next interval. One-shot mode exits nonzero on failure.

## Options and Environment Variables

| CLI option | Environment variable | Default | Description |
| --- | --- | --- | --- |
| `--greptime-url URL` | `GREPTIMEDB_URL` | Required | GreptimeDB HTTP base URL |
| `--database NAME` | `GREPTIMEDB_DATABASE` | `public` | Target database |
| `--table NAME` | `GREPTIMEDB_TABLE` | `llm_usage_snapshots` | Target table |
| `--username NAME` | `GREPTIMEDB_USERNAME` | None | HTTP Basic username |
| `--password VALUE` | `GREPTIMEDB_PASSWORD` | None | HTTP Basic password |
| `--provider ID` | `CODEXBAR_PROVIDER` | Enabled CodexBar providers | A `UsageProvider` ID, CLI alias, `both`, or `all` |
| `--source SOURCE` | `CODEXBAR_SOURCE` | Configured source or `auto` | `auto`, `web`, `cli`, `oauth`, or `api` |
| `--interval-seconds N` | `CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS` | One-shot | Run every positive `N` seconds |
| `--watch`, `--every-minute` | None | None | Run every 60 seconds |
| `--once` | None | None | Force one-shot behavior |

CLI options override their equivalent environment variables. `--database` and `--table` must be simple SQL identifiers: they begin with a letter or `_` and contain only letters, numbers, and `_`.

## Storage Schema

On the first write, the application creates the target table with `append_mode=true` through GreptimeDB's HTTP SQL API at `POST /v1/sql?db=...`.

| Column | Type | Description |
| --- | --- | --- |
| `ts` | `TIMESTAMP(3)` | Export capture time; the time index |
| `provider`, `provider_source`, `account_key`, `usage_window` | `STRING` | Time-series tags. `account_key` is the Core identity email, then a nonempty active-token-account label, then `__default__` |
| `account_email`, `account_organization` | `STRING` | Fields returned by `UsageSnapshot.identity` only; token-account labels are not written here |
| `used_percent`, `window_minutes`, `resets_at` | Numeric and timestamp | Usage percentage, duration, and reset time for a quota window |
| `usage_updated_at`, `credits_remaining` | Timestamp and numeric | CodexBarCore update time and available credits |

Every provider and account receives a `usage_window = 'snapshot'` row. This preserves providers that only report credits. Standard `primary`, `secondary`, and `tertiary` windows are added as separate rows. Core `extraRateWindows` are stored in the same table as `usage_window = 'extra:<id>'`.

Example query:

```sql
SELECT
  ts, provider, provider_source, account_email, usage_window,
  used_percent, window_minutes, resets_at, credits_remaining
FROM llm_usage_snapshots
ORDER BY ts DESC
LIMIT 100;
```

## Local GreptimeDB E2E

Start an isolated GreptimeDB container:

```sh
docker run -d --rm \
  --name codexbar-to-greptimedb-e2e \
  -p 127.0.0.1:14000:4000 \
  greptime/greptimedb:latest \
  standalone start --http-addr 0.0.0.0:4000

swift run codexbar-to-greptimedb \
  --greptime-url http://127.0.0.1:14000 \
  --table codexbar_e2e_usage \
  --provider codex --source cli

curl -sS -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'sql=SELECT provider, provider_source, usage_window, used_percent FROM codexbar_e2e_usage' \
  'http://127.0.0.1:14000/v1/sql?db=public'

docker stop codexbar-to-greptimedb-e2e
```

## CI

`.github/workflows/ci.yml` runs the following independent jobs in parallel for pull requests and pushes to `main`:

- **Format**: `swift format lint --strict`
- **Lint**: SwiftLint 0.65.0 and a warnings-as-errors build
- **Unit tests**: `swift test`
- **GreptimeDB E2E**: Insert and select a synthetic `ExportSnapshot` in a pinned GreptimeDB container

Linux jobs install `libsqlite3-dev` because CodexBarCore links SQLite. The E2E test does not use CodexBar configuration, provider credentials, API keys, or cookies.

## Verification

```sh
swift test
```

The test suite covers CodexBarCore primary, secondary, and extra-window mapping; credits-only summary rows; active-account key fallback; configuration precedence; SQL escaping and column order; and the opt-in GreptimeDB integration contract.
