# codexbar-to-greptimedb

[English README](README.md)

`codexbar-to-greptimedb` は [CodexBar](https://github.com/steipete/CodexBar) の公開 Swift ライブラリ **`CodexBarCore`** を直接利用し、LLM 利用状況を GreptimeDB に時系列スナップショットとして保存する CLI です。

`codexbar` 実行ファイルを子プロセスとして起動しません。CodexBar の provider descriptor、設定ファイル、認証ソース、active token account を同一プロセスで解決し、型付き `UsageSnapshot` / `CreditsSnapshot` を保存します。

## 前提条件

- ソースビルドには macOS 14+ と Swift 6.3+、または Linux と Swift 6.2+ が必要です。
- 配布済みバイナリは `macos-x86_64`、`macos-arm64`、`linux-x86_64` に対応します。
- Linux バイナリは Ubuntu 24.04 を基準（`glibc` 2.39+）にビルドされ、実行時には `curl`（`libcurl` を提供）と `libsqlite3` が必要です。
- HTTP SQL API を有効にした GreptimeDB
- 対象プロバイダーを設定済みの CodexBar config

SwiftPM は CodexBar `v0.42.1` の署名済み commit `3e05988f5c5fc1dff70c7a58bd659208cf34c840` を固定しています。CodexBar は `0.x` 系のため、意図しない Core API 変更を取り込まないよう `main` は追従しません。

ソースから release バイナリをビルドします。

```sh
swift build -c release
```

実行ファイルは `.build/release/codexbar-to-greptimedb` です。

## リリース版のインストール

最新版を `$HOME/.local/bin` へインストールします。

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh | sh
```

インストーラーは OS と CPU に対応するアーカイブを選択し、同梱する SHA-256 チェックサムをダウンロードして検証後、実行ファイルを atomic に置き換えます。`curl`、`tar`、`awk`、`install`、`mktemp`、および `sha256sum` または `shasum` が必要です。

特定バージョンを指定します。

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh \
  | CODEXBAR_TO_GREPTIMEDB_VERSION=0.1.0 sh
```

インストール先を指定します。

```sh
curl --fail --location --silent --show-error \
  https://raw.githubusercontent.com/takumi3488/codexbar-to-greptimedb/main/install.sh \
  | CODEXBAR_TO_GREPTIMEDB_INSTALL_DIR=/usr/local/bin sh
```

監査可能な手順が必要な場合は、インストーラーを先にダウンロードして内容を確認してから `sh install.sh` を実行してください。同じ指定は `--version` と `--install-dir` でも使えます。

### リリースの公開

バージョンタグを push すると GitHub Release を作成します。

```sh
git tag v0.1.0
git push origin v0.1.0
```

`.github/workflows/release-cli.yml` は unit test を実行後、各対象 OS/CPU の GitHub-hosted runner で 3 種類のアーカイブをビルドします。Linux バイナリには `--static-swift-stdlib` を使用し、Ubuntu 24.04 のクリーンなコンテナでインストーラーの実行時前提を満たした状態でスモークテストします。すべてのチェックサムを検証し、draft Release を作成または再利用して全 asset の upload に成功した場合だけ公開します。

## CodexBar 設定の解決

`CodexBarConfigStore` を用いて CodexBar 本体と同じ設定ファイルを読みます。

1. `CODEXBAR_CONFIG`
2. `XDG_CONFIG_HOME/codexbar/config.json`
3. `~/.config/codexbar/config.json`
4. 既存の `~/.codexbar/config.json`

設定から次を反映します。

- 有効プロバイダー一覧（`--provider` 未指定時）
- provider ごとの取得元 `source`
- API key・secret・workspace 等の環境変数への投影
- manual cookie と cookie source
- token account の active index。選択アカウントを `ProviderFetchContext.selectedTokenAccountID` と provider 環境へ反映

`--source` / `CODEXBAR_SOURCE` は設定値より優先し、未指定なら provider config の `source`、さらに未指定なら `auto` を使います。

## 使い方

### 一回だけ保存する（既定）

```sh
export GREPTIMEDB_URL='https://<greptime-host>'
export GREPTIMEDB_USERNAME='<username>'
export GREPTIMEDB_PASSWORD='<password>'

.build/release/codexbar-to-greptimedb --provider claude
```

資格情報を渡さない場合、HTTP Basic 認証ヘッダーなしで GreptimeDB に接続します。Basic 認証を使う場合はユーザー名とパスワードを必ず両方指定してください。秘密値がシェル履歴に残るため、`--password` より環境変数を推奨します。

`--provider` の例:

```sh
# CodexBar config で有効な provider 全部
.build/release/codexbar-to-greptimedb

# Codex と Claude
.build/release/codexbar-to-greptimedb --provider both

# 全登録 provider
.build/release/codexbar-to-greptimedb --provider all

# Codex の CLI source を明示
.build/release/codexbar-to-greptimedb --provider codex --source cli
```

### 毎分保存する

```sh
.build/release/codexbar-to-greptimedb --provider all --every-minute
```

または、プロセスマネージャーから環境変数で指定します。

```sh
CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS=60 \
GREPTIMEDB_URL='http://localhost:4000' \
.build/release/codexbar-to-greptimedb
```

`--once` は、間隔を指定する環境変数があっても one-shot を強制します。定期実行中の一時的な CodexBarCore/GreptimeDB エラーは標準エラーへ出し、次の周期で再試行します。一回実行時は非 0 で終了します。

## オプションと環境変数

| CLI オプション | 環境変数 | 既定値 | 説明 |
| --- | --- | --- | --- |
| `--greptime-url URL` | `GREPTIMEDB_URL` | なし（必須） | GreptimeDB の HTTP ベース URL |
| `--database NAME` | `GREPTIMEDB_DATABASE` | `public` | 保存先データベース |
| `--table NAME` | `GREPTIMEDB_TABLE` | `llm_usage_snapshots` | 保存先テーブル |
| `--username NAME` | `GREPTIMEDB_USERNAME` | なし | HTTP Basic ユーザー名 |
| `--password VALUE` | `GREPTIMEDB_PASSWORD` | なし | HTTP Basic パスワード |
| `--provider ID` | `CODEXBAR_PROVIDER` | CodexBar config の有効 provider | `UsageProvider` ID、CLI alias、`both`、または `all` |
| `--source SOURCE` | `CODEXBAR_SOURCE` | config の `source` または `auto` | `auto` / `web` / `cli` / `oauth` / `api` |
| `--interval-seconds N` | `CODEXBAR_TO_GREPTIMEDB_INTERVAL_SECONDS` | one-shot | `N > 0` 秒ごとの継続実行 |
| `--watch`, `--every-minute` | — | — | 60 秒ごとの継続実行 |
| `--once` | — | — | 強制的に一回だけ実行 |

CLI オプションは同名の環境変数より優先します。`--database` と `--table` は SQL 識別子（英字または `_` で開始し、英数字と `_` のみ）に制限されます。

## 保存スキーマ

初回実行時に、指定テーブルを `append_mode=true` で自動作成します。GreptimeDB の HTTP SQL API (`POST /v1/sql?db=...`) を使います。

| 列 | 型 | 内容 |
| --- | --- | --- |
| `ts` | `TIMESTAMP(3)` | エクスポータの取得時刻。time index |
| `provider`, `provider_source`, `account_key`, `usage_window` | `STRING` | 時系列タグ。`account_key` は identity のメール、未取得時は active token account の非空ラベル、さらに未取得時は `__default__` |
| `account_email`, `account_organization` | `STRING` | `UsageSnapshot.identity` が返したアカウント情報のみ。token account ラベルは入れない |
| `used_percent`, `window_minutes`, `resets_at` | 数値・時刻 | 使用枠の利用率・期間・リセット時刻 |
| `usage_updated_at`, `credits_remaining` | 時刻・数値 | CodexBarCore の更新時刻とクレジット残高 |

各プロバイダー・アカウントには必ず `usage_window = 'snapshot'` 行を一件保存します。これはクレジット残高のみを返す provider を欠落させないためです。通常の `primary` / `secondary` / `tertiary` に加え、Core の `extraRateWindows` は `usage_window = 'extra:<id>'` として同じテーブルへ保存します。

確認例:

```sql
SELECT
  ts, provider, provider_source, account_email, usage_window,
  used_percent, window_minutes, resets_at, credits_remaining
FROM llm_usage_snapshots
ORDER BY ts DESC
LIMIT 100;
```

## ローカル GreptimeDB E2E

GreptimeDB の公式イメージでローカル検証できます。

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

`.github/workflows/ci.yml` は PR と `main` への push で、次の独立ジョブを並列実行します。

- **Format**: `swift format lint --strict`
- **Lint**: SwiftLint `0.65.0` と warnings-as-errors build
- **Unit tests**: `swift test`
- **GreptimeDB E2E**: 固定 digest の `greptime/greptimedb` コンテナに、認証不要の合成 `ExportSnapshot` を INSERT / SELECT

Linux job は CodexBarCore の SQLite 依存のため、`libsqlite3-dev` を明示的に導入します。E2E は利用者の CodexBar config、API key、LLM provider 認証を使用しません。

## 検証

```sh
swift test
```

テストは CodexBarCore の primary/secondary/extra window 変換、credits-only provider の summary 行、設定の優先順位、SQL の列順・エスケープ・ミリ秒タイムスタンプを検証します。
