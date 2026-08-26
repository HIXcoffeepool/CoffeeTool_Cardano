# CoffeeTool (ctool) — 機能・UI 設計仕様

作成日: 2026-04-24

---

## 基本情報

| 項目 | 内容 |
|------|------|
| 正式名称 | CoffeeTool |
| 略称 | ctool |
| 起動コマンド | `ctool` |
| 対象サーバー | **BP 専用**（リレーでは起動しない） |
| 配置場所 | `$NODE_HOME/scripts/ctool.sh` |
| エイリアス | `alias ctool='cd $NODE_HOME/scripts && ./ctool.sh'` |

---

## UI デザイン方針

### 基本ルール
- 外部ツール依存なし（シェル装飾のみ）
- 罫線文字（`╔ ║ ╚ ═ ┌ │ └ ─ ├ ┤`）でボックスを構成
- カラーはANSIカラーコードのみ使用
- コーヒーブランドに合わせた落ち着いた配色

### カラーパレット

| 用途 | カラー | ANSI |
|------|--------|------|
| ヘッダー・強調 | イエロー（琥珀色に近い） | `\e[33m` |
| 成功・完了 | グリーン | `\e[32m` |
| 警告・注意 | オレンジ（ボールドイエロー） | `\e[1;33m` |
| エラー | レッド | `\e[31m` |
| 補足情報 | シアン | `\e[36m` |
| 通常テキスト | リセット | `\e[0m` |

### 起動時ウェルカム画面

ピクセルアート（案A）＋ウェルカムメッセージ：

```
     ▓  ░  ▓  ░  ▓        ← スチーム（グレー）
      ░▓░  ░▓░  ░
   ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄        ← カップ（イエロー）
   █▓▓▓▓▓▓▓▓▓▓▓▓▓█        ← コーヒー面（ブライトイエロー）
   █             █▄▄       ← ハンドル
   █             █  █
   █             █▀▀
   ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀        ← ソーサー
     ▀▀▀▀▀▀▀▀▀▀▀

   Welcome to CoffeeTool ☕️   v1.0.0
```

**カラー設計：**

| パーツ | 文字 | カラー | ANSIコード |
|--------|------|--------|------------|
| スチーム | `▓ ░` | グレー | `\e[37m` |
| カップ本体 | `▄ █ ▀` | イエロー（琥珀） | `\e[33m` |
| コーヒー面 | `▓` | ブライトイエロー | `\e[1;33m` |
| ウェルカム文字 | テキスト | イエロー | `\e[33m` |
| バージョン | テキスト | グレー | `\e[37m` |

**実装イメージ（echo コマンド）：**
```bash
echo -e "     \e[37m▓  ░  ▓  ░  ▓\e[0m"
echo -e "      \e[37m░▓░  ░▓░  ░\e[0m"
echo -e "   \e[33m▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄\e[0m"
echo -e "   \e[33m█\e[1;33m▓▓▓▓▓▓▓▓▓▓▓▓▓\e[0;33m█\e[0m"
echo -e "   \e[33m█             █▄▄\e[0m"
echo -e "   \e[33m█             █  █\e[0m"
echo -e "   \e[33m█             █▀▀\e[0m"
echo -e "   \e[33m▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀\e[0m"
echo -e "     \e[33m▀▀▀▀▀▀▀▀▀▀▀\e[0m"
echo
echo -e "   \e[33mWelcome to CoffeeTool ☕️\e[0m   \e[37mv${TOOL_VERSION}\e[0m"
```

### ノード情報ヘッダー（ウェルカム画面の下）

```
╔══════════════════════════════════════════════════════╗
║  サーバー : BP  │  ネットワーク : mainnet             ║
║  Era      : Conway  │  ノード : 10.6.4               ║
║  CLI      : 10.15.0  │  DB : 142G  │  空き : 230G    ║
╚══════════════════════════════════════════════════════╝
```

### メニュー操作方式

数字入力とカーソル移動の**両方**に対応する。外部ツール不要（純粋 bash 実装）。

| 操作 | 動作 |
|------|------|
| `↑` `↓` | カーソル移動（ハイライト） |
| `Enter` | 選択確定 |
| `1`〜`9` | 番号で即時選択・確定 |
| `q` | 戻る／終了 |

### メニューデザイン

通常状態（カーソルが [2] にある例）：

```
┌─────────────────────────────────────────┐
│  メインメニュー                          │
├─────────────────────────────────────────┤
│    [1]  ウォレット操作                   │
│  ▶ [2]  ブロック生成状態チェック  ←選択中 │
│    [3]  KES 更新                        │
│    [4]  ガバナンス（投票・委任）          │
│  ─────────────────────────────────────  │
│    [q]  終了                            │
└─────────────────────────────────────────┘
```

- 選択中の行は `▶` ＋ イエローハイライト
- 選択していない行はグレー表示
- 数字キー入力で即時確定（カーソル移動不要）

### メニュー共通関数（実装方針）

```bash
# 使い方:
#   menu_select "タイトル" "項目1" "項目2" ...
#   戻り値: 選択インデックス（0始まり）、q=99

menu_select() {
  local title="$1"; shift
  local items=("$@")
  local selected=0
  local total=${#items[@]}

  while true; do
    # メニュー再描画
    tput cup ... # カーソル位置リセット
    draw_menu_box "$title" "${items[@]}" $selected

    # キー入力
    read -s -n1 key

    if [[ $key == $'\e' ]]; then
      read -s -n2 seq
      case $seq in
        '[A') ((selected--)); [ $selected -lt 0 ] && selected=$((total-1)) ;;
        '[B') ((selected++)); [ $selected -ge $total ] && selected=0 ;;
      esac
    elif [[ $key == '' ]]; then   # Enter
      return $selected
    elif [[ $key =~ ^[1-9]$ ]]; then  # 数字即時選択
      local num=$((key-1))
      [ $num -lt $total ] && return $num
    elif [[ $key == 'q' ]]; then
      return 99
    fi
  done
}
```

### セクション見出し

```
╔══ ウォレット操作 ═══════════════════════╗
```

### コピペ範囲表示

```
┌──── tx.raw の内容（エアギャップにコピー）────┐
84a400...
└─────────────────────────────────────────────┘
```

### エアギャップ CLI 表示

> USB マウント・アンマウントコマンドは表示しない。ファイル転送はユーザーが適宜実施する前提。

```
┌──── エアギャップで実行（コピペ用）──────────┐
│  # cold-keys ロック解除                      │
│  chmod 400 $HOME/cold-keys/payment.skey      │
│                                              │
│  cardano-cli conway transaction sign \       │
│    --tx-body-file tx.raw \                   │
│    --signing-key-file .../payment.skey \     │
│    --mainnet \                               │
│    --out-file tx.signed                      │
│                                              │
│  # cold-keys 再ロック                        │
│  chmod 000 $HOME/cold-keys/payment.skey      │
└──────────────────────────────────────────────┘
```

### ステータス表示

```
  ✅ トランザクションを送信しました
  ⚠️  ノードが起動していません
  ❌ ファイルが見つかりません: payment.skey
```

---

## メニューフロー全体図

```
起動
 └─ ウェルカム画面（ピクセルアート）
     └─ ノード情報ヘッダー
         └─ [メインメニュー]
               ├─ [1] プール資金の管理
               │     ├─ [1] ウォレット残高を表示する（報酬残高も同時表示）
               │     ├─ [2] リワードを送金する
               │     ├─ [3] プール資金を送金する
               │     └─ [b] 戻る
               │
               ├─ [2] プール設定の確認
               │     ├─ [1] 現在のブロック生成状態
               │     ├─ [2] 次エポックのスロットリーダー確認
               │     └─ [b] 戻る
               │
               ├─ [3] KES の更新をする
               │     │
               │     │  ── STEP 1: 状態確認（BP・自動）──
               │     ├─ KES 残日数・更新回数を表示
               │     ├─ 更新しますか？ [y/N]
               │     │     └─ y → ブロック生成スケジュール確認
               │     │             ├─ ✅ 次のブロック生成まで1時間以上あります → 実行しますか？ [y/N]
               │     │             └─ ⚠️  1時間以内にブロック生成があります → それでも実行しますか？ [y/N]
               │     │
               │     │  ── STEP 2: KES キー生成（BP・自動）──
               │     ├─ kes.vkey / kes.skey をバックアップ、node.cert をバックアップ
               │     ├─ 新規 kes.vkey / kes.skey を生成
               │     │
               │     │  ── STEP 3: エアギャップへ転送（手動）──
               │     ├─ kes.vkey / kes.skey の sha256sum を表示（コピペ範囲付き）
               │     ├─ 「USB に kes.vkey / kes.skey をコピーしてエアギャップへ転送してください」
               │     ├─ エアギャップ側でのコマンドを表示（コピペ用）
               │     └─ 転送・ハッシュ確認が完了したら Enter
               │
               │     │  ── STEP 4: オンチェーン情報取得（BP・自動）──
               │     ├─ オンチェーンカウンター取得・表示（lastBlockCnt）
               │     ├─ startKesPeriod 算出・表示
               │     │
               │     │  ── STEP 5: エアギャップで node.cert 生成（手動）──
               │     ├─ エアギャップで実行するコマンドをボックス表示（コピペ用）
               │     │     ├─ cold-keys ロック解除
               │     │     ├─ カウンターファイル更新（cnt_No = lastBlockCnt + 1）
               │     │     ├─ node.cert 生成（startKesPeriod を使用）
               │     │     └─ cold-keys 再ロック
               │     ├─ 「node.cert を USB 経由で BP に転送してください」
               │     └─ 転送完了したら Enter
               │
               │     │  ── STEP 6: ハッシュ確認・ノード再起動（BP・自動）──
               │     ├─ node.cert の sha256sum を表示
               │     ├─ 「エアギャップ側と同じ値か確認してください」→ Enter
               │     ├─ ノードを再起動（自動）
               │     ├─ KES 状態を確認・表示
               │     │     ├─ ✅ 正常に更新されました
               │     │     └─ ❌ エラー → バックアップから復元しますか？ [y/N]
               │     └─ バックアップファイルを削除しますか？ [y/N]
               │
               ├─ [4] プール情報を更新する（統合フロー）
               │     ├─ 現在のプール設定を表示
               │     │     ├─ pledge   : XX,XXX ADA
               │     │     ├─ margin   : X.X %
               │     │     ├─ cost     : XXX ADA
               │     │     ├─ metadata : https://...
               │     │     └─ extended : https://...（未設定の場合は表示なし）
               │     │
               │     ├─ 変更する項目を選択（変更しない項目は現在値を引き継ぎ）
               │     │     ├─ [ ] pledge（ADA で入力 → lovelace に自動変換）
               │     │     ├─ [ ] margin（% で入力 → 小数に自動変換　例: 3.0 → 0.03）
               │     │     ├─ [ ] cost（ADA で入力 → lovelace に自動変換）
               │     │     ├─ [ ] metadata（name / description / ticker / homepage）
               │     │     └─ [ ] extended metadata URL
               │     │
               │     ├─ 入力値の単位ガイド表示
               │     │     ├─ pledge / cost : 「ADA で入力してください（例: 10000）」
               │     │     └─ margin        : 「% で入力してください（例: 3.0 = 3.0%）」
               │     │
               │     ├─ poolMetaData.json 生成＋ハッシュ自動計算（metadata 変更時）
               │     ├─ ⚠️  poolMetaData.json をアップロードしてください（metadata 変更時・手動）
               │     │
               │     ├─ ── 確認画面 ──────────────────────────────
               │     │     ├─ pledge   : XX,XXX ADA（XXXXXXXX lovelace）
               │     │     ├─ margin   : X.X %（0.0X）
               │     │     ├─ cost     : XXX ADA（XXXXXX lovelace）
               │     │     ├─ name     : xxxxxxxxxx
               │     │     ├─ ticker   : XXXXX
               │     │     ├─ desc     : xxxxxxxxxx
               │     │     ├─ homepage : https://...
               │     │     ├─ metadata : https://...（hash: xxxxxxxx）
               │     │     └─ extended : https://...
               │     │
               │     ├─ この内容で pool.cert を生成しますか？ [y/N]
               │     │     └─ y → pool.cert 生成 → Tx 作成 → エアギャップ（node.skey + payment.skey）→ 送信
               │     │
               │     └─ [b] 戻る
               │
               ├─ [5] DRep へ委任をする（サブメニューなし）
               │     ├─ [1] DRep に委任する → DRep ID 入力
               │     ├─ [2] 棄権する（always-abstain）
               │     ├─ [3] 不信任にする（always-no-confidence）
               │     └─ [b] 戻る
               │
               ├─ [6] ガバナンス投票をする（サブメニューなし）
               │     ├─ Action ID を入力
               │     ├─ [1] Yes  [2] No  [3] Abstain
               │     ├─ rationale を添付しますか？ [y/N]
               │     │     └─ y → URL 入力 → ハッシュ自動計算 → 確認表示
               │     └─ Tx 作成 → エアギャップ → 送信
               │
               └─ [q] 終了
```

## メインメニュー構成

```
[1] プール資金の管理
[2] プール設定の確認
[3] KES の更新をする
[4] プール情報を更新する
[5] DRep へ委任をする
[6] ガバナンス投票をする
[q] 終了
```

---

## KES 更新フロー詳細（ユーザー操作含む）

凡例：
- `[ctool]` … ツールが自動実行
- `[BP手動]` … ユーザーが BP で手動操作
- `[エアギャップ手動]` … ユーザーがエアギャップで手動操作
- `[確認]` … ユーザーが目視確認して Enter

```
[ctool]        KES 残日数・更新回数を表示
               ┌─────────────────────────────────────┐
               │  KES 残日数  : 23日                  │
               │  更新回数    : 3 / 62               │
               │  次回期限    : 2026-05-20 頃         │
               └─────────────────────────────────────┘
               更新しますか？ [y/N]

[ユーザー]     y を入力

[ctool]        ブロック生成スケジュールを確認中...
               ✅ 次のブロック生成まで 4時間32分 あります
               実行しますか？ [y/N]
               （⚠️  1時間以内の場合は警告を表示）

[ユーザー]     y を入力

━━ STEP 1: KES キー生成＋オンチェーン情報取得（BP）━━━━

[ctool]        kes.vkey / kes.skey / node.cert をバックアップ
               新規 kes.vkey / kes.skey を生成
               オンチェーンカウンターを取得
               startKesPeriod を算出
               ✅ 完了

               ┌─────────────────────────────────────┐
               │  オンチェーンカウンター : 3          │
               │  新しいカウンター値    : 4           │
               │  startKesPeriod       : 572          │
               ├─────────────────────────────────────┤
               │  kes.vkey ハッシュ : a1b2c3d4...    │
               │  kes.skey ハッシュ : e5f6a7b8...    │
               └─────────────────────────────────────┘

               ┌──── エアギャップで実行（コピペ用）─────┐
               │  # cold-keys ロック解除               │
               │  chmod u+rwx $HOME/cold-keys           │
               │                                        │
               │  cd $NODE_HOME                         │
               │  cardano-cli latest node new-counter \ │
               │    --cold-verification-key-file \      │
               │      $HOME/cold-keys/node.vkey \       │
               │    --counter-value 4 \                 │  ← 実数値
               │    --operational-certificate-issue-    │
               │      counter-file \                    │
               │      $HOME/cold-keys/node.counter      │
               │                                        │
               │  cardano-cli latest node issue-op-cert\│
               │    --kes-verification-key-file \       │
               │      $NODE_HOME/kes.vkey \             │
               │    --cold-signing-key-file \           │
               │      $HOME/cold-keys/node.skey \       │
               │    --operational-certificate-issue-    │
               │      counter \                         │
               │      $HOME/cold-keys/node.counter \    │
               │    --kes-period 572 \                  │  ← 実数値
               │    --out-file $NODE_HOME/node.cert     │
               │                                        │
               │  # cold-keys 再ロック                  │
               │  chmod a-rwx $HOME/cold-keys           │
               └────────────────────────────────────────┘

━━ STEP 2: エアギャップへ転送（USB）━━━━━━━━━━━━━━━━

[ctool]        BP 側での USB コピーコマンドを表示（コピペ用）
               ┌──── BP で実行 ──────────────────────────┐
               │  sudo mount /dev/sdb1 /mnt             │
               │  cp $NODE_HOME/kes.vkey /mnt/          │
               │  cp $NODE_HOME/kes.skey /mnt/          │
               │  sudo umount /mnt                      │
               └────────────────────────────────────────┘

[BP手動]       USB に kes.vkey / kes.skey をコピー
               USB をエアギャップマシンに挿す

[ctool]        エアギャップ側でのコマンドを表示（コピペ用）
               ┌──── エアギャップで実行 ─────────────────┐
               │  sudo mount /dev/sdb1 /mnt             │
               │  cp /mnt/kes.vkey $NODE_HOME/          │
               │  cp /mnt/kes.skey $NODE_HOME/          │
               │  sudo umount /mnt                      │
               │                                        │
               │  # ハッシュ確認（BP の値と照合）        │
               │  sha256sum $NODE_HOME/kes.vkey          │
               │  sha256sum $NODE_HOME/kes.skey          │
               └────────────────────────────────────────┘

[エアギャップ手動] コマンドを実行・ハッシュを BP の値と目視確認

[確認]         ハッシュが一致したら Enter

━━ STEP 3: エアギャップで node.cert 生成━━━━━━━━━━━━

[エアギャップ手動] STEP 1 で表示されたコマンド（実数値入り）をコピペして実行

━━ STEP 4: BP へ転送（USB）━━━━━━━━━━━━━━━━━━━━━━

[ctool]        エアギャップ・BP 両側の USB コマンドを表示（コピペ用）

[エアギャップ手動] node.cert を USB にコピー
               USB を BP に挿す

[BP手動]       USB から node.cert をコピー

[確認]         転送完了したら Enter

━━ STEP 5: ハッシュ確認（BP）━━━━━━━━━━━━━━━━━━━

[ctool]        node.cert の sha256sum を表示
               ┌──── node.cert のハッシュ（コピー用）───┐
               │  c9d8e7f6...                          │
               └────────────────────────────────────────┘
               エアギャップ側と同じ値であることを確認してください
               確認できたら Enter

[確認]         ハッシュを目視確認して Enter

━━ STEP 6: ノード再起動・確認（BP）━━━━━━━━━━━━━━

[ctool]        ノードを再起動
               KES 状態を確認...
               ✅ KES 更新が正常に完了しました

               バックアップファイル（kes-bk.* / node-bk.cert）を削除しますか？ [y/N]

[ユーザー]     y を入力 → 削除完了
```

---

## プール資金管理フロー詳細（ユーザー操作含む）

凡例：`[ctool]` 自動実行　`[BP手動]` ユーザーがBPで操作　`[エアギャップ手動]` エアギャップで操作　`[確認]` 目視確認してEnter

---

### [1] ウォレット残高を表示する

```
[ctool]        payment.addr・stake.addr の残高を取得・表示

               ┌──── ウォレット残高 ──────────────────────┐
               │  payment.addr                           │
               │    残高 : 15,230.5 ADA                  │
               │    UTXO : 3件                           │
               │                                         │
               │  stake.addr（報酬）                     │
               │    残高 : 42.3 ADA                      │
               │                                         │
               │  ⚠️  誓約額 10,000 ADA を維持してください │
               └─────────────────────────────────────────┘

[確認]         確認したら Enter でメニューに戻る
```

---

### [2] リワードを送金する（stake → 全額）

```
[ctool]        報酬残高を取得・表示
               ┌──── 報酬残高 ────────────────────────────┐
               │  stake.addr 残高 : 42.3 ADA              │
               │  ⚠️  報酬は全額のみ引き出し可能です       │
               └─────────────────────────────────────────┘

               どこに送金しますか？

               ┌─────────────────────────────────────────┐
               │  [1]  外部アドレス / ADAhandle に送金する │
               │  [2]  プールウォレットに送金する          │
               │       → addr1xxxx...xxxx（payment.addr） │
               │  [b]  戻る                              │
               └─────────────────────────────────────────┘

  ── [1] 外部アドレス / ADAhandle に送金する ──

[ctool]        送金先を入力してください（addr1... または $handle）：
               > $coffe

[ctool]        ADAhandle を解決中... → addr1xxxx...xxxx
               手数料を自動計算
               ┌──── 送金内容の確認 ──────────────────────┐
               │  送金先 : $coffe（addr1xxxx...xxxx）     │
               │  報酬額 : 42.3 ADA                      │
               │  手数料 : 0.18 ADA（自動計算）           │
               │  受取額 : 42.12 ADA                     │
               └─────────────────────────────────────────┘
               実行しますか？ [y/N]

  ── [2] プールウォレットに送金する ──

[ctool]        手数料を自動計算
               ┌──── 送金内容の確認 ──────────────────────┐
               │  送金先 : payment.addr（プールウォレット）│
               │  報酬額 : 42.3 ADA                      │
               │  手数料 : 0.18 ADA（自動計算）           │
               │  受取額 : 42.12 ADA                     │
               └─────────────────────────────────────────┘
               実行しますか？ [y/N]

[ユーザー]     y を入力

[ctool]        tx.raw を生成
               tx.raw の内容を表示（コピペ範囲付き）

               ┌──── エアギャップで実行（コピペ用）──────┐
               │  # BP で実行（USB へコピー）             │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/tx.raw /mnt/             │
               │  sudo umount /mnt                       │
               │                                         │
               │  # エアギャップで実行                    │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp /mnt/tx.raw $NODE_HOME/             │
               │  sudo umount /mnt                       │
               │                                         │
               │  chmod 400 $HOME/cold-keys/payment.skey │
               │  chmod 400 $HOME/cold-keys/stake.skey   │
               │                                         │
               │  cardano-cli latest transaction sign \  │
               │    --tx-body-file tx.raw \              │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/payment.skey \     │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/stake.skey \       │
               │    --mainnet \                          │
               │    --out-file tx.signed                 │
               │                                         │
               │  chmod 000 $HOME/cold-keys/payment.skey │
               │  chmod 000 $HOME/cold-keys/stake.skey   │
               │                                         │
               │  # tx.signed を USB にコピー             │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/tx.signed /mnt/          │
               │  sudo umount /mnt                       │
               └─────────────────────────────────────────┘

[BP手動]       USB に tx.raw をコピー → エアギャップへ

[エアギャップ手動] コマンドをコピペ実行 → tx.signed を USB にコピー → BP へ

[BP手動]       USB から tx.signed をコピー

[確認]         転送完了したら Enter

[ctool]        トランザクションを送信
               ✅ 送信完了
               送金後の残高を表示
```

---

### [3] プール資金を送金する（payment → 任意アドレス）

```
[ctool]        payment.addr 残高を取得・表示

               ┌──── payment.addr 残高 ───────────────────┐
               │  残高         : 15,230.5 ADA            │
               │  誓約額       : 10,000.0 ADA            │
               │  送金可能上限 :  5,230.5 ADA（手数料除く）│
               │                                         │
               │  ⚠️  誓約額を下回る送金はブロックされます  │
               └─────────────────────────────────────────┘

               送金先アドレスを入力してください：
               > addr1...

               送金額を入力してください（ADA）：
               > 100

[ctool]        入力値を検証
               ├─ ✅ 送金可能（残高 - 誓約額 - 手数料 > 送金額）→ 確認画面へ
               └─ ❌ 送金不可 → エラーを表示して再入力を促す
                     ┌──── エラー ────────────────────────────┐
                     │  ❌ 送金できません                     │
                     │                                       │
                     │  残高         : 15,230.5 ADA          │
                     │  誓約額       : 10,000.0 ADA          │
                     │  手数料（概算）:      0.2 ADA          │
                     │  送金可能上限  :  5,230.3 ADA          │
                     │                                       │
                     │  入力額 9,000 ADA は上限を超えています │
                     └───────────────────────────────────────┘
                     別の金額を入力してください（ADA）：
                     > ___

[ctool]        手数料を自動計算（送金可能な場合）
               ┌──── 送金内容の確認 ──────────────────────┐
               │  送金先 : addr1xxxx...xxxx               │
               │  送金額 : 100 ADA（100000000 lovelace）  │
               │  手数料 : 0.18 ADA（自動計算）           │
               │  おつり : 15,130.32 ADA                  │
               │  残高（送金後）: 15,130.32 ADA ≥ 誓約額  │
               └─────────────────────────────────────────┘
               実行しますか？ [y/N]

[ユーザー]     y を入力

[ctool]        tx.raw を生成
               tx.raw の内容を表示（コピペ範囲付き）

               ┌──── エアギャップで実行（コピペ用）──────┐
               │  （USB転送 → 署名 → USB転送）           │
               │  ※ payment.skey のみで署名              │
               │  chmod 400 $HOME/cold-keys/payment.skey │
               │  cardano-cli latest transaction sign \  │
               │    --tx-body-file tx.raw \              │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/payment.skey \     │
               │    --mainnet \                          │
               │    --out-file tx.signed                 │
               │  chmod 000 $HOME/cold-keys/payment.skey │
               └─────────────────────────────────────────┘

[BP手動]       USB に tx.raw をコピー → エアギャップへ

[エアギャップ手動] コマンドをコピペ実行 → tx.signed を USB にコピー → BP へ

[BP手動]       USB から tx.signed をコピー

[確認]         転送完了したら Enter

[ctool]        トランザクションを送信
               ✅ 送信完了
               送金後の残高を表示
```

---

## プール設定の確認フロー詳細

### [1] 現在のブロック生成状態（ヘルスチェック）

```
[ctool]        各種ファイル・証明書・KES状態を一括チェック

               ┌──── ブロック生成 ヘルスチェック ─────────┐
               │                                         │
               │  ノード起動状態                         │
               │  ✅ cardano-node 起動中（PID: 12345）   │
               │                                         │
               │  必須ファイル                           │
               │  ✅ kes.skey        存在               │
               │  ✅ kes.vkey        存在               │
               │  ✅ vrf.skey        存在               │
               │  ✅ vrf.vkey        存在               │
               │  ✅ node.cert       存在               │
               │                                         │
               │  KES 証明書の状態                       │
               │  ✅ opcert カウンター : 正常            │
               │  ✅ KES 残日数       : 23日             │
               │  ✅ KES 更新回数     : 3 / 62          │
               │                                         │
               │  VRF キー照合                           │
               │  ✅ vrf.vkey ハッシュ : 一致            │
               │                                         │
               │  総合判定                               │
               │  ✅ ブロック生成可能な状態です            │
               └─────────────────────────────────────────┘

               ❌ が表示された場合の例：
               ┌──── ブロック生成 ヘルスチェック ─────────┐
               │  ❌ node.cert       見つかりません      │
               │  ❌ KES 残日数      : 0日（期限切れ）   │
               │                                         │
               │  総合判定                               │
               │  ❌ ブロック生成できない状態です          │
               │     → [3] KES の更新をする を実行してください │
               └─────────────────────────────────────────┘

[確認]         確認したら Enter でメニューに戻る
```

> `cardano-cli latest query kes-period-info` および各ファイルの存在確認で判定。
> エラー項目には対応メニューへの案内も表示。

---

### [2] 次エポックのスロットリーダー確認

```
[ctool]        次エポックのスケジュールを確認中...
               （cncli leaderlog を実行）

               ┌──── 次エポックのスケジュール ───────────┐
               │  次エポック    : 479                    │
               │  割当ブロック数 : 4                     │
               │                                         │
               │  #  スロット        予定時刻            │
               │  ─────────────────────────────────────  │
               │  1  12345678    2026-04-29 03:12:45    │
               │  2  12367890    2026-04-30 11:44:02    │
               │  3  12389012    2026-05-01 08:23:17    │
               │  4  12401234    2026-05-03 19:55:48    │
               └─────────────────────────────────────────┘

[確認]         確認したら Enter でメニューに戻る
```

> `cncli leaderlog` を使用。vrf.skey が必要。
> 次エポックのスケジュールはエポック終盤（約1.5日前）から取得可能。
> 取得できない場合は「次エポックのスケジュールはまだ確認できません」を表示。

---

## プール情報更新フロー詳細（ユーザー操作含む）

> pool.cert の生成にはエアギャップ側の `node.vkey` が必要なため、USB の往来が2往復になります。

```
[ctool]        現在のプール設定を Koios API + ローカルファイルから取得・表示

               ┌──── 現在のプール設定 ────────────────────┐
               │  pledge   : 10,000 ADA                  │
               │  margin   : 3.0 %                       │
               │  cost     : 170 ADA                     │
               │  name     : Sample Pool                  │
               │  ticker   : SAMPL                       │
               │  desc     : example.com...            │
               │  homepage : https://example.com       │
               │  metadata : https://...                 │
               │  extended : https://...                 │
               └─────────────────────────────────────────┘

               変更する項目を選択してください（スペースで複数選択・Enter で確定）：

               ┌─────────────────────────────────────────┐
               │  [ ] pledge                             │
               │  [ ] margin                             │
               │  [ ] cost                              │
               │  [ ] name / description / ticker / homepage │
               │  [ ] extended metadata URL              │
               │  [b] 戻る                               │
               └─────────────────────────────────────────┘

[ユーザー]     変更項目を選択・値を入力
               （pledge / cost : ADA で入力　margin : % で入力）

[ctool]        metadata 変更時：poolMetaData.json を生成
               metadata 変更時：ハッシュを自動計算

               ── 確認画面 ──

               ┌──── 変更後の設定（確認）────────────────┐
               │  pledge   : 10,000 ADA（10000000000 lovelace）│
               │  margin   : 3.0 %（0.03）               │
               │  cost     : 170 ADA（170000000 lovelace）│
               │  name     : Sample Pool                  │
               │  ticker   : SAMPL                       │
               │  desc     : example.com...            │
               │  homepage : https://example.com       │
               │  metadata : https://...（hash: xxxx）   │
               │  extended : https://...                 │
               └─────────────────────────────────────────┘
               この内容で進めますか？ [y/N]

[ユーザー]     y を入力

━━ TRIP 1: BP → エアギャップ ━━━━━━━━━━━━━━━━━━━━

[ctool]        エアギャップで実行するコマンドを表示（値を埋め込み済み）

               ┌──── BP で実行（USB へコピー）───────────┐
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/vrf.vkey /mnt/           │
               │  cp $NODE_HOME/poolMetaData.json /mnt/  │
               │  cp $NODE_HOME/poolMetaDataHash.txt /mnt/│
               │  cp $NODE_HOME/params.json /mnt/        │
               │  sudo umount /mnt                       │
               └─────────────────────────────────────────┘
               ┌──── エアギャップで実行（コピペ用）──────┐
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp /mnt/vrf.vkey $NODE_HOME/           │
               │  cp /mnt/poolMetaData.json $NODE_HOME/  │
               │  cp /mnt/poolMetaDataHash.txt $NODE_HOME/│
               │  cp /mnt/params.json $NODE_HOME/        │
               │  sudo umount /mnt                       │
               │                                         │
               │  # cold-keys ロック解除                  │
               │  chmod u+rwx $HOME/cold-keys            │
               │                                         │
               │  cardano-cli latest stake-pool \        │
               │    registration-certificate \           │
               │    --cold-verification-key-file \       │
               │      $HOME/cold-keys/node.vkey \        │
               │    --vrf-verification-key-file \        │
               │      $NODE_HOME/vrf.vkey \              │
               │    --pool-pledge 10000000000 \          │  ← 実数値
               │    --pool-cost 170000000 \              │  ← 実数値
               │    --pool-margin 0.03 \                 │  ← 実数値
               │    --pool-reward-account-verification-  │
               │      key-file $NODE_HOME/stake.vkey \   │
               │    --pool-owner-stake-verification-     │
               │      key-file $NODE_HOME/stake.vkey \   │
               │    --mainnet \                          │
               │    --pool-relay-ipv4 YOUR_RELAY_IP \    │
               │    --pool-relay-port 6000 \             │
               │    --metadata-url https://... \         │  ← 実URL
               │    --metadata-hash xxxxxxxxxxxx \       │  ← 実ハッシュ値
               │    --out-file $NODE_HOME/pool.cert      │
               │                                         │
               │  # cold-keys 再ロック                    │
               │  chmod a-rwx $HOME/cold-keys            │
               │                                         │
               │  # pool.cert を USB にコピー             │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/pool.cert /mnt/          │
               │  sudo umount /mnt                       │
               └─────────────────────────────────────────┘

[BP手動]       USB にファイルをコピー → エアギャップへ

[エアギャップ手動] コマンドをコピペ実行 → pool.cert を USB にコピー → BP へ

[BP手動]       USB から pool.cert をコピー

[確認]         転送完了したら Enter

━━ TRIP 2: BP → エアギャップ（署名）━━━━━━━━━━━━━

[ctool]        tx.raw を生成（BP・自動）
               tx.raw の内容を表示（コピペ範囲付き）

               ┌──── エアギャップで実行（コピペ用）──────┐
               │  # USB 転送（BP → エアギャップ）         │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/tx.raw /mnt/             │
               │  sudo umount /mnt                       │
               │                                         │
               │  # エアギャップ側                        │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp /mnt/tx.raw $NODE_HOME/             │
               │  sudo umount /mnt                       │
               │                                         │
               │  chmod u+rwx $HOME/cold-keys            │
               │                                         │
               │  cardano-cli conway transaction sign \  │
               │    --tx-body-file tx.raw \              │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/node.skey \        │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/payment.skey \     │
               │    --mainnet \                          │
               │    --out-file tx.signed                 │
               │                                         │
               │  chmod a-rwx $HOME/cold-keys            │
               │                                         │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/tx.signed /mnt/          │
               │  sudo umount /mnt                       │
               └─────────────────────────────────────────┘

[BP手動]       USB に tx.raw をコピー → エアギャップへ

[エアギャップ手動] コマンドをコピペ実行 → tx.signed を USB にコピー → BP へ

[BP手動]       USB から tx.signed をコピー

[確認]         転送完了したら Enter

[ctool]        トランザクションを送信
               ✅ 送信完了
```

---

## DRep 委任フロー詳細（ユーザー操作含む）

```
[ctool]        現在の委任状況を Koios API で取得・表示

               ┌──── 現在の DRep 委任状況 ───────────────┐
               │  委任先 : drep1xxxx...                  │
               │  DRep名 : Hikaru Nomura                 │
               └─────────────────────────────────────────┘
               （未委任・always-abstain・always-no-confidence の場合もそれぞれ表示）

               委任方法を選択してください：

               ┌─────────────────────────────────────────┐
               │  [1]  DRep に委任する                   │
               │  [2]  棄権する（always-abstain）         │
               │  [3]  不信任にする（always-no-confidence）│
               │  [b]  戻る                              │
               └─────────────────────────────────────────┘

  ── [1] DRep に委任する ──

[ctool]        委任先の DRep ID を入力してください（drep1...）：
               > drep1xxxx...

[ctool]        DRep 情報を Koios API で確認中...

               ┌──── DRep 情報 ───────────────────────────┐
               │  DRep ID : drep1xxxx...                 │
               │  DRep 名 : Hikaru Nomura                │
               └─────────────────────────────────────────┘
               このDRepに委任しますか？ [y/N]
               （DRep が見つからない場合は ❌ を表示して再入力）

[ユーザー]     y を入力

  ── [2][3] 棄権 / 不信任 ──

[ctool]        確認メッセージを表示
               ┌─────────────────────────────────────────┐
               │  ⚠️  常に棄権（always-abstain）に設定します │
               └─────────────────────────────────────────┘
               実行しますか？ [y/N]

[ユーザー]     y を入力

  ── 共通フロー（委任証明書生成〜送信）──

[ctool]        $NODE_HOME/governance/ を作成（mkdir -p・存在すればスキップ）
               drep-deleg.cert を生成（BP・自動）
               tx.raw を生成（BP・自動）
               tx.raw の内容を表示（コピペ範囲付き）

               ┌──── エアギャップで実行（コピペ用）──────┐
               │  # USB 転送（BP → エアギャップ）         │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/governance/drep-tx.raw \ │
               │     /mnt/                               │
               │  sudo umount /mnt                       │
               │                                         │
               │  # エアギャップ側                        │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp /mnt/drep-tx.raw $NODE_HOME/        │
               │  sudo umount /mnt                       │
               │                                         │
               │  chmod 400 $HOME/cold-keys/payment.skey │
               │  chmod 400 $HOME/cold-keys/stake.skey   │
               │                                         │
               │  cardano-cli conway transaction sign \  │
               │    --tx-body-file drep-tx.raw \         │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/payment.skey \     │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/stake.skey \       │
               │    --mainnet \                          │
               │    --out-file drep-tx.signed            │
               │                                         │
               │  chmod 000 $HOME/cold-keys/payment.skey │
               │  chmod 000 $HOME/cold-keys/stake.skey   │
               │                                         │
               │  # USB 転送（エアギャップ → BP）          │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/drep-tx.signed /mnt/     │
               │  sudo umount /mnt                       │
               └─────────────────────────────────────────┘

[BP手動]       USB に drep-tx.raw をコピー → エアギャップへ

[エアギャップ手動] コマンドをコピペ実行 → drep-tx.signed を USB にコピー → BP へ

[BP手動]       USB から drep-tx.signed をコピー

[確認]         転送完了したら Enter

[ctool]        トランザクションを送信
               ✅ 送信完了

               ┌──── 委任完了 ────────────────────────────┐
               │  委任先 : drep1xxxx...                  │
               │  DRep名 : Hikaru Nomura                 │
               └─────────────────────────────────────────┘
```

---

## ガバナンス投票フロー詳細（ユーザー操作含む）

```
[ctool]        $NODE_HOME/governance/ を作成（mkdir -p）
               オンチェーンから SPO 投票可能なガバナンスアクションを取得
               （cardano-cli conway query gov-state）

               ┌──── SPO 投票可能なガバナンスアクション ──┐
               │                                         │
               │  [1] ハードフォーク提案 v10.0           │
               │      HardForkInitiation                 │
               │      開始: 470  終了: 485               │
               │                                         │
               │  [2] プロトコルパラメーター変更          │
               │      ParameterChange                    │
               │      開始: 472  終了: 487               │
               │                                         │
               │  [3] ガバナンスアクションIDを手動入力    │
               │                                         │
               │  [b] 戻る                               │
               └─────────────────────────────────────────┘
               （提案が0件の場合は「現在投票可能な提案はありません」を表示）

[ユーザー]     番号を選択（例: 1）

  ── 提案の詳細表示 ──

[ctool]        アンカー URL からデータを取得
               オンチェーンハッシュと照合

               ┌──── 提案の詳細 ──────────────────────────┐
               │  ID       : gov_action1xxxx...           │
               │  種別     : HardForkInitiation           │
               │  タイトル : Chang Hardfork 2            │
               │  概要     : This governance action...   │
               │  開始     : エポック 470                 │
               │  終了     : エポック 485                 │
               │  アンカー : https://...                  │
               │  ✅ ハッシュ検証: 一致                   │
               │  （⚠️  ハッシュ不一致の場合は警告を表示） │
               └─────────────────────────────────────────┘

               投票内容を選択してください：

               ┌─────────────────────────────────────────┐
               │  [1]  Yes                               │
               │  [2]  No                                │
               │  [3]  Abstain                           │
               │  [b]  戻る                              │
               └─────────────────────────────────────────┘

[ユーザー]     投票内容を選択（例: 2）

[ctool]        rationale（投票理由）を添付しますか？ [y/N]

  ── rationale あり ──

[ctool]        rationale の URL を入力してください：
               > https://github.com/your-repo/rationale.jsonld

               ハッシュを計算中...
               ┌──── rationale ──────────────────────────┐
               │  URL  : https://github.com/.../...      │
               │  Hash : a1b2c3d4...（自動計算）         │
               └─────────────────────────────────────────┘
               この内容で投票しますか？ [y/N]

  ── rationale なし ──

[ctool]        ┌──── 投票内容の確認 ──────────────────────┐
               │  提案  : Chang Hardfork 2               │
               │  投票  : No                             │
               │  rationale : なし                       │
               └─────────────────────────────────────────┘
               この内容で投票しますか？ [y/N]

[ユーザー]     y を入力

  ── 共通フロー（vote.json 生成〜送信）──

[ctool]        vote.json を生成（BP・自動）
               tx.raw を生成（BP・自動）
               tx.raw の内容を表示（コピペ範囲付き）

               ┌──── エアギャップで実行（コピペ用）──────┐
               │  # USB 転送（BP → エアギャップ）         │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/governance/vote-tx.raw \ │
               │     /mnt/                               │
               │  sudo umount /mnt                       │
               │                                         │
               │  # エアギャップ側                        │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp /mnt/vote-tx.raw $NODE_HOME/        │
               │  sudo umount /mnt                       │
               │                                         │
               │  # cold-keys ロック解除                  │
               │  chmod u+rwx $HOME/cold-keys            │
               │                                         │
               │  cardano-cli conway transaction sign \  │
               │    --tx-body-file vote-tx.raw \         │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/node.skey \        │
               │    --signing-key-file \                 │
               │      $HOME/cold-keys/payment.skey \     │
               │    --mainnet \                          │
               │    --out-file vote-tx.signed            │
               │                                         │
               │  # cold-keys 再ロック                    │
               │  chmod a-rwx $HOME/cold-keys            │
               │                                         │
               │  # USB 転送（エアギャップ → BP）          │
               │  sudo mount /dev/sdb1 /mnt              │
               │  cp $NODE_HOME/vote-tx.signed /mnt/     │
               │  sudo umount /mnt                       │
               └─────────────────────────────────────────┘

[BP手動]       USB に vote-tx.raw をコピー → エアギャップへ

[エアギャップ手動] コマンドをコピペ実行 → vote-tx.signed を USB にコピー → BP へ

[BP手動]       USB から vote-tx.signed をコピー

[確認]         転送完了したら Enter

[ctool]        トランザクションを送信
               ✅ 送信完了

               ┌──── 投票完了 ────────────────────────────┐
               │  提案  : Chang Hardfork 2               │
               │  投票  : No                             │
               └─────────────────────────────────────────┘
```

> **署名キーについて**
> SPO 投票は `node.skey`（コールドキー）+ `payment.skey` の2つで署名。
> コールドキーが必要なため、エアギャップでの作業が必須。

---

## 機能詳細

### [1] ウォレット操作

| # | 機能 | 参照 spo-guide |
|---|------|----------------|
| 1 | ウォレット残高・UTXO 確認 | 15_withdrawal.md |
| 2 | プール報酬確認 | 15_withdrawal.md |
| 3 | 報酬出金（stake → payment） | 15_withdrawal.md |
| 4 | 送金（外部アドレスへ） | 15_withdrawal.md |

### [2] ブロック生成状態チェック

| # | 機能 | 参照 spo-guide |
|---|------|----------------|
| 1 | 現在のブロック生成状態表示 | 11_blocklog_cncli.md |
| 2 | 次エポックのスロットリーダー確認 | 11_blocklog_cncli.md |

### [3] KES 更新

| # | 機能 | 参照 spo-guide |
|---|------|----------------|
| - | KES 有効期限確認 → 更新手順の案内 | 13_kes_update.md |

### [4] ガバナンス（投票・委任）

| # | 機能 | 備考 |
|---|------|------|
| 1 | DRep への委任・変更 | — |
| 2 | ガバナンス投票 | rationale アンカー対応（下記参照） |

#### DRep 委任フロー

```
委任方法を選択してください：

  [1]  DRep に委任する
  [2]  棄権する（always-abstain）
  [3]  不信任にする（always-no-confidence）
  [b]  戻る
```

| 選択 | cardano-cli オプション |
|------|-----------------------|
| [1] DRep に委任 | `--drep-key-hash <DREP_ID>` または `--drep-script-hash` |
| [2] 棄権 | `--always-abstain` |
| [3] 不信任 | `--always-no-confidence` |

**[1] 選択時の追加入力：**
```
DRep ID を入力してください（drep1... または drep_script1...）：
> drep1xxxxxx...
```

#### ガバナンス投票の rationale 対応

Conway era の投票では、投票理由（rationale）をアンカーとして添付できる。

**入力フロー：**
```
投票対象の Action ID を入力
  ↓
投票内容を選択（Yes / No / Abstain）
  ↓
rationale を添付しますか？ [y/N]
  ↓ y の場合
  rationale URL を入力
  （例: https://github.com/your-repo/rationale.jsonld）
  ↓
  URL からハッシュを自動計算（ctool 内で実行）
  → 計算結果を画面表示して確認
  ↓
投票 Tx 作成 → エアギャップ署名 → 送信
```

**ハッシュ自動計算：**
```bash
# URL 入力後、ctool 内で自動実行
anchor_hash=$(cardano-cli hash anchor-data --url "$rationale_url")
```

**使用する cardano-cli オプション：**
```bash
cardano-cli conway governance vote create \
  --yes / --no / --abstain \
  --governance-action-tx-id <TX_ID> \
  --governance-action-index <INDEX> \
  --stake-pool-verification-key-file <VKEY> \
  --anchor-url <RATIONALE_URL> \      # rationale 添付時のみ
  --anchor-data-hash <HASH> \         # rationale 添付時のみ（自動計算値）
  --out-file vote.json
```

> ℹ️ rationale ファイルは CIP-0100 形式（JSON-LD）。
> 事前に IPFS・GitHub 等に公開しておき、URL を入力する。

---

## 共通コンポーネント（関数設計）

| 関数名 | 役割 |
|--------|------|
| `header` | ヘッダー表示（ノード状態・バージョン等） |
| `menu` | メニューボックス表示 |
| `section` | セクション見出し表示 |
| `show_txraw` | tx.raw をコピー範囲付きで表示 |
| `show_airgap_sign` | エアギャップ署名 CLI をボックス表示 |
| `show_airgap_sign_stake` | 同上（stake.skey も含む版） |
| `paste_signed` | tx.signed のペースト受付 |
| `tx_submit` | トランザクション送信 |
| `node_check` | ノード起動状態確認 |
| `file_check` | ファイル存在確認 |
| `payment_utxo` | UTXO・残高取得 |
| `current_slot` | 現在スロット取得 |

---

## 未決事項

- [ ] BP 以外で起動した場合のエラーメッセージ設計（opcert 不在を検出）
- [ ] DRep 登録・委任の詳細フロー整理
- [ ] rationale ファイル形式（CIP-0100）のサンプルを spo-guide に追加するか
