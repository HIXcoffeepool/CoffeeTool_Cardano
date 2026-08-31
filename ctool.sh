#!/usr/bin/env bash
# =============================================================================
#  CoffeeTool (ctool) — Cardano SPO 運用ツール
#  Copyright (c) 2026 CoffeePool
#  License: MIT
#  Version: 1.7.0
#  cardano-cli 11.0.0.0 対応
# =============================================================================

set -uo pipefail

# --- バージョン ---------------------------------------------------------------
TOOL_VERSION="1.7.0"

# --- 言語設定 (i18n) ----------------------------------------------------------
# 表示言語 ja|en。env の CTOOL_LANG で既定を指定、メニュー [L] で実行中に切替。
# env より前に定義して初期エラーメッセージも切替対象にする。
CTOOL_LANG="${CTOOL_LANG:-ja}"
# t "日本語" "English" : 現在の言語に応じて文字列を返す
t() { [[ "$CTOOL_LANG" == "en" ]] && printf '%s' "$2" || printf '%s' "$1"; }

# --- env ファイルの読み込み ---------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
ENV_FILE="${SCRIPT_DIR}/env"
if [[ -f "$ENV_FILE" ]]; then
  # guild env は $1 参照・set -o posix 設定など副作用があるため
  # source 前後でシェルオプションを完全に保存・復元する
  _saved_opts=$(set +o 2>/dev/null)
  set +u
  # shellcheck source=./env
  source "$ENV_FILE"
  _env_rc=$?
  eval "${_saved_opts}" 2>/dev/null  # source 前の状態に戻す
  set -uo pipefail                   # ctool 必須オプションを再設定
  if [[ $_env_rc -eq 2 ]]; then
    echo -e "\e[31m❌ $(t "cardano-node が起動していないか、ソケットファイルが存在しません。" "cardano-node is not running, or the socket file is missing.")\e[0m"
    echo -e "   $(t "ノードを起動してから ctool を実行してください。" "Start the node before running ctool.")"
    exit 1
  elif [[ $_env_rc -ne 0 ]]; then
    echo -e "\e[31m❌ $(t "env ファイルの読み込みに失敗しました（rc=${_env_rc}）。" "Failed to load the env file (rc=${_env_rc}).")\e[0m"
    exit 1
  fi
else
  echo -e "\e[31m❌ $(t "env ファイルが見つかりません" "env file not found"): ${ENV_FILE}\e[0m"
  echo -e "   $(t "env.sample をコピーして env を作成してください。" "Copy env.sample to env and edit it.")"
  exit 1
fi

# --- 定数（env 派生）---------------------------------------------------------
# guild-operators env は CNODE_HOME / NETWORK_IDENTIFIER を使う
NODE_HOME="${NODE_HOME:-${CNODE_HOME:-}}"
GOVERNANCE_DIR="${NODE_HOME}"   # governance サブディレクトリは使わず NODE_HOME 直下に統一
COLDKEYS_DIR="${COLDKEYS_DIR:-${HOME}/cold-keys}"
NETWORK="${NETWORK:-${NETWORK_IDENTIFIER:---mainnet}}"

# --- カラー定義 ---------------------------------------------------------------
NC='\e[0m'
FG_YELLOW='\e[33m'
FG_BRIGHT_YELLOW='\e[1;37m'
FG_GREEN='\e[32m'
FG_RED='\e[31m'
FG_CYAN='\e[36m'
FG_GRAY='\e[90m'
FG_WHITE='\e[97m'
FG_ORANGE='\e[33m'

# --- 前提チェック -------------------------------------------------------------
if [[ -z "${NODE_HOME:-}" ]]; then
  echo -e "\e[31m❌ $(t "NODE_HOME が設定されていません。env ファイルを確認してください。" "NODE_HOME is not set. Check your env file.")\e[0m"
  exit 1
fi

# =============================================================================
#  UI コンポーネント
# =============================================================================

SEP="  ──────────────────────────────────────────────────"

# --- ウェルカム画面 -----------------------------------------------------------
show_welcome() {
  clear
  echo
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
  echo -e "   \e[33mWelcome to CoffeeTool ☕️\e[0m  \e[90mv${TOOL_VERSION}\e[0m"
  echo
}

# --- ノード情報ヘッダー -------------------------------------------------------
show_header() {
  local node_ver era cli_ver db_size disk_free

  node_ver=$(cardano-node --version 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A")
  cli_ver=$(cardano-cli --version 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A")
  era=$(cardano-cli latest query tip ${NETWORK} 2>/dev/null | jq -r '.era // "N/A"' || echo "N/A")
  db_size=$(du -sh "${NODE_HOME}/db" 2>/dev/null | awk '{print $1}' || echo "N/A")
  disk_free=$(df -h "${NODE_HOME}" 2>/dev/null | tail -1 | awk '{print $4}' || echo "N/A")

  echo -e "  ${FG_YELLOW}$(t "サーバー" "Server ") : BP  │  $(t "ネットワーク" "Network") : mainnet${NC}"
  echo -e "  ${FG_YELLOW}Era      : ${era}  │  $(t "ノード" "Node") : ${node_ver}${NC}"
  echo -e "  ${FG_YELLOW}CLI      : ${cli_ver}  │  DB : ${db_size}  │  $(t "空き" "Free") : ${disk_free}${NC}"
  echo -e "${SEP}"
}

# --- セクション見出し ---------------------------------------------------------
section() {
  echo
  echo -e "  ${FG_YELLOW}$1${NC}"
  echo -e "${SEP}"
  echo
}

# --- 情報ブロック（タイトル + 行）--------------------------------------------
infoblock() {
  local title="$1"; shift
  echo -e "  ${FG_CYAN}── ${title}${NC}"
  for line in "$@"; do
    echo -e "  ${line}"
  done
  echo -e "${SEP}"
}

# --- コピペ用ブロック ---------------------------------------------------------
copyblock() {
  local title="$1"; shift
  echo
  echo -e "  ${FG_CYAN}── ${title}${NC}"
  for line in "$@"; do
    printf "  \033[97m%s\033[0m\n" "${line}"
  done
  echo -e "${SEP}"
  echo
}

# --- tx.raw 表示 --------------------------------------------------------------
show_txraw() {
  local rel="${1:-tx.raw}"
  local txraw_file="${NODE_HOME}/${rel}"
  local base="${rel##*/}"   # エアギャップへは bare なファイル名で渡す
  [[ ! -f "$txraw_file" ]] && { err "$(t "${rel} が見つかりません" "${rel} not found")"; return 1; }
  echo
  echo -e "  ${FG_CYAN}── $(t "${base} をエアギャップに貼り付け（下記を丸ごとコピー）" "Paste ${base} on the air-gap (copy the whole block below)")${NC}"
  echo -e "${SEP}"
  # ヒアドキュメント形式。終端 EOF は行頭でないと終了しないため字下げしない。
  echo "cat > ${base} << EOF"
  cat "$txraw_file"
  echo
  echo "EOF"
  echo -e "${SEP}"
  echo
}

# --- エアギャップ署名済みファイルを貼り付けで取り込む -------------------------
paste_signed_file() {
  local dest="$1"
  local name; name=$(basename "$dest")
  mkdir -p "$(dirname "$dest")"
  echo
  echo -e "  ${FG_CYAN}── $(t "${name} の中身を貼り付けてください" "Paste the contents of ${name}")${NC}"
  info "$(t "エアギャップで出力された ${name}（JSON）をそのまま貼り付け、" "Paste the ${name} (JSON) produced on the air-gap as-is,")"
  info "$(t "最後に改行してから Ctrl-D を押すと取り込みます。" "then add a newline and press Ctrl-D to import.")"
  echo -e "${SEP}"
  local tmp="${dest}.paste.tmp"
  cat > "$tmp"
  echo
  if ! jq -e '(.cborHex // "") | length > 0' "$tmp" >/dev/null 2>&1; then
    err "$(t "有効な TextEnvelope ではありません（cborHex が見つかりません）。貼り付け内容を確認してください。" "Not a valid TextEnvelope (cborHex not found). Check what you pasted.")"
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$dest"
  ok "$(t "${name} を取り込みました" "${name} imported")"
  return 0
}

# --- エアギャップ署名 CLI 表示（payment.skey のみ）---------------------------
show_airgap_sign_payment() {
  local txfile="${1:-tx.raw}"
  local outfile="${2:-tx.signed}"
  local tb="${txfile##*/}" ob="${outfile##*/}"   # エアギャップでは bare 名で扱う
  copyblock "$(t "エアギャップで実行（コピペ用）" "Run on the air-gapped machine (copy-paste)")" \
    "$(t "# cold-keys ロック解除" "# unlock cold-keys")" \
    "chmod 400 \$HOME/cold-keys/payment.skey" \
    "" \
    "cardano-cli latest transaction sign \\" \
    "  --tx-body-file ${tb} \\" \
    "  --signing-key-file \$HOME/cold-keys/payment.skey \\" \
    "  --mainnet \\" \
    "  --out-file ${ob}" \
    "" \
    "$(t "# cold-keys 再ロック" "# re-lock cold-keys")" \
    "chmod 000 \$HOME/cold-keys/payment.skey" \
    "" \
    "$(t "# 署名済みファイルを BP 貼り付け用のヒアドキュメント形式で表示" "# print the signed file as a heredoc to paste on the BP")" \
    "{ echo \"cat > ${ob} << EOF\"; cat ${ob}; echo; echo EOF; }"
}

# --- エアギャップ署名 CLI 表示（payment.skey + stake.skey）-------------------
show_airgap_sign_stake() {
  local txfile="${1:-tx.raw}"
  local outfile="${2:-tx.signed}"
  local tb="${txfile##*/}" ob="${outfile##*/}"   # エアギャップでは bare 名で扱う
  copyblock "$(t "エアギャップで実行（コピペ用）" "Run on the air-gapped machine (copy-paste)")" \
    "$(t "# cold-keys ロック解除" "# unlock cold-keys")" \
    "chmod 400 \$HOME/cold-keys/payment.skey" \
    "chmod 400 \$HOME/cold-keys/stake.skey" \
    "" \
    "cardano-cli latest transaction sign \\" \
    "  --tx-body-file ${tb} \\" \
    "  --signing-key-file \$HOME/cold-keys/payment.skey \\" \
    "  --signing-key-file \$HOME/cold-keys/stake.skey \\" \
    "  --mainnet \\" \
    "  --out-file ${ob}" \
    "" \
    "$(t "# cold-keys 再ロック" "# re-lock cold-keys")" \
    "chmod 000 \$HOME/cold-keys/payment.skey" \
    "chmod 000 \$HOME/cold-keys/stake.skey" \
    "" \
    "$(t "# 署名済みファイルを BP 貼り付け用のヒアドキュメント形式で表示" "# print the signed file as a heredoc to paste on the BP")" \
    "{ echo \"cat > ${ob} << EOF\"; cat ${ob}; echo; echo EOF; }"
}

# --- エアギャップ署名 CLI 表示（node.skey + payment.skey）--------------------
show_airgap_sign_node() {
  local txfile="${1:-tx.raw}"
  local outfile="${2:-tx.signed}"
  local tb="${txfile##*/}" ob="${outfile##*/}"   # エアギャップでは bare 名で扱う
  copyblock "$(t "エアギャップで実行（コピペ用）" "Run on the air-gapped machine (copy-paste)")" \
    "$(t "# cold-keys ロック解除" "# unlock cold-keys")" \
    "chmod u+rwx \$HOME/cold-keys" \
    "" \
    "cardano-cli latest transaction sign \\" \
    "  --tx-body-file ${tb} \\" \
    "  --signing-key-file \$HOME/cold-keys/node.skey \\" \
    "  --signing-key-file \$HOME/cold-keys/payment.skey \\" \
    "  --mainnet \\" \
    "  --out-file ${ob}" \
    "" \
    "$(t "# cold-keys 再ロック" "# re-lock cold-keys")" \
    "chmod a-rwx \$HOME/cold-keys" \
    "" \
    "$(t "# 署名済みファイルを BP 貼り付け用のヒアドキュメント形式で表示" "# print the signed file as a heredoc to paste on the BP")" \
    "{ echo \"cat > ${ob} << EOF\"; cat ${ob}; echo; echo EOF; }"
}

# --- 確認プロンプト（y/N）-----------------------------------------------------
confirm() {
  local msg="${1:-$(t "実行しますか？" "Proceed?")}"
  echo -en "  ${FG_WHITE}${msg} [y/N]:${NC} "
  local ans
  read -r ans
  [[ "${ans,,}" == "y" ]]
}

# --- Enter 待ち ---------------------------------------------------------------
press_enter() {
  local msg="${1:-$(t "確認したら Enter を押してください" "Press Enter to continue")}"
  echo -en "  ${FG_GRAY}${msg}${NC} "
  read -r
}

# --- ステータス表示 -----------------------------------------------------------
ok()   { echo -e "  ${FG_GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${FG_ORANGE}⚠️  $1${NC}"; }
err()  { echo -e "  ${FG_RED}❌ $1${NC}"; }
info() { echo -e "  ${FG_CYAN}   $1${NC}"; }

# --- UTXO・残高取得 -----------------------------------------------------------
get_payment_balance() {
  local addr
  addr=$(cat "${NODE_HOME}/payment.addr" 2>/dev/null || echo "")

  cardano-cli latest query utxo \
    --address "${addr}" \
    ${NETWORK} 2>"${NODE_HOME}/balance.err" \
    > "${NODE_HOME}/balance.out"

  local total_balance=0
  local tx_in=""

  if [[ ! -s "${NODE_HOME}/balance.out" ]]; then
    echo "0"
    return
  fi

  # 出力形式を判定（先頭行が { なら JSON、そうでなければテーブル）
  if head -1 "${NODE_HOME}/balance.out" | grep -q '^{'; then
    # JSON 形式（cardano-cli 新バージョン）
    total_balance=$(jq '[.[].value.lovelace // 0] | add // 0' "${NODE_HOME}/balance.out" 2>/dev/null || echo 0)
    tx_in=$(jq -r 'keys[] | "--tx-in \(.)"' "${NODE_HOME}/balance.out" 2>/dev/null | tr '\n' ' ')
  else
    # テーブル形式
    while read -r utxo; do
      [[ -z "$utxo" ]] && continue
      local in_addr idx utxo_balance
      in_addr=$(awk '{ print $1 }' <<< "${utxo}")
      idx=$(awk '{ print $2 }' <<< "${utxo}")
      utxo_balance=$(awk '{ print $3 }' <<< "${utxo}")
      [[ "$in_addr" == "TxHash" || "$in_addr" == -* ]] && continue
      total_balance=$(( total_balance + utxo_balance ))
      tx_in+=" --tx-in ${in_addr}#${idx}"
    done < "${NODE_HOME}/balance.out"
  fi

  echo "${total_balance} ${tx_in}"
}

get_reward_balance() {
  cardano-cli latest query stake-address-info \
    --address "$(cat "${NODE_HOME}/stake.addr")" \
    ${NETWORK} 2>/dev/null \
    | jq -r '.[0].rewardAccountBalance // 0'
}

lovelace_to_ada() { awk "BEGIN { printf \"%.6f\", $1/1000000 }"; }
ada_to_lovelace() { awk "BEGIN { printf \"%d\", $1*1000000 }"; }
format_ada()      { awk "BEGIN { printf \"%'.3f\", $1/1000000 }"; }

# cardano-cli 11.x: calculate-min-fee が JSON {"fee": N} を返す場合に対応
# FEE_BUFFER: cli 11 の calculate-min-fee は未署名 body ベースのため witness 分を
# 過小評価しがち（実測で約1 witness=~4400 lovelace 不足）。複数witnessのtxも安全に
# 通すよう余裕を持たせる（余剰分は手数料として消費されるだけで害はない）。
FEE_BUFFER=20000

parse_fee() {
  local raw="$1"
  local v
  v=$(echo "$raw" | jq -r '.fee // empty' 2>/dev/null)
  if [[ -n "$v" && "$v" =~ ^[0-9]+$ ]]; then
    echo $(( v + FEE_BUFFER ))
  else
    local n
    n=$(echo "$raw" | awk '{print $1}')
    echo $(( n + FEE_BUFFER ))
  fi
}

# tx_in 文字列から --tx-in の実数をカウント
count_tx_ins() {
  local tx_in_str="$1"
  local n
  n=$(echo "$tx_in_str" | grep -o -- '--tx-in' | wc -l | tr -d ' ')
  echo "${n:-1}"
}

get_params() {
  cardano-cli latest query protocol-parameters \
    ${NETWORK} \
    --out-file "${NODE_HOME}/params.json" 2>/dev/null
}

get_ttl() {
  # エアギャップ往復（ビルド→署名→送信）に時間がかかるため TTL を長めに取る。
  # 1 slot ≈ 1秒。7200 slot ≈ 2時間の有効期間。
  local slot
  slot=$(cardano-cli latest query tip ${NETWORK} 2>/dev/null | jq -r '.slot // "0"' 2>/dev/null || echo "0")
  echo $(( ${slot:-0} + 7200 ))
}

get_pool_info() {
  # bech32 ID を優先取得（pool1... 形式が必要）
  local pool_id=""

  # 1. pool.id-bech32 を試す
  if [[ -f "${NODE_HOME}/pool.id-bech32" ]]; then
    pool_id=$(cat "${NODE_HOME}/pool.id-bech32" 2>/dev/null || echo "")
  fi

  # 2. pool.id が bech32 形式なら使う
  if [[ -z "$pool_id" || "$pool_id" != pool1* ]]; then
    local raw_id
    raw_id=$(cat "${NODE_HOME}/pool.id" 2>/dev/null || echo "")
    if [[ "$raw_id" == pool1* ]]; then
      pool_id="$raw_id"
    fi
  fi

  # 3. hex 形式しかない場合は cardano-cli で変換
  if [[ -z "$pool_id" || "$pool_id" != pool1* ]]; then
    pool_id=$(cardano-cli latest stake-pool id \
      --cold-verification-key-file "${NODE_HOME}/cold.vkey" \
      --output-format bech32 2>/dev/null || echo "")
  fi

  [[ -z "$pool_id" ]] && { echo ""; return; }

  curl -s "https://api.koios.rest/api/v1/pool_info" \
    -H "Content-Type: application/json" \
    -d "{\"_pool_bech32_ids\":[\"${pool_id}\"]}" 2>/dev/null \
    | jq -r 'if type == "array" then .[0] // empty else empty end' 2>/dev/null || echo ""
}

get_drep_info() {
  curl -s "https://api.koios.rest/api/v1/drep_info" \
    -H "Content-Type: application/json" \
    -d "{\"_drep_ids\":[\"$1\"]}" 2>/dev/null \
    | jq -r '.[0] // empty'
}

resolve_handle() {
  local handle="${1#\$}"
  curl -s "https://api.handle.me/${handle}" 2>/dev/null \
    | jq -r '.resolved_addresses.ada // empty'
}

# =============================================================================
#  メニュー選択（カーソル + 数字入力対応）
# =============================================================================

_draw_menu() {
  local title="$1"
  local selected="$2"
  shift 2
  local items=("$@")

  echo
  echo -e "  ${FG_YELLOW}${title}${NC}"
  echo -e "${SEP}"
  for i in "${!items[@]}"; do
    if [[ $i -eq $selected ]]; then
      echo -e "  ${FG_BRIGHT_YELLOW}▶ ${items[$i]}${NC}"
    else
      echo -e "  ${FG_GRAY}  ${items[$i]}${NC}"
    fi
  done
  echo -e "${SEP}"
  echo -e "  ${FG_GRAY}$(t "↑↓ 移動  Enter 確定  数字キー即選択  q 戻る" "↑↓ move  Enter select  number = quick pick  q back")${NC}"
}

menu_select() {
  local title="$1"; shift
  local items=("$@")
  local total=${#items[@]}
  local selected=0

  tput civis 2>/dev/null || true
  tput sc   2>/dev/null || true  # カーソル位置を保存

  _draw_menu "$title" "$selected" "${items[@]}"

  while true; do
    local key seq
    IFS= read -rs -n1 key

    if [[ $key == $'\e' ]]; then
      IFS= read -rs -n2 -t 0.1 seq 2>/dev/null || seq=""
      case "$seq" in
        '[A') selected=$(( selected - 1 )); [[ $selected -lt 0 ]] && selected=$(( total - 1 )) ;;
        '[B') selected=$(( selected + 1 )); [[ $selected -ge $total ]] && selected=0 ;;
        *) continue ;;
      esac
    elif [[ $key == $'\n' || $key == '' ]]; then
      tput cnorm 2>/dev/null || true
      echo
      [[ "${items[$selected]}" == \[b\]* || "${items[$selected]}" == \[q\]* ]] && return 99
      return $selected
    elif [[ $key =~ ^[1-9]$ ]]; then
      local num=$(( key - 1 ))
      if [[ $num -lt $total ]]; then
        tput cnorm 2>/dev/null || true
        echo
        [[ "${items[$num]}" == \[b\]* || "${items[$num]}" == \[q\]* ]] && return 99
        return $num
      fi
      continue
    elif [[ $key == 'q' || $key == 'b' ]]; then
      tput cnorm 2>/dev/null || true
      echo
      return 99
    else
      continue
    fi

    # 保存したカーソル位置に戻って再描画（行数に依存しないため折り返しに強い）
    tput rc 2>/dev/null || true
    _draw_menu "$title" "$selected" "${items[@]}"
  done
}

# =============================================================================
#  トランザクション共通処理
# =============================================================================

tx_submit() {
  local rel="${1:-tx.signed}"
  local signed_file="${NODE_HOME}/${rel}"
  local name; name=$(basename "$signed_file")

  echo
  info "$(t "エアギャップ出力の「cat > ${rel} << EOF … EOF」を BP の ${NODE_HOME} で実行すると作成できます。" \
           "Run the air-gap output ('cat > ${rel} << EOF … EOF') in ${NODE_HOME} on the BP to create it.")"
  if confirm "$(t "代わりに ctool に直接貼り付けて取り込みますか？（heredocで作成済みなら No）" \
                  "Paste the file content directly into ctool instead? (No if you already created it via heredoc)")"; then
    paste_signed_file "$signed_file" || { press_enter; return 1; }
  else
    press_enter "$(t "${name} を ${signed_file%/*}/ に用意したら Enter を押してください" \
                     "Place ${name} in ${signed_file%/*}/ then press Enter")"
  fi

  if [[ ! -f "$signed_file" ]]; then
    err "$(t "${name} が見つかりません" "${name} not found"): ${signed_file}"
    return 1
  fi

  # 送信前検証(1): 本当に署名済みか。未署名の tx.raw を誤って貼り付けると
  # cborHex は持つため素通りし、submit で MissingVKeyWitness になる。
  local env_type
  env_type=$(jq -r '.type // ""' "$signed_file" 2>/dev/null)
  if [[ "$env_type" == *Unwitnessed* || "$env_type" == *TxBody* ]]; then
    err "$(t "このファイルは未署名です（type: ${env_type}）。" "This file is unsigned (type: ${env_type}).")"
    warn "$(t "未署名の tx.raw を貼り付けた可能性があります。" "You may have pasted the unsigned tx.raw.")"
    info "$(t "エアギャップで署名したファイル（type が「Witnessed Tx …」）を貼り付けてください。" \
             "Paste the air-gap signed file (type 'Witnessed Tx …').")"
    return 1
  fi

  # 送信前検証(2): 署名済みtxが参照する入力が現在のライブUTxOに存在するか確認する。
  # 存在しなければ「古い *-tx.raw に署名した」可能性が高く、submit すると必ず失敗する。
  local tx_inputs stale=""
  tx_inputs=$(cardano-cli debug transaction view --tx-file "$signed_file" 2>/dev/null \
    | jq -r '.inputs[]?' 2>/dev/null)
  if [[ -n "$tx_inputs" ]]; then
    local inp chk
    while IFS= read -r inp; do
      [[ -z "$inp" ]] && continue
      chk=$(cardano-cli latest query utxo --tx-in "$inp" ${NETWORK} 2>/dev/null)
      # 出力に txhash が含まれなければ使用済み（テーブル/JSON どちらの形式でも判定可）
      printf '%s' "$chk" | grep -q "${inp%%#*}" || stale+="${inp} "
    done <<< "$tx_inputs"
  fi
  if [[ -n "$stale" ]]; then
    err "$(t "署名済み tx が参照する入力が現在の UTxO に存在しません:" \
             "The signed tx references inputs that no longer exist in the current UTxO set:")"
    echo -e "  ${FG_GRAY}${stale}${NC}"
    warn "$(t "古い tx.raw に署名している可能性が高いです（送信しても必ず失敗します）。" \
             "You likely signed an old tx.raw (submitting it will always fail).")"
    info "$(t "エアギャップ上の古い tx.raw を削除し、BP で今ビルドした最新の raw を転送して署名し直してください。" \
             "Delete the old tx.raw on the air-gap, transfer the freshly built raw from the BP, and re-sign.")"
    return 1
  fi

  info "$(t "送信中..." "Submitting...")"
  local submit_err
  if submit_err=$(cardano-cli latest transaction submit \
    --tx-file "$signed_file" \
    ${NETWORK} 2>&1); then
    ok "$(t "トランザクションを送信しました" "Transaction submitted")"
    local txid
    txid=$(cardano-cli latest transaction txid --tx-file "$signed_file" 2>/dev/null)
    if [[ -n "$txid" ]]; then
      echo -e "  ${FG_GRAY}Tx ID: ${txid}${NC}"
      info "$(t "反映まで数十秒〜1分ほどかかります。エクスプローラで上記 Tx ID を確認できます。" \
               "It takes ~30-60s to appear on-chain. Look up the Tx ID above in an explorer.")"
    fi
  else
    err "$(t "送信に失敗しました" "Submission failed")"
    [[ -n "$submit_err" ]] && echo -e "  ${FG_GRAY}${submit_err}${NC}"
    # 入力が既に使用済み。「既に取り込み済み」か「別txが入力を消費」かはノードでは区別不可。
    if printf '%s' "$submit_err" | grep -qiE "already been included|All inputs are spent"; then
      warn "$(t "入力UTxOが既に使用済みです（このtxが取り込まれた／別txが入力を消費した、のどちらか）。" \
               "The input UTxO is already spent (either this tx was included, or another tx spent it).")"
      info "$(t "gov-state 等で結果を確認してください。未反映なら、メニューから操作をやり直すと最新のUTxOで再ビルドされます（同じ署名ファイルの再送信では直りません）。" \
               "Check the result (e.g. gov-state). If not reflected, redo the operation from the menu to rebuild with the current UTxO (resubmitting the same signed file will not help).")"
    fi
    return 1
  fi
}

# =============================================================================
#  [1] プール資金の管理
# =============================================================================

menu_wallet() {
  while true; do
    clear
    show_header
    menu_select "$(t "プール資金の管理" "Manage pool funds")" \
      "[1]  $(t "ウォレット残高を表示する" "Show wallet balance")" \
      "[2]  $(t "リワードを送金する"       "Withdraw rewards")" \
      "[3]  $(t "プール資金を送金する"     "Send pool funds")" \
      "[b]  $(t "戻る" "Back")"
    local choice=$?

    case $choice in
      0) wallet_show_balance ;;
      1) wallet_send_reward ;;
      2) wallet_send_payment ;;
      99) return ;;
    esac
  done
}

wallet_show_balance() {
  clear
  section "$(t "ウォレット残高" "Wallet balance")"

  # ファイル存在チェック
  if [[ ! -f "${NODE_HOME}/payment.addr" ]]; then
    err "$(t "payment.addr が見つかりません" "payment.addr not found"): ${NODE_HOME}/payment.addr"
    press_enter; return
  fi
  if [[ ! -f "${NODE_HOME}/stake.addr" ]]; then
    err "$(t "stake.addr が見つかりません" "stake.addr not found"): ${NODE_HOME}/stake.addr"
    press_enter; return
  fi

  info "$(t "残高を取得中..." "Fetching balance...")"

  local result pay_balance utxo_count
  result=$(get_payment_balance)
  pay_balance=$(echo "${result}" | awk '{print $1}')
  if head -1 "${NODE_HOME}/balance.out" 2>/dev/null | grep -q '^{'; then
    utxo_count=$(jq 'length' "${NODE_HOME}/balance.out" 2>/dev/null || echo 0)
  else
    utxo_count=$(awk '/^[a-f0-9]/{n++} END{print n+0}' "${NODE_HOME}/balance.out" 2>/dev/null || echo 0)
  fi

  # クエリエラーの検知
  if [[ -s "${NODE_HOME}/balance.err" ]]; then
    warn "$(t "UTxO クエリでエラーが発生しました：" "The UTxO query returned an error:")"
    while IFS= read -r line; do info "  ${line}"; done < "${NODE_HOME}/balance.err"
    echo
  fi

  local reward_balance
  reward_balance=$(get_reward_balance)

  local pledge_lovelace=0
  local pool_info
  pool_info=$(get_pool_info)
  [[ -n "$pool_info" ]] && pledge_lovelace=$(echo "$pool_info" | jq -r '.pledge // 0')

  echo -e "  ${FG_CYAN}payment.addr${NC}"
  echo -e "    $(t "アドレス" "Address") : $(cat "${NODE_HOME}/payment.addr")"
  echo -e "    $(t "残高    " "Balance") : $(format_ada $pay_balance) ADA"
  echo -e "    UTXO     : ${utxo_count}$(t " 件" "")"
  echo
  echo -e "  ${FG_CYAN}$(t "stake.addr（報酬）" "stake.addr (rewards)")${NC}"
  echo -e "    $(t "残高" "Balance") : $(format_ada $reward_balance) ADA"
  echo
  [[ $pledge_lovelace -gt 0 ]] && warn "$(t "誓約額 $(format_ada $pledge_lovelace) ADA を維持してください" "Keep at least the pledge of $(format_ada $pledge_lovelace) ADA")"

  press_enter
}

wallet_send_reward() {
  clear
  section "$(t "リワードを送金する" "Withdraw rewards")"

  local reward_balance
  reward_balance=$(get_reward_balance)

  if [[ $reward_balance -eq 0 ]]; then
    warn "$(t "引き出せる報酬がありません" "No rewards available to withdraw")"
    press_enter
    return
  fi

  echo -e "  $(t "stake.addr 残高" "stake.addr balance") : $(format_ada $reward_balance) ADA"
  warn "$(t "報酬は全額のみ引き出し可能です" "Rewards can only be withdrawn in full")"
  echo

  menu_select "$(t "送金先を選択" "Choose destination")" \
    "[1]  $(t "外部アドレス / ADAhandle に送金する" "Send to an external address / ADAhandle")" \
    "[2]  $(t "プールウォレットに送金する（payment.addr）" "Send to the pool wallet (payment.addr)")" \
    "[b]  $(t "戻る" "Back")"
  local choice=$?

  local dest_addr="" dest_label=""

  case $choice in
    0)
      echo -en "  ${FG_WHITE}$(t "送金先（addr1... または \$handle）" "Destination (addr1... or \$handle)")：${NC} "
      local dest_input
      read -r dest_input
      if [[ "${dest_input}" == \$* ]]; then
        info "$(t "ADAhandle を解決中..." "Resolving ADAhandle...")"
        dest_addr=$(resolve_handle "$dest_input")
        if [[ -z "$dest_addr" ]]; then
          err "$(t "ADAhandle が見つかりませんでした" "ADAhandle not found"): ${dest_input}"
          press_enter; return
        fi
        dest_label="${dest_input}（${dest_addr:0:20}...）"
      else
        dest_addr="$dest_input"
        dest_label="${dest_addr:0:30}..."
      fi
      ;;
    1)
      dest_addr=$(cat "${NODE_HOME}/payment.addr")
      dest_label="$(t "payment.addr（プールウォレット）" "payment.addr (pool wallet)")"
      ;;
    99) return ;;
  esac

  info "$(t "tx.raw を作成中です。しばらくお待ちください…" "Building tx.raw, please wait…")"
  info "$(t "（作成後、この tx.raw をエアギャップに貼り付けて署名します）" "(after building, paste this tx.raw on the air-gap and sign it)")"
  get_params
  local result pay_balance tx_in
  result=$(get_payment_balance)
  pay_balance=$(awk '{print $1}' <<< "${result}")
  tx_in=$(awk '{$1=""; print $0}' <<< "${result}")

  cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "${dest_addr}+0" \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+0" \
    --withdrawal "$(cat ${NODE_HOME}/stake.addr)+${reward_balance}" \
    --invalid-hereafter 0 --fee 0 \
    --out-file "${NODE_HOME}/tx.draft" 2>/dev/null

  local fee
  fee=$(cardano-cli latest transaction calculate-min-fee \
    --tx-body-file "${NODE_HOME}/tx.draft" \
    --protocol-params-file "${NODE_HOME}/params.json" \
    --tx-in-count "$(count_tx_ins "$tx_in")" --tx-out-count 2 --witness-count 2 \
    2>/dev/null)
  fee=$(parse_fee "$fee")

  local receive_amount=$(( reward_balance - fee ))
  local ttl; ttl=$(get_ttl)

  cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "${dest_addr}+${receive_amount}" \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+${pay_balance}" \
    --withdrawal "$(cat ${NODE_HOME}/stake.addr)+${reward_balance}" \
    --invalid-hereafter ${ttl} --fee ${fee} \
    --out-file "${NODE_HOME}/tx.raw" 2>/dev/null

  echo
  echo -e "  ${FG_CYAN}── $(t "送金内容の確認" "Review transfer")${NC}"
  echo -e "  $(t "送金先" "To    ") : ${dest_label}"
  echo -e "  $(t "報酬額" "Reward") : $(format_ada $reward_balance) ADA"
  echo -e "  $(t "手数料" "Fee   ") : $(format_ada $fee) ADA"
  echo -e "  $(t "受取額" "Net   ") : $(format_ada $receive_amount) ADA"
  echo -e "${SEP}"

  confirm "$(t "実行しますか？" "Proceed?")" || return

  show_txraw
  show_airgap_sign_stake "tx.raw" "tx.signed"
  if tx_submit "tx.signed"; then
    sleep 3
    wallet_show_balance
  else
    press_enter   # 失敗時はエラーを読めるよう Enter で止める
  fi
}

wallet_send_payment() {
  clear
  section "$(t "プール資金を送金する" "Send pool funds")"

  local result pay_balance tx_in
  result=$(get_payment_balance)
  pay_balance=$(awk '{print $1}' <<< "${result}")
  tx_in=$(awk '{$1=""; print $0}' <<< "${result}")

  local pledge_lovelace=0
  local pool_info
  pool_info=$(get_pool_info)
  [[ -n "$pool_info" ]] && pledge_lovelace=$(echo "$pool_info" | jq -r '.pledge // 0')

  local est_fee=200000
  local pledge_max=$(( pay_balance - pledge_lovelace - est_fee ))   # 誓約維持で送れる目安
  local abs_max=$(( pay_balance - est_fee ))                        # 物理的な上限（全額送金）

  echo -e "  $(t "残高                " "Balance             ") : $(format_ada $pay_balance) ADA"
  echo -e "  $(t "誓約額              " "Pledge              ") : $(format_ada $pledge_lovelace) ADA"
  echo -e "  $(t "誓約維持で送れる目安" "Sendable (keep pledge)") : $(format_ada $pledge_max) ADA"
  echo -e "  $(t "送金可能上限（全額）" "Max sendable (all)  ") : $(format_ada $abs_max) ADA"
  info "$(t "誓約を下回る送金も可能です（プール引退時など）。下回る場合は確認が出ます。" "Sending below the pledge is allowed (e.g. pool retirement); you'll be asked to confirm if it does.")"
  echo

  echo -e "  ${FG_GRAY}  $(t "b: 戻る" "b: back")${NC}"
  echo -en "  ${FG_WHITE}$(t "送金先アドレス" "Destination address")：${NC} "
  local dest_addr
  read -r dest_addr
  [[ -z "$dest_addr" || "$dest_addr" == "b" || "$dest_addr" == "q" ]] && return

  local send_lovelace=0 send_all=false send_ada=""
  while true; do
    echo -en "  ${FG_WHITE}$(t "送金額（ADA、全額送金は all）" "Amount (ADA, or 'all' to send everything)")：${NC} "
    read -r send_ada
    [[ -z "$send_ada" || "$send_ada" == "b" || "$send_ada" == "q" ]] && return
    if [[ "$send_ada" == "all" || "$send_ada" == "全額" || "$send_ada" == "max" ]]; then
      send_all=true; break
    fi
    send_lovelace=$(ada_to_lovelace "$send_ada")
    if [[ ! "$send_lovelace" =~ ^[0-9]+$ || $send_lovelace -le 0 ]]; then
      echo; err "$(t "金額の入力が不正です" "Invalid amount")"; echo; continue
    fi
    if [[ $send_lovelace -gt $abs_max ]]; then
      echo
      err "$(t "残高を超えています（手数料込みで送れません）" "Exceeds balance (cannot cover amount + fee)")"
      echo -e "  $(t "送金可能上限（全額）" "Max sendable (all)"): $(format_ada $abs_max) ADA"
      echo
      continue
    fi
    break
  done

  info "$(t "tx.raw を作成中です。しばらくお待ちください…" "Building tx.raw, please wait…")"
  info "$(t "（作成後、この tx.raw をエアギャップに貼り付けて署名します）" "(after building, paste this tx.raw on the air-gap and sign it)")"
  get_params
  local min_utxo=1000000   # おつりがこれ未満なら全額送金へ切替（0 lovelace 出力は無効なため）
  local fee change=0 ttl

  _build_fee_draft() {   # $1=出力数(1|2)
    if [[ "$1" == "1" ]]; then
      cardano-cli latest transaction build-raw ${tx_in} \
        --tx-out "${dest_addr}+0" \
        --invalid-hereafter 0 --fee 0 \
        --out-file "${NODE_HOME}/tx.draft" 2>/dev/null
    else
      cardano-cli latest transaction build-raw ${tx_in} \
        --tx-out "${dest_addr}+0" \
        --tx-out "$(cat ${NODE_HOME}/payment.addr)+0" \
        --invalid-hereafter 0 --fee 0 \
        --out-file "${NODE_HOME}/tx.draft" 2>/dev/null
    fi
    local f
    f=$(cardano-cli latest transaction calculate-min-fee \
      --tx-body-file "${NODE_HOME}/tx.draft" \
      --protocol-params-file "${NODE_HOME}/params.json" \
      --tx-in-count "$(count_tx_ins "$tx_in")" --tx-out-count "$1" --witness-count 1 \
      2>/dev/null)
    parse_fee "$f"
  }

  if [[ "$send_all" == "true" ]]; then
    fee=$(_build_fee_draft 1)
    send_lovelace=$(( pay_balance - fee ))
    change=0
  else
    fee=$(_build_fee_draft 2)
    change=$(( pay_balance - send_lovelace - fee ))
    if [[ $change -lt 0 ]]; then
      err "$(t "残高不足です（手数料込みで送れません）" "Insufficient balance (cannot cover amount + fee)")"; press_enter; return
    fi
    if [[ $change -lt $min_utxo ]]; then
      warn "$(t "おつりが最小UTxO未満のため、全額送金に切り替えます。" "Change is below the minimum UTxO; switching to full send.")"
      send_all=true
      fee=$(_build_fee_draft 1)
      send_lovelace=$(( pay_balance - fee ))
      change=0
    fi
  fi

  # 誓約チェック：送金後の残高が誓約を下回る場合はブロックせず確認する
  if [[ $pledge_lovelace -gt 0 && $change -lt $pledge_lovelace ]]; then
    echo
    warn "$(t "送金後の残高 $(format_ada $change) ADA は誓約額 $(format_ada $pledge_lovelace) ADA を下回ります。" "Balance after sending, $(format_ada $change) ADA, is below the pledge of $(format_ada $pledge_lovelace) ADA.")"
    info "$(t "プール引退などで全額を引き出す場合は続行してください。" "Continue if you are withdrawing everything (e.g. retiring the pool).")"
    info "$(t "現役プールで誓約を割ると、そのエポックのブロック生成・報酬に影響します。" "For an active pool, falling below pledge affects that epoch's block production and rewards.")"
    confirm "$(t "誓約を下回りますが、続けますか？" "This goes below the pledge. Continue?")" || return
  fi

  ttl=$(get_ttl)
  if [[ "$send_all" == "true" ]]; then
    cardano-cli latest transaction build-raw ${tx_in} \
      --tx-out "${dest_addr}+${send_lovelace}" \
      --invalid-hereafter ${ttl} --fee ${fee} \
      --out-file "${NODE_HOME}/tx.raw" 2>/dev/null
  else
    cardano-cli latest transaction build-raw ${tx_in} \
      --tx-out "${dest_addr}+${send_lovelace}" \
      --tx-out "$(cat ${NODE_HOME}/payment.addr)+${change}" \
      --invalid-hereafter ${ttl} --fee ${fee} \
      --out-file "${NODE_HOME}/tx.raw" 2>/dev/null
  fi

  echo
  echo -e "  ${FG_CYAN}── $(t "送金内容の確認" "Review transfer")${NC}"
  echo -e "  $(t "送金先" "To    ") : ${dest_addr:0:40}"
  echo -e "  $(t "送金額" "Amount") : $(format_ada $send_lovelace) ADA（${send_lovelace} lovelace）"
  echo -e "  $(t "手数料" "Fee   ") : $(format_ada $fee) ADA"
  echo -e "  $(t "おつり" "Change") : $(format_ada $change) ADA"
  [[ "$send_all" == "true" ]] && echo -e "  ${FG_GRAY}$(t "（全額送金：おつり無し）" "(full send: no change)")${NC}"
  echo -e "${SEP}"

  confirm "$(t "実行しますか？" "Proceed?")" || return

  show_txraw
  show_airgap_sign_payment "tx.raw" "tx.signed"
  tx_submit "tx.signed"
  press_enter   # 成功・失敗いずれも結果を読めるよう Enter で止める
}

# =============================================================================
#  [2] プール設定の確認
# =============================================================================

menu_pool_check() {
  while true; do
    clear
    show_header
    menu_select "$(t "プール設定の確認" "Pool status")" \
      "[1]  $(t "現在のブロック生成状態" "Block production status")" \
      "[b]  $(t "戻る" "Back")"
    local choice=$?

    case $choice in
      0) pool_health_check ;;
      99) return ;;
    esac
  done
}

pool_health_check() {
  clear
  section "$(t "ブロック生成 ヘルスチェック" "Block production health check")"

  local all_ok=true

  # ノード起動確認
  echo -e "  ${FG_CYAN}$(t "ノード起動状態" "Node status")${NC}"
  local pid
  pid=$(pgrep -x cardano-node 2>/dev/null | head -1 || echo "")
  if [[ -n "$pid" ]]; then
    ok "$(t "cardano-node 起動中" "cardano-node running")（PID: ${pid}）"
  else
    err "$(t "cardano-node が起動していません" "cardano-node is not running")"
    all_ok=false
  fi
  echo

  # 必須ファイル確認
  echo -e "  ${FG_CYAN}$(t "必須ファイル" "Required files")${NC}"
  for f in kes.skey kes.vkey vrf.skey vrf.vkey node.cert; do
    if [[ -f "${NODE_HOME}/${f}" ]]; then
      ok "${f}"
    else
      err "${f}  $(t "見つかりません" "not found")"
      all_ok=false
    fi
  done
  echo

  # KES 状態確認
  echo -e "  ${FG_CYAN}$(t "KES 証明書の状態" "KES certificate status")${NC}"
  local kes_info
  kes_info=$(cardano-cli latest query kes-period-info \
    --op-cert-file "${NODE_HOME}/node.cert" \
    ${NETWORK} 2>/dev/null \
    | sed -n '/^[[:space:]]*{/,$p' || echo "")

  if [[ -n "$kes_info" ]]; then
    local kes_current kes_expiry kes_counter kes_expiry_date slots_per_kes
    kes_current=$(echo "$kes_info"      | jq -r '.qKesCurrentKesPeriod // "0"')
    kes_expiry=$(echo "$kes_info"       | jq -r '.qKesEndKesInterval // "0"')
    kes_counter=$(echo "$kes_info"      | jq -r '.qKesOnDiskOperationalCertificateNumber // "0"')
    kes_expiry_date=$(echo "$kes_info"  | jq -r '.qKesKesKeyExpiry // ""')
    slots_per_kes=$(echo "$kes_info"    | jq -r '.qKesSlotsPerKesPeriod // 129600')
    local kes_remaining=$(( ${kes_expiry:-0} - ${kes_current:-0} ))
    local kes_days=$(( kes_remaining * slots_per_kes / 86400 ))

    if [[ $kes_remaining -gt 0 ]]; then
      ok "$(t "KES 残日数" "KES days left") : $(t "約${kes_days}日（残り${kes_remaining}期）" "~${kes_days} days (${kes_remaining} periods)")"
      ok "$(t "opcert カウンター" "opcert counter") : ${kes_counter}"
      [[ -n "$kes_expiry_date" ]] && info "$(t "有効期限" "Expiry") : ${kes_expiry_date}"
    else
      err "$(t "KES 期限切れ（現在期=${kes_current}  期限期=${kes_expiry}）" "KES expired (current=${kes_current}  end=${kes_expiry})")"
      all_ok=false
    fi
  else
    err "$(t "KES 情報を取得できません" "Cannot fetch KES info")"
    all_ok=false
  fi
  echo

  # 総合判定
  echo -e "  ${FG_CYAN}$(t "総合判定" "Overall")${NC}"
  if [[ "$all_ok" == "true" ]]; then
    ok "$(t "ブロック生成可能な状態です" "Ready to produce blocks")"
  else
    err "$(t "ブロック生成できない状態です" "Not ready to produce blocks")"
    warn "$(t "[3] KES の更新をする を実行してください" "Run [3] Update KES")"
  fi

  press_enter
}

# =============================================================================
#  [3] KES の更新をする
# =============================================================================

menu_kes_update() {
  clear
  section "$(t "KES の更新をする" "Update KES")"

  local kes_info
  kes_info=$(cardano-cli latest query kes-period-info \
    --op-cert-file "${NODE_HOME}/node.cert" \
    ${NETWORK} 2>/dev/null \
    | sed -n '/^{/,$p' || echo "")

  if [[ -z "$kes_info" ]]; then
    err "$(t "KES 情報を取得できません。ノードが起動しているか確認してください。" "Cannot fetch KES info. Check that the node is running.")"
    press_enter; return
  fi

  local kes_current kes_expiry kes_counter kes_expiry_date slots_per_kes
  kes_current=$(echo "$kes_info"     | jq -r '.qKesCurrentKesPeriod // "0"')
  kes_expiry=$(echo "$kes_info"      | jq -r '.qKesEndKesInterval // "0"')
  kes_counter=$(echo "$kes_info"     | jq -r '.qKesOnDiskOperationalCertificateNumber // "0"')
  kes_expiry_date=$(echo "$kes_info" | jq -r ".qKesKesKeyExpiry // \"$(t "不明" "unknown")\"")
  slots_per_kes=$(echo "$kes_info"   | jq -r '.qKesSlotsPerKesPeriod // 129600')

  local kes_remaining=$(( ${kes_expiry:-0} - ${kes_current:-0} ))
  local kes_days=$(( kes_remaining * slots_per_kes / 86400 ))

  if [[ $kes_remaining -le 0 ]]; then
    echo -e "  $(t "KES 残日数 " "KES days left") : ${FG_RED}$(t "期限切れ" "expired")${NC}$(t "（現在期=${kes_current} / 期限期=${kes_expiry}）" " (current=${kes_current} / end=${kes_expiry})")"
  else
    echo -e "  $(t "KES 残日数 " "KES days left") : ${kes_days}$(t " 日（残り${kes_remaining}期）" " days (${kes_remaining} periods)")"
  fi
  echo -e "  $(t "更新回数   " "Counter    ") : ${kes_counter}"
  echo -e "  $(t "有効期限   " "Expiry     ") : ${kes_expiry_date}"
  echo

  confirm "$(t "更新しますか？" "Update now?")" || return

  _kes_check_schedule       || return
  _kes_step1_generate       || { err "$(t "STEP 1 で問題が発生したため中断します。" "STEP 1 failed; aborting.")"; press_enter; return; }
  _kes_step2_transfer       || return
  _kes_step3_transfer_cert  || return
  _kes_step4_restart
}

_kes_check_schedule() {
  info "$(t "ブロック生成スケジュールを確認中..." "Checking block production schedule...")"

  local db="${NODE_HOME}/cncli/cncli.db"
  if [[ ! -f "$db" ]]; then
    warn "$(t "cncli.db が見つかりません。スケジュール確認をスキップします。" "cncli.db not found; skipping schedule check.")"
    confirm "$(t "このまま続けますか？" "Continue anyway?")" || return 1
    return 0
  fi

  local schedule
  schedule=$(cncli leaderlog \
    --db "$db" \
    --byron-genesis "${NODE_HOME}/byron-genesis.json" \
    --shelley-genesis "${NODE_HOME}/shelley-genesis.json" \
    --pool-id "$(cat ${NODE_HOME}/pool.id)" \
    --pool-vrf-skey "${NODE_HOME}/vrf.skey" \
    --ledger-set current 2>/dev/null || echo "")

  local current_slot
  current_slot=$(cardano-cli latest query tip ${NETWORK} 2>/dev/null | jq -r '.slot // "0"' 2>/dev/null || echo "0")
  current_slot=${current_slot:-0}

  local next_slot
  next_slot=$(echo "$schedule" | jq -r \
    "[.assignedSlots[] | select(.slot > ${current_slot})] | sort_by(.slot) | .[0].slot // 0" \
    2>/dev/null || echo 0)

  if [[ "$next_slot" -gt 0 ]]; then
    local diff=$(( next_slot - current_slot ))
    local diff_min=$(( diff / 60 ))
    local diff_hour=$(( diff_min / 60 ))

    if [[ $diff -lt 3600 ]]; then
      warn "$(t "1時間以内にブロック生成があります（${diff_min}分後）" "A block is scheduled within the hour (in ${diff_min} min)")"
      confirm "$(t "それでも実行しますか？" "Proceed anyway?")" || return 1
    else
      ok "$(t "次のブロック生成まで ${diff_hour}時間$(( diff_min % 60 ))分 あります" "Next block is in ${diff_hour}h $(( diff_min % 60 ))m")"
      confirm "$(t "実行しますか？" "Proceed?")" || return 1
    fi
  else
    ok "$(t "現エポック内にスケジュールはありません" "No blocks scheduled this epoch")"
    confirm "$(t "実行しますか？" "Proceed?")" || return 1
  fi
  return 0
}

_kes_step1_generate() {
  section "$(t "STEP 1: KES キー生成＋オンチェーン情報取得" "STEP 1: Generate KES key + fetch on-chain info")"

  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  [[ -f "${NODE_HOME}/kes.vkey" ]]  && cp "${NODE_HOME}/kes.vkey"  "${NODE_HOME}/kes-bk-${ts}.vkey"
  [[ -f "${NODE_HOME}/kes.skey" ]]  && cp "${NODE_HOME}/kes.skey"  "${NODE_HOME}/kes-bk-${ts}.skey"
  [[ -f "${NODE_HOME}/node.cert" ]] && cp "${NODE_HOME}/node.cert" "${NODE_HOME}/node-bk-${ts}.cert"
  ok "$(t "既存ファイルをバックアップしました（${ts}）" "Backed up existing files (${ts})")"

  if ! cardano-cli latest node key-gen-KES \
    --verification-key-file "${NODE_HOME}/kes.vkey" \
    --signing-key-file "${NODE_HOME}/kes.skey"; then
    err "$(t "KES キーの生成に失敗しました。" "Failed to generate KES key.")"
    # 上書きに失敗している可能性があるためバックアップから復元
    [[ -f "${NODE_HOME}/kes-bk-${ts}.vkey" ]] && cp "${NODE_HOME}/kes-bk-${ts}.vkey" "${NODE_HOME}/kes.vkey"
    [[ -f "${NODE_HOME}/kes-bk-${ts}.skey" ]] && cp "${NODE_HOME}/kes-bk-${ts}.skey" "${NODE_HOME}/kes.skey"
    return 1
  fi
  ok "$(t "新規 kes.vkey / kes.skey を生成しました" "Generated new kes.vkey / kes.skey")"

  warn "$(t "この時点で kes.skey は新しくなり、node.cert は旧のままです。" "kes.skey is now new while node.cert is still the old one.")"
  info "$(t "STEP 4 の再起動までに予期せぬノード再起動が起きると forge が一時停止します。" "If the node restarts unexpectedly before STEP 4, forging will pause.")"
  info "$(t "問題時は kes-bk-${ts}.* / node-bk-${ts}.cert から復元できます。" "On trouble, restore from kes-bk-${ts}.* / node-bk-${ts}.cert.")"

  local chain_counter=""
  if [[ -f "${NODE_HOME}/node-bk-${ts}.cert" ]]; then
    chain_counter=$(cardano-cli latest query kes-period-info \
      --op-cert-file "${NODE_HOME}/node-bk-${ts}.cert" \
      ${NETWORK} 2>/dev/null \
      | sed -n '/^{/,$p' \
      | jq -r '.qKesOnDiskOperationalCertificateNumber // empty')
  fi

  # カウンターは KES 更新で最も事故が多い箇所。
  # クエリ失敗で空のまま +1 すると小さい番号で発行→チェーン拒否でブロック停止になる。
  if [[ ! "$chain_counter" =~ ^[0-9]+$ ]]; then
    err "$(t "オンチェーンの op-cert カウンターを取得できませんでした（取得値: '${chain_counter:-空}'）。" "Could not read the on-chain op-cert counter (got: '${chain_counter:-empty}').")"
    warn "$(t "誤ったカウンターで証明書を発行するとブロック生成が停止します。" "Issuing a cert with the wrong counter will stop block production.")"
    info "$(t "エアギャップの \$HOME/cold-keys/node.counter の値を直接確認してください。" "Check \$HOME/cold-keys/node.counter on the air-gap directly.")"
    info "$(t "issue-op-cert は node.counter の値をそのまま証明書番号に使い、発行後に +1 します。" "issue-op-cert uses the node.counter value as the cert number, then increments it by 1.")"
    confirm "$(t "カウンターを手動で確認できる場合のみ続行してください。続けますか？" "Continue only if you can verify the counter manually. Proceed?")" || return 1
    # 手動入力（誤入力防止のため数値のみ受理）
    local manual=""
    while [[ ! "$manual" =~ ^[0-9]+$ ]]; do
      printf "  %s: " "$(t "新しいカウンター値（次に発行する証明書番号）を入力" "Enter the new counter value (next cert number)")"
      read -r manual
    done
    local new_counter="$manual"
    chain_counter="$(t "(手動)" "(manual)")"
  else
    local new_counter=$(( chain_counter + 1 ))
  fi

  local current_slot
  current_slot=$(cardano-cli latest query tip ${NETWORK} 2>/dev/null | jq -r '.slot // "0"' 2>/dev/null || echo "0")
  current_slot=${current_slot:-0}
  local slots_per_kes
  slots_per_kes=$(jq -r '.slotsPerKESPeriod // "129600"' "${NODE_HOME}/shelley-genesis.json" 2>/dev/null || echo "129600")
  slots_per_kes=${slots_per_kes:-129600}
  local start_kes=$(( current_slot / slots_per_kes ))

  local kes_vkey_hash kes_skey_hash
  kes_vkey_hash=$(sha256sum "${NODE_HOME}/kes.vkey" | awk '{print $1}')
  kes_skey_hash=$(sha256sum "${NODE_HOME}/kes.skey" | awk '{print $1}')

  echo
  echo -e "  $(t "オンチェーンカウンター" "On-chain counter") : ${chain_counter}"
  echo -e "  $(t "新しいカウンター値   " "New counter value") : ${new_counter}"
  echo -e "  startKesPeriod       : ${start_kes}"
  echo
  echo -e "  $(t "kes.vkey ハッシュ" "kes.vkey hash") : ${kes_vkey_hash}"
  echo -e "  $(t "kes.skey ハッシュ" "kes.skey hash") : ${kes_skey_hash}"
  echo -e "${SEP}"

  warn "$(t "発行前に \$HOME/cold-keys/node.counter の現在値を確認し、新カウンター(${new_counter})が妥当か照合してください。" "Before issuing, check the current \$HOME/cold-keys/node.counter and confirm the new counter (${new_counter}) is correct.")"
  copyblock "$(t "エアギャップで実行（コピペ用）" "Run on the air-gapped machine (copy-paste)")" \
    "$(t "# cold-keys ロック解除" "# unlock cold-keys")" \
    "chmod u+rwx \$HOME/cold-keys" \
    "" \
    "$(t "# 現在のカウンターを確認（任意・照合用）" "# check the current counter (optional, for verification)")" \
    "cat \$HOME/cold-keys/node.counter" \
    "" \
    "cd \${NODE_HOME}" \
    "cardano-cli latest node new-counter \\" \
    "  --cold-verification-key-file \$HOME/cold-keys/node.vkey \\" \
    "  --counter-value ${new_counter} \\" \
    "  --operational-certificate-issue-counter-file \\" \
    "    \$HOME/cold-keys/node.counter" \
    "" \
    "cardano-cli latest node issue-op-cert \\" \
    "  --kes-verification-key-file \${NODE_HOME}/kes.vkey \\" \
    "  --cold-signing-key-file \$HOME/cold-keys/node.skey \\" \
    "  --operational-certificate-issue-counter \\" \
    "    \$HOME/cold-keys/node.counter \\" \
    "  --kes-period ${start_kes} \\" \
    "  --out-file \${NODE_HOME}/node.cert" \
    "" \
    "$(t "# cold-keys 再ロック" "# re-lock cold-keys")" \
    "chmod a-rwx \$HOME/cold-keys"

  export _KES_VK_HASH="$kes_vkey_hash"
  export _KES_SK_HASH="$kes_skey_hash"
}

_kes_step2_transfer() {
  section "$(t "STEP 2: kes.vkey / kes.skey をエアギャップへ転送" "STEP 2: Transfer kes.vkey / kes.skey to the air-gap")"

  echo -e "  $(t "BP から USB に kes.vkey / kes.skey をコピーして、エアギャップマシンに転送してください。" "Copy kes.vkey / kes.skey from the BP to USB and move them to the air-gapped machine.")"
  echo
  copyblock "$(t "エアギャップで実行（ハッシュ確認）" "Run on the air-gapped machine (hash check)")" \
    "sha256sum \${NODE_HOME}/kes.vkey" \
    "sha256sum \${NODE_HOME}/kes.skey"
  echo -e "  ${FG_GRAY}$(t "BP 側のハッシュ値：" "BP-side hashes:")${NC}"
  echo -e "  ${FG_GRAY}  kes.vkey : ${_KES_VK_HASH}${NC}"
  echo -e "  ${FG_GRAY}  kes.skey : ${_KES_SK_HASH}${NC}"
  echo

  press_enter "$(t "kes ファイルの転送とハッシュ確認が完了したら Enter を押してください" "Press Enter once the kes files are transferred and the hashes match")"
}

_kes_step3_transfer_cert() {
  section "$(t "STEP 3: node.cert をエアギャップで生成して BP へ転送" "STEP 3: Generate node.cert on the air-gap and transfer it to the BP")"

  echo -e "  $(t "STEP 1 のコマンドをエアギャップで実行してください。" "Run the STEP 1 commands on the air-gapped machine.")"
  echo -e "  $(t "生成した node.cert を USB 経由で BP（\${NODE_HOME}/）にコピーしてください。" "Copy the resulting node.cert to the BP (\${NODE_HOME}/) via USB.")"
  echo

  press_enter "$(t "node.cert の転送が完了したら Enter を押してください" "Press Enter once node.cert has been transferred")"

  if [[ -f "${NODE_HOME}/node.cert" ]]; then
    local cert_hash
    cert_hash=$(sha256sum "${NODE_HOME}/node.cert" | awk '{print $1}')
    echo
    echo -e "  $(t "node.cert ハッシュ" "node.cert hash") : ${cert_hash}"
    warn "$(t "エアギャップ側と同じ値であることを確認してください" "Confirm this matches the value on the air-gap")"
    press_enter "$(t "確認できたら Enter を押してください" "Press Enter once confirmed")"
  fi
}

_kes_step4_restart() {
  section "$(t "STEP 4: ノード再起動・KES 確認" "STEP 4: Restart node & verify KES")"

  confirm "$(t "ノードを再起動しますか？" "Restart the node now?")" || return

  local service_name
  service_name=$(systemctl list-units --type=service 2>/dev/null \
    | grep -m1 -i cardano | awk '{print $1}')
  service_name=${service_name:-cardano-node}

  info "$(t "ノードを再起動中..." "Restarting the node...")"
  if ! sudo systemctl restart "${service_name}" 2>/dev/null; then
    err "$(t "ノードの再起動に失敗しました。手動で再起動してください。" "Failed to restart the node. Please restart it manually.")"
    press_enter; return
  fi

  info "$(t "KES 状態を確認中（30秒待機）..." "Checking KES status (waiting 30s)...")"
  sleep 30

  local kes_info
  kes_info=$(cardano-cli latest query kes-period-info \
    --op-cert-file "${NODE_HOME}/node.cert" \
    ${NETWORK} 2>/dev/null \
    | sed -n '/^{/,$p' || echo "")

  local kes_healthy=false
  if [[ -n "$kes_info" ]]; then
    local kes_interval_ok disk_counter state_counter
    kes_interval_ok=$(echo "$kes_info" | jq -r \
      '.qKesEndKesInterval > .qKesCurrentKesPeriod')
    disk_counter=$(echo "$kes_info"  | jq -r '.qKesOnDiskOperationalCertificateNumber // "?"')
    state_counter=$(echo "$kes_info" | jq -r '.qKesNodeStateOperationalCertificateNumber // "?"')

    echo
    info "$(t "KES 期間が有効      " "KES interval valid ") : ${kes_interval_ok}"
    info "$(t "ディスク上カウンター" "On-disk counter    ") : ${disk_counter}"
    info "$(t "ノード状態カウンター" "Node-state counter ") : ${state_counter}"

    # 新 cert のカウンターは旧チェーン状態より 1 大きいのが正常
    if [[ "$kes_interval_ok" == "true" ]] \
       && [[ "$disk_counter" =~ ^[0-9]+$ ]] && [[ "$state_counter" =~ ^[0-9]+$ ]] \
       && [[ "$disk_counter" -ge "$state_counter" ]]; then
      kes_healthy=true
      ok "$(t "KES 状態は正常です（期間有効・カウンター整合）" "KES status is healthy (interval valid, counters consistent)")"
    else
      err "$(t "KES 状態に問題がある可能性があります。設定を確認してください。" "KES status may be wrong. Please check your setup.")"
    fi
  else
    err "$(t "再起動後の KES 情報を取得できませんでした。ノードのログを確認してください。" "Could not fetch KES info after restart. Check the node logs.")"
  fi

  echo
  warn "$(t "カウンターがチェーンに受理され実際に forge できるか確認できるのは次のブロック生成時です。" "Whether the counter is accepted on-chain and forging works can only be confirmed at the next block.")"
  warn "$(t "それまでバックアップ（kes-bk-* / node-bk-*）は削除しないことを推奨します。" "Until then, keep the backups (kes-bk-* / node-bk-*).")"
  if [[ "$kes_healthy" == "true" ]]; then
    confirm "$(t "それでも今すぐバックアップを削除しますか？" "Delete the backups now anyway?")" && {
      rm -f "${NODE_HOME}"/kes-bk-*.vkey "${NODE_HOME}"/kes-bk-*.skey "${NODE_HOME}"/node-bk-*.cert
      ok "$(t "バックアップファイルを削除しました" "Backup files deleted")"
    }
  else
    info "$(t "状態が確認できていないため、バックアップは保持します。" "Status unconfirmed, so backups are kept.")"
  fi
  press_enter
}

# =============================================================================
#  [4] プール情報を更新する
# =============================================================================

menu_pool_update() {
  clear
  section "$(t "プール情報を更新する" "Update pool info")"

  info "$(t "現在のプール設定を取得中..." "Fetching current pool settings...")"
  local pool_info
  pool_info=$(get_pool_info)

  if [[ -z "$pool_info" ]]; then
    warn "$(t "Koios からプール情報を取得できませんでした" "Could not fetch pool info from Koios")"
    info "$(t "pool.id / pool.id-bech32 が ${NODE_HOME}/ に存在するか確認してください" "Check that pool.id / pool.id-bech32 exist in ${NODE_HOME}/")"
    press_enter; return
  fi

  local pledge=0 margin=0 cost=0 name="" ticker="" desc="" homepage="" meta_url="" ext_url=""

  if [[ -n "$pool_info" ]]; then
    pledge=$(echo "$pool_info"   | jq -r '.pledge // 0')
    margin=$(echo "$pool_info"   | jq -r '.margin // 0')
    cost=$(echo "$pool_info"     | jq -r '.fixed_cost // 0')
    name=$(echo "$pool_info"     | jq -r '.meta_json.name // ""')
    ticker=$(echo "$pool_info"   | jq -r '.meta_json.ticker // ""')
    desc=$(echo "$pool_info"     | jq -r '.meta_json.description // ""')
    homepage=$(echo "$pool_info" | jq -r '.meta_json.homepage // ""')
    meta_url=$(echo "$pool_info" | jq -r '.meta_url // ""')
  fi

  local pledge_ada margin_pct cost_ada
  pledge_ada=$(format_ada "$pledge")
  margin_pct=$(awk "BEGIN { printf \"%.1f\", ${margin} * 100 }")
  cost_ada=$(format_ada "$cost")

  echo -e "  ${FG_CYAN}── $(t "現在のプール設定" "Current pool settings")${NC}"
  echo -e "  pledge   : ${pledge_ada} ADA"
  echo -e "  margin   : ${margin_pct} %"
  echo -e "  cost     : ${cost_ada} ADA"
  echo -e "  name     : ${name}"
  echo -e "  ticker   : ${ticker}"
  echo -e "  desc     : ${desc:0:50}"
  echo -e "  homepage : ${homepage}"
  echo -e "  metadata : ${meta_url}"
  [[ -n "$ext_url" ]] && echo -e "  extended : ${ext_url}"
  echo -e "${SEP}"
  echo

  echo -e "  ${FG_WHITE}$(t "変更する番号を入力してください（複数可、例: 1 3 4）" "Enter the numbers to change (multiple allowed, e.g. 1 3 4)")${NC}"
  echo -e "  ${FG_GRAY}  1: pledge  2: margin  3: cost  4: metadata  5: extended URL${NC}"
  echo -e "  ${FG_GRAY}  $(t "b: 戻る" "b: back")${NC}"
  echo -en "  > "
  local nums
  read -r nums
  [[ -z "$nums" || "$nums" == "b" || "$nums" == "q" ]] && return

  local change_pledge=false change_margin=false change_cost=false
  local change_meta=false change_ext=false

  for n in $nums; do
    case $n in
      1) change_pledge=true ;;
      2) change_margin=true ;;
      3) change_cost=true ;;
      4) change_meta=true ;;
      5) change_ext=true ;;
    esac
  done

  [[ "$change_pledge" == "true" ]] && {
    echo -en "  ${FG_WHITE}$(t "pledge（ADA）" "pledge (ADA)")：${NC} "
    local new_pledge_ada; read -r new_pledge_ada
    pledge=$(ada_to_lovelace "$new_pledge_ada")
    pledge_ada="$new_pledge_ada"
  }
  [[ "$change_margin" == "true" ]] && {
    echo -en "  ${FG_WHITE}$(t "margin（%、例: 3.0）" "margin (%, e.g. 3.0)")：${NC} "
    read -r margin_pct
    margin=$(awk "BEGIN { printf \"%.6f\", ${margin_pct}/100 }")
  }
  [[ "$change_cost" == "true" ]] && {
    echo -en "  ${FG_WHITE}$(t "cost（ADA）" "cost (ADA)")：${NC} "
    local new_cost_ada; read -r new_cost_ada
    cost=$(ada_to_lovelace "$new_cost_ada")
    cost_ada="$new_cost_ada"
  }
  [[ "$change_meta" == "true" ]] && {
    echo -en "  ${FG_WHITE}name：${NC} ";        read -r name
    echo -en "  ${FG_WHITE}ticker：${NC} ";      read -r ticker
    echo -en "  ${FG_WHITE}description：${NC} "; read -r desc
    echo -en "  ${FG_WHITE}homepage：${NC} ";    read -r homepage
    echo -en "  ${FG_WHITE}metadata URL：${NC} "; read -r meta_url

    jq -n \
      --arg name "$name" --arg ticker "$ticker" \
      --arg description "$desc" --arg homepage "$homepage" \
      '{name: $name, ticker: $ticker, description: $description, homepage: $homepage}' \
      > "${NODE_HOME}/poolMetaData.json"

    local meta_hash
    meta_hash=$(cardano-cli latest stake-pool metadata-hash \
      --pool-metadata-file "${NODE_HOME}/poolMetaData.json")
    echo "$meta_hash" > "${NODE_HOME}/poolMetaDataHash.txt"
    ok "$(t "poolMetaData.json を生成しました（hash: ${meta_hash}）" "Generated poolMetaData.json (hash: ${meta_hash})")"
    warn "$(t "poolMetaData.json をサーバーにアップロードしてください" "Upload poolMetaData.json to your server")"
    press_enter "$(t "アップロード完了後、Enter を押してください" "Press Enter once the upload is complete")"
  }
  [[ "$change_ext" == "true" ]] && {
    echo -en "  ${FG_WHITE}extended metadata URL：${NC} "; read -r ext_url
  }

  echo
  echo -e "  ${FG_CYAN}── $(t "変更後の設定（確認）" "New settings (review)")${NC}"
  echo -e "  pledge   : ${pledge_ada} ADA（${pledge} lovelace）"
  echo -e "  margin   : ${margin_pct} %（${margin}）"
  echo -e "  cost     : ${cost_ada} ADA（${cost} lovelace）"
  echo -e "  name     : ${name}"
  echo -e "  ticker   : ${ticker}"
  echo -e "  metadata : ${meta_url}"
  [[ -n "$ext_url" ]] && echo -e "  extended : ${ext_url}"
  echo -e "${SEP}"

  confirm "$(t "この内容で pool.cert を生成しますか？" "Generate pool.cert with these settings?")" || return

  _pool_update_trip1 "$pledge" "$margin" "$cost" "$meta_url"
  _pool_update_trip2
}

_pool_update_trip1() {
  local pledge="$1" margin="$2" cost="$3" meta_url="$4"

  section "$(t "TRIP 1: BP → エアギャップ（pool.cert 生成）" "TRIP 1: BP → air-gap (generate pool.cert)")"

  get_params

  local meta_hash=""
  [[ -f "${NODE_HOME}/poolMetaDataHash.txt" ]] && meta_hash=$(cat "${NODE_HOME}/poolMetaDataHash.txt")

  local relay_ip="${RELAY1_IP:-}"
  if [[ -z "$relay_ip" ]]; then
    echo -en "  ${FG_WHITE}$(t "リレーの IP アドレス" "Relay IP address")：${NC} "
    read -r relay_ip
  fi

  copyblock "$(t "エアギャップで実行（コピペ用）" "Run on the air-gapped machine (copy-paste)")" \
    "$(t "# cold-keys ロック解除" "# unlock cold-keys")" \
    "chmod u+rwx \$HOME/cold-keys" \
    "" \
    "cardano-cli latest stake-pool registration-certificate \\" \
    "  --cold-verification-key-file \$HOME/cold-keys/node.vkey \\" \
    "  --vrf-verification-key-file \${NODE_HOME}/vrf.vkey \\" \
    "  --pool-pledge ${pledge} \\" \
    "  --pool-cost ${cost} \\" \
    "  --pool-margin ${margin} \\" \
    "  --pool-reward-account-verification-key-file \${NODE_HOME}/stake.vkey \\" \
    "  --pool-owner-stake-verification-key-file \${NODE_HOME}/stake.vkey \\" \
    "  --mainnet \\" \
    "  --pool-relay-ipv4 ${relay_ip} \\" \
    "  --pool-relay-port 6000 \\" \
    "  --metadata-url ${meta_url} \\" \
    "  --metadata-hash ${meta_hash} \\" \
    "  --out-file \${NODE_HOME}/pool.cert" \
    "" \
    "$(t "# cold-keys 再ロック" "# re-lock cold-keys")" \
    "chmod a-rwx \$HOME/cold-keys"

  echo -e "  $(t "USB 経由でエアギャップへ転送するファイル：" "Files to transfer to the air-gap via USB:")"
  echo -e "  ${FG_GRAY}  - \${NODE_HOME}/vrf.vkey${NC}"
  [[ -n "$meta_url" ]] && echo -e "  ${FG_GRAY}  - \${NODE_HOME}/poolMetaData.json${NC}"
  echo -e "  ${FG_GRAY}  - \${NODE_HOME}/params.json${NC}"
  echo

  press_enter "$(t "pool.cert を生成して BP に転送したら Enter を押してください" "Press Enter once pool.cert is generated and transferred to the BP")"
}

_pool_update_trip2() {
  section "$(t "TRIP 2: Tx 作成→エアギャップ（署名）" "TRIP 2: Build tx → air-gap (sign)")"

  info "$(t "tx.raw を作成中です。しばらくお待ちください…" "Building tx.raw, please wait…")"
  info "$(t "（作成後、この tx.raw をエアギャップに貼り付けて署名します）" "(after building, paste this tx.raw on the air-gap and sign it)")"
  local result pay_balance tx_in
  result=$(get_payment_balance)
  pay_balance=$(awk '{print $1}' <<< "${result}")
  tx_in=$(awk '{$1=""; print $0}' <<< "${result}")

  get_params

  cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+0" \
    --certificate-file "${NODE_HOME}/pool.cert" \
    --invalid-hereafter 0 --fee 0 \
    --out-file "${NODE_HOME}/tx.draft" 2>/dev/null

  local fee
  fee=$(cardano-cli latest transaction calculate-min-fee \
    --tx-body-file "${NODE_HOME}/tx.draft" \
    --protocol-params-file "${NODE_HOME}/params.json" \
    --tx-in-count "$(count_tx_ins "$tx_in")" --tx-out-count 1 --witness-count 3 \
    2>/dev/null)
  fee=$(parse_fee "$fee")

  local change=$(( pay_balance - fee ))
  local ttl; ttl=$(get_ttl)

  cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+${change}" \
    --certificate-file "${NODE_HOME}/pool.cert" \
    --invalid-hereafter ${ttl} --fee ${fee} \
    --out-file "${NODE_HOME}/tx.raw" 2>/dev/null

  ok "$(t "tx.raw を生成しました" "Built tx.raw")"
  show_txraw
  show_airgap_sign_node "tx.raw" "tx.signed"
  if tx_submit "tx.signed"; then
    ok "$(t "プール情報を更新しました" "Pool info updated")"
  else
    err "$(t "プール情報は更新されていません（送信に失敗）。上記エラーを確認してください。" "Pool info was NOT updated (submission failed). Check the error above.")"
  fi
  press_enter
}

# =============================================================================
#  [5] DRep へ委任をする
# =============================================================================

menu_drep_delegate() {
  clear
  section "$(t "DRep へ委任をする" "Delegate to a DRep")"

  info "$(t "現在の DRep 委任状況を確認中..." "Checking current DRep delegation...")"
  local stake_addr
  stake_addr=$(cat "${NODE_HOME}/stake.addr" 2>/dev/null || echo "")
  local drep_delegation=""

  if [[ -n "$stake_addr" ]]; then
    drep_delegation=$(curl -s "https://api.koios.rest/api/v1/account_info" \
      -H "Content-Type: application/json" \
      -d "{\"_stake_addresses\":[\"${stake_addr}\"]}" 2>/dev/null \
      | jq -r '.[0].drep_id // ""')
  fi

  echo
  local drep_display
  case "${drep_delegation}" in
    "") drep_display="$(t "未委任" "not delegated")" ;;
    drep_always_abstain) drep_display="$(t "棄権（always-abstain）" "abstain (always-abstain)")" ;;
    drep_always_no_confidence) drep_display="$(t "不信任（always-no-confidence）" "no-confidence (always-no-confidence)")" ;;
    *) drep_display="${drep_delegation}" ;;
  esac
  echo -e "  $(t "現在の委任先" "Current delegation") : ${drep_display}"
  echo -e "${SEP}"
  echo

  menu_select "$(t "委任方法を選択" "Choose delegation")" \
    "[1]  $(t "DRep に委任する" "Delegate to a DRep")" \
    "[2]  $(t "棄権する（always-abstain）" "Abstain (always-abstain)")" \
    "[3]  $(t "不信任にする（always-no-confidence）" "No-confidence (always-no-confidence)")" \
    "[b]  $(t "戻る" "Back")"
  local choice=$?

  local drep_opt=""

  case $choice in
    0)
      echo -en "  ${FG_WHITE}$(t "DRep ID（drep1... / b: 戻る）" "DRep ID (drep1... / b: back)")：${NC} "
      local drep_id; read -r drep_id
      [[ -z "$drep_id" || "$drep_id" == "b" || "$drep_id" == "q" ]] && return

      info "$(t "DRep 情報を確認中..." "Checking DRep info...")"
      local drep_info
      drep_info=$(get_drep_info "$drep_id")

      if [[ -z "$drep_info" ]]; then
        err "$(t "DRep が見つかりませんでした" "DRep not found"): ${drep_id}"
        press_enter; return
      fi

      local drep_name
      drep_name=$(echo "$drep_info" | jq -r ".given_name // \"$(t "不明" "unknown")\"")
      echo -e "  DRep ID : ${drep_id}"
      echo -e "  $(t "DRep 名" "DRep name") : ${drep_name}"
      echo

      confirm "$(t "この DRep に委任しますか？" "Delegate to this DRep?")" || return
      drep_opt="--drep-key-hash ${drep_id}"
      ;;
    1) confirm "$(t "常に棄権（always-abstain）に設定しますか？" "Set to always abstain (always-abstain)?")" || return
       drep_opt="--always-abstain" ;;
    2) confirm "$(t "常に不信任（always-no-confidence）に設定しますか？" "Set to always no-confidence (always-no-confidence)?")" || return
       drep_opt="--always-no-confidence" ;;
    99) return ;;
  esac

  mkdir -p "${GOVERNANCE_DIR}"

  # shellcheck disable=SC2086
  cardano-cli latest stake-address vote-delegation-certificate \
    --stake-verification-key-file "${NODE_HOME}/stake.vkey" \
    ${drep_opt} \
    --out-file "${GOVERNANCE_DIR}/drep-deleg.cert"
  ok "$(t "drep-deleg.cert を生成しました" "Built drep-deleg.cert")"

  # 古い tx を必ず削除（再署名されないまま古い署名ファイルを送信する事故を防ぐ）
  rm -f "${GOVERNANCE_DIR}/tx.raw" "${GOVERNANCE_DIR}/tx.signed" "${NODE_HOME}/tx.draft"

  info "$(t "tx.raw を作成中です。しばらくお待ちください…" "Building tx.raw, please wait…")"
  info "$(t "（作成後、この tx.raw をエアギャップに貼り付けて署名します）" "(after building, paste this tx.raw on the air-gap and sign it)")"
  local result pay_balance tx_in
  result=$(get_payment_balance)
  pay_balance=$(awk '{print $1}' <<< "${result}")
  tx_in=$(awk '{$1=""; print $0}' <<< "${result}")

  if [[ -z "${tx_in// /}" || ! "$pay_balance" =~ ^[0-9]+$ || "$pay_balance" -eq 0 ]]; then
    err "$(t "payment アドレスに利用可能な UTxO がありません（残高: ${pay_balance}）。" "No usable UTxO at the payment address (balance: ${pay_balance}).")"
    info "$(t "ノードが同期しているか、payment.addr に資金があるか確認してください。" "Check that the node is synced and payment.addr has funds.")"
    press_enter; return
  fi
  info "$(t "使用する入力: ${tx_in# }" "Using input: ${tx_in# }")"

  get_params

  cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+0" \
    --certificate-file "${GOVERNANCE_DIR}/drep-deleg.cert" \
    --invalid-hereafter 0 --fee 0 \
    --out-file "${NODE_HOME}/tx.draft" 2>/dev/null

  local fee
  fee=$(cardano-cli latest transaction calculate-min-fee \
    --tx-body-file "${NODE_HOME}/tx.draft" \
    --protocol-params-file "${NODE_HOME}/params.json" \
    --tx-in-count "$(count_tx_ins "$tx_in")" --tx-out-count 1 --witness-count 2 \
    2>/dev/null)
  fee=$(parse_fee "$fee")

  local change=$(( pay_balance - fee ))
  local ttl; ttl=$(get_ttl)

  local build_err
  build_err=$(cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+${change}" \
    --certificate-file "${GOVERNANCE_DIR}/drep-deleg.cert" \
    --invalid-hereafter ${ttl} --fee ${fee} \
    --out-file "${GOVERNANCE_DIR}/tx.raw" 2>&1)

  if [[ ! -s "${GOVERNANCE_DIR}/tx.raw" ]]; then
    err "$(t "tx.raw のビルドに失敗しました。" "Failed to build tx.raw.")"
    [[ -n "$build_err" ]] && echo -e "  ${FG_GRAY}${build_err}${NC}"
    press_enter; return
  fi

  show_txraw "tx.raw"
  show_airgap_sign_stake "tx.raw" "tx.signed"
  if tx_submit "tx.signed"; then
    ok "$(t "DRep 委任が完了しました" "DRep delegation complete")"
  else
    err "$(t "DRep 委任は完了していません（送信に失敗）。上記エラーを確認してください。" "DRep delegation did NOT complete (submission failed). Check the error above.")"
  fi
  press_enter
}

# =============================================================================
#  [6] ガバナンス投票をする
# =============================================================================

menu_governance_vote() {
  clear
  section "$(t "ガバナンス投票をする" "Governance vote")"

  mkdir -p "${GOVERNANCE_DIR}"

  info "$(t "SPO 投票可能なガバナンスアクションを取得中..." "Fetching governance actions an SPO can vote on...")"
  local gov_state
  gov_state=$(cardano-cli latest query gov-state ${NETWORK} 2>/dev/null || echo "")

  if [[ -z "$gov_state" ]]; then
    err "$(t "ガバナンス状態を取得できません" "Cannot fetch governance state")"
    press_enter; return
  fi

  local actions
  actions=$(echo "$gov_state" | jq -r '
    .proposals[] |
    select(
      .proposalProcedure.govAction.tag == "HardForkInitiation" or
      .proposalProcedure.govAction.tag == "ParameterChange" or
      .proposalProcedure.govAction.tag == "NoConfidence" or
      .proposalProcedure.govAction.tag == "UpdateCommittee"
    ) |
    "\(.actionId.txId)|\(.actionId.govActionIx)|\(.proposalProcedure.govAction.tag)|\(.proposalProcedure.anchor.url // "")|\(.proposalProcedure.anchor.dataHash // "")"
  ' 2>/dev/null || echo "")

  local action_ids=() action_idxs=() action_types=() action_urls=() action_hashes=()
  if [[ -n "$actions" ]]; then
    while IFS='|' read -r aid aidx atype aurl ahash; do
      action_ids+=("$aid")
      action_idxs+=("$aidx")
      action_types+=("$atype")
      action_urls+=("$aurl")
      action_hashes+=("$ahash")
    done <<< "$actions"
  fi

  if [[ ${#action_ids[@]} -eq 0 ]]; then
    info "$(t "現在投票可能な提案はありません" "No proposals available to vote on right now")"
    press_enter; return
  fi

  local menu_items=()
  for ((i=0; i<${#action_ids[@]}; i++)); do
    menu_items+=("[$(( i+1 ))]  ${action_types[$i]} — ${action_ids[$i]}#${action_idxs[$i]}")
  done
  menu_items+=("[m]  $(t "ガバナンスアクション ID を手動入力" "Enter a governance action ID manually")")
  menu_items+=("[b]  $(t "戻る" "Back")")

  echo
  menu_select "$(t "投票する提案を選択" "Choose a proposal to vote on")" "${menu_items[@]}"
  local choice=$?

  local action_id="" action_index="0"

  if [[ $choice -eq 99 ]]; then
    return
  elif [[ $choice -eq $(( ${#menu_items[@]} - 2 )) ]]; then
    echo -en "  ${FG_WHITE}$(t "Action ID（例: txhash#0 / b: 戻る）" "Action ID (e.g. txhash#0 / b: back)")：${NC} "
    local raw_input; read -r raw_input
    [[ -z "$raw_input" || "$raw_input" == "b" || "$raw_input" == "q" ]] && return
    if [[ "$raw_input" == *"#"* ]]; then
      action_id="${raw_input%#*}"
      action_index="${raw_input##*#}"
    else
      action_id="$raw_input"
      action_index="0"
      warn "$(t "インデックス指定がないため #0 とみなします。" "No index given; assuming #0.")"
    fi
  elif [[ $choice -lt ${#action_ids[@]} ]]; then
    action_id="${action_ids[$choice]}"
    action_index="${action_idxs[$choice]}"
    local anchor_url="${action_urls[$choice]}"
    local anchor_expected="${action_hashes[$choice]}"

    if [[ -n "$anchor_url" ]]; then
      info "$(t "アンカーデータを確認中..." "Verifying anchor data...")"
      local anchor_hash
      # ipfs:// アンカーは IPFS_GATEWAY_URI が必須。未設定なら公開ゲートウェイを既定にする。
      anchor_hash=$(IPFS_GATEWAY_URI="${IPFS_GATEWAY_URI:-https://ipfs.io}" \
        cardano-cli hash anchor-data --url "$anchor_url" 2>/dev/null || echo "")
      echo -e "  $(t "種別" "Type") : ${action_types[$choice]}"
      echo -e "  URL  : ${anchor_url}"
      if [[ -z "$anchor_hash" ]]; then
        warn "$(t "アンカーデータを取得できませんでした（URL到達不可の可能性）" "Could not fetch anchor data (URL may be unreachable)")"
      elif [[ "$anchor_hash" == "$anchor_expected" ]]; then
        ok "$(t "ハッシュ検証: 一致（オンチェーン値と一致）" "Hash check: match (matches the on-chain value)")"
      else
        err "$(t "ハッシュ不一致！ 改ざんの可能性があります。" "Hash mismatch! The data may have been tampered with.")"
        echo -e "  $(t "オンチェーン" "On-chain") : ${anchor_expected}"
        echo -e "  $(t "実取得      " "Fetched ") : ${anchor_hash}"
        confirm "$(t "それでも投票を続けますか？" "Vote anyway?")" || return
      fi
      echo
    fi
  fi

  menu_select "$(t "投票内容を選択" "Choose your vote")" "[1]  Yes" "[2]  No" "[3]  Abstain" "[b]  $(t "戻る" "Back")"
  local vote_choice=$?

  local vote_opt="" vote_label=""
  case $vote_choice in
    0) vote_opt="--yes";     vote_label="Yes" ;;
    1) vote_opt="--no";      vote_label="No" ;;
    2) vote_opt="--abstain"; vote_label="Abstain" ;;
    99) return ;;
  esac

  local rationale_opts=""
  confirm "$(t "rationale（投票理由）を添付しますか？" "Attach a rationale (reason for the vote)?")" && {
    echo -en "  ${FG_WHITE}$(t "rationale の URL" "Rationale URL")：${NC} "
    local rationale_url; read -r rationale_url
    info "$(t "ハッシュを計算中..." "Computing hash...")"
    local rationale_hash
    rationale_hash=$(IPFS_GATEWAY_URI="${IPFS_GATEWAY_URI:-https://ipfs.io}" \
      cardano-cli hash anchor-data --url "$rationale_url" 2>/dev/null || echo "")
    echo -e "  URL  : ${rationale_url}"
    echo -e "  Hash : ${rationale_hash}"
    if [[ -z "$rationale_hash" ]]; then
      warn "$(t "rationale のハッシュを取得できませんでした。rationale なしで続行します。" "Could not get the rationale hash; continuing without a rationale.")"
    else
      rationale_opts="--anchor-url ${rationale_url} --anchor-data-hash ${rationale_hash}"
    fi
  }

  echo
  echo -e "  ${FG_CYAN}── $(t "投票内容の確認" "Review your vote")${NC}"
  echo -e "  $(t "提案     " "Proposal ") : ${action_id}"
  echo -e "  $(t "投票     " "Vote     ") : ${vote_label}"
  [[ -n "$rationale_opts" ]] && echo -e "  rationale : $(t "あり" "yes")"
  [[ -z "$rationale_opts" ]] && echo -e "  rationale : $(t "なし" "no")"
  echo -e "${SEP}"

  confirm "$(t "この内容で投票しますか？" "Cast this vote?")" || return

  # vote create はコールド検証鍵(node.vkey)を要求するため、エアギャップで実行する。
  rm -f "${GOVERNANCE_DIR}/vote.json"

  section "$(t "STEP A: エアギャップで vote.json を生成" "STEP A: Generate vote.json on the air-gap")"
  local cl=()
  cl+=("$(t "# cold-keys ロック解除" "# unlock cold-keys")")
  cl+=("chmod u+rwx \$HOME/cold-keys")
  cl+=("")
  cl+=("cardano-cli conway governance vote create \\")
  cl+=("  ${vote_opt} \\")
  cl+=("  --governance-action-tx-id ${action_id} \\")
  cl+=("  --governance-action-index ${action_index} \\")
  cl+=("  --cold-verification-key-file \$HOME/cold-keys/node.vkey \\")
  [[ -n "$rationale_opts" ]] && cl+=("  ${rationale_opts} \\")
  cl+=("  --out-file \$HOME/vote.json")
  cl+=("")
  cl+=("$(t "# cold-keys 再ロック" "# re-lock cold-keys")")
  cl+=("chmod a-rwx \$HOME/cold-keys")
  cl+=("")
  cl+=("$(t "# vote.json を BP 貼り付け用のヒアドキュメント形式で表示" "# print vote.json as a heredoc to paste on the BP")")
  cl+=("{ echo \"cat > vote.json << EOF\"; cat \$HOME/vote.json; echo; echo EOF; }")
  copyblock "$(t "エアギャップで実行（コピペ用）" "Run on the air-gapped machine (copy-paste)")" "${cl[@]}"

  echo
  info "$(t "上記の最後の出力（cat > vote.json << EOF … EOF）を、" "Run the last output above (cat > vote.json << EOF … EOF)")"
  info "$(t "BP の ${NODE_HOME} で実行すると vote.json が作成されます。" "in ${NODE_HOME} on the BP to create vote.json.")"
  echo
  if confirm "$(t "代わりに ctool に直接貼り付けて取り込みますか？（heredocで作成済みなら No）" "Paste it into ctool directly instead? (No if you already created it via heredoc)")"; then
    paste_signed_file "${GOVERNANCE_DIR}/vote.json" || { press_enter; return; }
  else
    press_enter "$(t "vote.json を ${GOVERNANCE_DIR}/ に用意したら Enter を押してください" "Place vote.json in ${GOVERNANCE_DIR}/ then press Enter")"
  fi

  if [[ ! -s "${GOVERNANCE_DIR}/vote.json" ]]; then
    err "$(t "vote.json が取り込めていません。" "vote.json was not imported.")"
    press_enter; return
  fi
  ok "$(t "vote.json を取り込みました" "vote.json imported")"

  section "$(t "STEP B: 投票 tx をビルド → エアギャップ署名 → 送信" "STEP B: Build vote tx → air-gap sign → submit")"

  # 古い tx を必ず削除（再署名されないまま古い署名ファイルを送信する事故を防ぐ）
  rm -f "${GOVERNANCE_DIR}/tx.raw" "${GOVERNANCE_DIR}/tx.signed" "${NODE_HOME}/tx.draft"

  info "$(t "tx.raw を作成中です。しばらくお待ちください…" "Building tx.raw, please wait…")"
  info "$(t "（作成後、この tx.raw をエアギャップに貼り付けて署名します）" "(after building, paste this tx.raw on the air-gap and sign it)")"
  local result pay_balance tx_in
  result=$(get_payment_balance)
  pay_balance=$(awk '{print $1}' <<< "${result}")
  tx_in=$(awk '{$1=""; print $0}' <<< "${result}")

  if [[ -z "${tx_in// /}" || ! "$pay_balance" =~ ^[0-9]+$ || "$pay_balance" -eq 0 ]]; then
    err "$(t "payment アドレスに利用可能な UTxO がありません（残高: ${pay_balance}）。" "No usable UTxO at the payment address (balance: ${pay_balance}).")"
    info "$(t "ノードが同期しているか、payment.addr に資金があるか確認してください。" "Check that the node is synced and payment.addr has funds.")"
    press_enter; return
  fi
  info "$(t "使用する入力: ${tx_in# }" "Using input: ${tx_in# }")"

  get_params

  cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+0" \
    --vote-file "${GOVERNANCE_DIR}/vote.json" \
    --invalid-hereafter 0 --fee 0 \
    --out-file "${NODE_HOME}/tx.draft" 2>/dev/null

  local fee
  fee=$(cardano-cli latest transaction calculate-min-fee \
    --tx-body-file "${NODE_HOME}/tx.draft" \
    --protocol-params-file "${NODE_HOME}/params.json" \
    --tx-in-count "$(count_tx_ins "$tx_in")" --tx-out-count 1 --witness-count 2 \
    2>/dev/null)
  fee=$(parse_fee "$fee")

  local change=$(( pay_balance - fee ))
  local ttl; ttl=$(get_ttl)

  local build_err
  build_err=$(cardano-cli latest transaction build-raw \
    ${tx_in} \
    --tx-out "$(cat ${NODE_HOME}/payment.addr)+${change}" \
    --vote-file "${GOVERNANCE_DIR}/vote.json" \
    --invalid-hereafter ${ttl} --fee ${fee} \
    --out-file "${GOVERNANCE_DIR}/tx.raw" 2>&1)

  if [[ ! -s "${GOVERNANCE_DIR}/tx.raw" ]]; then
    err "$(t "tx.raw のビルドに失敗しました。" "Failed to build tx.raw.")"
    [[ -n "$build_err" ]] && echo -e "  ${FG_GRAY}${build_err}${NC}"
    press_enter; return
  fi

  show_txraw "tx.raw"
  show_airgap_sign_node "tx.raw" "tx.signed"
  if tx_submit "tx.signed"; then
    ok "$(t "投票が完了しました" "Vote submitted")"
    echo -e "  $(t "提案" "Proposal") : ${action_id}"
    echo -e "  $(t "投票" "Vote    ") : ${vote_label}"
  else
    err "$(t "投票は完了していません（送信に失敗）。上記エラーを確認してください。" "Vote was NOT cast (submission failed). Check the error above.")"
  fi
  press_enter
}

# =============================================================================
#  メインメニュー
# =============================================================================

main_menu() {
  while true; do
    clear
    show_welcome
    show_header

    menu_select "$(t "メインメニュー" "Main Menu")" \
      "[1]  $(t "プール資金の管理"     "Manage pool funds")" \
      "[2]  $(t "プール設定の確認"     "Check pool config")" \
      "[3]  $(t "KES の更新をする"      "Rotate KES key")" \
      "[4]  $(t "プール情報を更新する"  "Update pool info")" \
      "[5]  $(t "DRep へ委任をする"     "Delegate to DRep")" \
      "[6]  $(t "ガバナンス投票をする"  "Governance vote")" \
      "[L]  $(t "言語: 日本語 → English" "Language: English → 日本語")" \
      "[q]  $(t "終了"                 "Quit")"
    local choice=$?

    case $choice in
      0) menu_wallet ;;
      1) menu_pool_check ;;
      2) menu_kes_update ;;
      3) menu_pool_update ;;
      4) menu_drep_delegate ;;
      5) menu_governance_vote ;;
      6) [[ "$CTOOL_LANG" == "en" ]] && CTOOL_LANG="ja" || CTOOL_LANG="en" ;;
      7|99)
        clear
        echo -e "\n  ${FG_YELLOW}☕️  $(t "またのご利用をお待ちしています。" "Thanks for using ctool. See you!")${NC}\n"
        exit 0
        ;;
    esac
  done
}

main_menu
