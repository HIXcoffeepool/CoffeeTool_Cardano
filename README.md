# CoffeeTool (ctool) ☕️

**A Cardano stake pool operations tool (Japanese UI) built around air-gapped cold-key signing.**

[English](#english) ・ [日本語](#日本語)

Targets `cardano-cli 11.0.0.0` (Conway era). Every signing step is shown as a command to run on your **offline (air-gapped) machine**; unsigned/signed transactions move between the block producer and the air-gap by **copy-pasting `cat > file << EOF` heredocs**.

> ⚠️ Provided **as-is** under the MIT License. It handles **mainnet funds and keys** — always test on a testnet or with small amounts first, and review every command before you run it.

---

## English

### Features
- **Cold keys never touch the hot environment.** Signing commands are displayed for you to run on the air-gapped machine.
- **Copy-paste round-trip workflow.** `tx.raw` (BP → air-gap) and `tx.signed` / `vote.json` (air-gap → BP) transfer via heredoc. Every operation uses the same `tx.raw` / `tx.signed` names (one operation at a time), so files are never mixed up.
- **Pre-submit safety checks.** Verifies the signed tx is actually witnessed and that its inputs are still live before submitting; prints the Tx ID on success.
- **Operations:** pool funds (send / withdraw rewards), pool config check, KES rotation, pool info update, DRep delegation, governance voting.

### Quick start
```bash
git clone git@github.com:HIXcoffeepool/ctool.git
cd ctool
cp env.sample env      # edit NODE_HOME / COLDKEYS_DIR / NETWORK ...
chmod +x ctool.sh
./ctool.sh
```
`env` is your personal config and is git-ignored — copy `env.sample` to `env` and edit it. Full UI/behavior spec is in [FUNCTIONS.md](./FUNCTIONS.md) (Japanese).

### Requirements
Runs on the block-producing node; cold keys stay in `~/cold-keys/` on the air-gapped machine; `cardano-cli` and `jq` available; `CARDANO_NODE_SOCKET_PATH` pointing at a fully synced node.

---

## 日本語

Cardano ステークプールオペレーター（SPO）向けの運用補助ツール。日本語UIで、**エアギャップ（コールド環境）を前提としたコールドキー運用**に対応しています。`cardano-cli 11.0.0.0`（Conway era）対応。

---

## 特徴

- **コールドキーは一切ホット環境に置かない設計** — 署名が必要な操作は、エアギャップで実行するコマンドをそのまま画面に表示します。
- **コピペで完結する往復ワークフロー** — 未署名tx（`tx.raw`）はBP→エアギャップ、署名済みファイル（`tx.signed` / 投票の `vote.json`）はエアギャップ→BP を、いずれも `cat > file << EOF` 形式のヒアドキュメントでコピペ転送できます。全操作で `tx.raw` / `tx.signed` の名前に統一されており、ファイルを取り違えません（1操作ずつ完結）。
- **送信前の安全チェック** — 送信直前に署名済みtxの入力が現在のライブUTxOに存在するか検証し、古い未署名txに署名していた場合は送信前に停止します。
- **主な機能**: プール資金の管理 / プール設定の確認 / KESの更新 / プール情報の更新 / DRepへの委任 / ガバナンス投票

詳細な機能・UI仕様は [FUNCTIONS.md](./FUNCTIONS.md) を参照してください。

---

## 前提

- ブロック生成ノード（BP）上で動作します。
- コールドキー（`node.skey` など）はエアギャップマシンの `~/cold-keys/` に保管されている前提です。
- `cardano-cli` / `jq` が利用可能であること。
- `CARDANO_NODE_SOCKET_PATH` が同期済みノードを指していること。

---

## セットアップ

```bash
git clone <this-repo-url>
cd ctool
cp env.sample env      # 環境設定をコピーして編集
nano env               # NODE_HOME / COLDKEYS_DIR / NETWORK などを自分の環境に合わせる
chmod +x ctool.sh
./ctool.sh
```

`env` は **各自の環境設定ファイル**で、`.gitignore` により公開対象から除外されています。テンプレートの `env.sample` を `env` にコピーして編集してください。

### 主な設定項目（env.sample）

| 変数 | 説明 |
|---|---|
| `NODE_HOME` | ノードのデータ・鍵ファイルが置かれるディレクトリ |
| `COLDKEYS_DIR` | コールドキーの保管先（エアギャップ上のパス表記に使用） |
| `NETWORK` | `--mainnet` またはテストネットの magic |
| `RELAY1_IP` | プール情報更新時に使うリレーノードのIP |
| `POOL_PORT` | リレーノードのポート |

---

## エアギャップ運用の流れ（例: ガバナンス投票）

1. **BP**: 提案を選び、投票内容（Yes/No/Abstain）を決める。
2. **エアギャップ**: 表示された `vote create` コマンドを実行し、`vote.json` を生成 → 出力（`cat > vote.json << EOF …`）をコピーして BP に貼り付け。
3. **BP**: tx をビルド → 表示された `cat > tx.raw << EOF …` をコピー。
4. **エアギャップ**: それを貼り付けて `tx.raw` を作成 → 表示された署名コマンドで署名 → `cat > tx.signed << EOF …` をコピー。
5. **BP**: 貼り付けて取り込み → 送信前の安全チェック（未署名検出・入力ライブ性）→ 送信 → Tx ID 表示。

---

## 免責・注意

- 本ツールは cardano-cli の公式コマンドを組み立てて表示・実行するラッパーです。表示されるコマンドは**実行前に必ず内容を確認**してください。
- 鍵・アドレス・`env` などの個人情報はリポジトリに含まれていません（`.gitignore` で除外）。
- バグ報告・改善提案は Issue / PR で歓迎します。

## ライセンス

[MIT](./LICENSE)
