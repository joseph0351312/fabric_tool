#!/bin/bash
################################################################################
#                                                                              #
#  Hyperledger Fabric Network Tool (Self-Contained)                           #
#  一鍵生成、部署、管理 Hyperledger Fabric 區塊鏈網路                           #
#                                                                              #
#  功能：                                                                      #
#    • generate - 自動生成完整 Fabric 網路配置和 Docker Compose 檔案           #
#    • deploy   - 分佈式多機部署 (透過 SSH)                                    #
#    • version  - 顯示版本和依賴信息                                           #
#                                                                              #
################################################################################

set -e

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 常數定義
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly TOOL_VERSION="1.0.0"
readonly TOOL_NAME="Hyperledger Fabric Network Tool"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 支援的 Fabric 版本
readonly FABRIC_VERSION="2.5"
readonly FABRIC_CA_VERSION="1.5.5"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 顏色定義 (支援淺色和深色主題)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 工具函數
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# 打印橫幅
print_banner() {
  echo ""
  echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${NC}  ${BOLD}Hyperledger Fabric Network Tool${NC} ${DIM}v${TOOL_VERSION}${NC}"
  echo -e "${CYAN}║${NC}  一鍵生成、部署、管理 Fabric 區塊鏈網路"
  echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

# 打印錯誤信息
error() {
  echo -e "${RED}✗ 錯誤:${NC} $*" >&2
}

# 打印警告信息
warn() {
  echo -e "${YELLOW}⚠ 警告:${NC} $*" >&2
}

# 打印成功信息
success() {
  echo -e "${GREEN}✓${NC} $*"
}

# 打印信息
info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

# 打印步驟
step() {
  echo -e "${CYAN}→${NC} ${BOLD}$*${NC}"
}

# 除錯輸出 (DEBUG=1 時啟用)
debug() {
  [ "${DEBUG:-0}" = "1" ] && echo -e "${DIM}[DEBUG]${NC} $*" >&2
  return 0
}

# 打印使用說明
print_usage() {
  cat << 'EOF'
╔═ 用法 ═══════════════════════════════════════════════════════════════════╗

  ./fabric-tool.sh <命令> [選項]

╔═ 命令 ════════════════════════════════════════════════════════════════════╗

  generate    生成完整的 Fabric 網路配置文件和 Docker Compose
  deploy      多機部署 (透過 SSH 將配置分發到遠端主機並啟動)
  version     顯示版本和依賴信息
  help        顯示此說明

╔═ generate 命令選項 ═══════════════════════════════════════════════════════╗

EOF

  echo -e "  ${BOLD}-C <檔案>${NC}${DIM}    YAML 配置檔${NC} (定義組織名稱、channel、主機)"
  echo -e "  ${BOLD}-o <數量>${NC}${DIM}    Orderer 節點數量${NC} (預設: 5, 建議奇數)"
  echo -e "  ${BOLD}-p <數量>${NC}${DIM}    Peer 組織數量${NC} (預設: 5)"
  echo -e "  ${BOLD}-c <名稱>${NC}${DIM}    Channel 名稱${NC} (預設: mychannel)"
  echo -e "  ${BOLD}-d <目錄>${NC}${DIM}    輸出目錄${NC} (預設: generated-network)"
  echo -e "  ${BOLD}-b <路徑>${NC}${DIM}    Fabric 工具路徑${NC} (cryptogen/configtxgen)"

  echo ""
  echo "╔═ deploy 命令選項 ═════════════════════════════════════════════════════════╗"
  echo ""
  echo -e "  ${BOLD}-f <檔案>${NC}${DIM}    部署配置文件${NC} (預設: network-config.yaml)"
  echo -e "  ${BOLD}-b <路徑>${NC}${DIM}    Fabric 工具路徑${NC}"
  echo -e "  ${BOLD}-t${NC}${DIM}           測試 SSH 連線 (不執行部署)${NC}"
  echo -e "  ${BOLD}-g${NC}${DIM}           僅生成配置，不部署 (dry-run)${NC}"
  echo -e "  ${BOLD}-d${NC}${DIM}           僅部署，跳過生成${NC}"
  echo -e "  ${BOLD}-s${NC}${DIM}           部署後自動啟動網路${NC}"
  echo -e "  ${BOLD}-c${NC}${DIM}           清理所有遠端節點${NC}"

  echo ""
  echo "╔═ 常見範例 ════════════════════════════════════════════════════════════════╗"
  echo ""

  cat << 'EOF'
  # 單機快速部署 (3 個 Orderer + 4 個 Peer 組織)
  ./fabric-tool.sh generate -o 3 -p 4 -c mychannel
  cd generated-network && ./start.sh set_channel

  # 最小化測試網路 (1 個 Orderer + 1 個 Peer)
  ./fabric-tool.sh generate -o 1 -p 1 -c testchannel

  # 生產級網路，指定 Fabric 工具路徑
  ./fabric-tool.sh generate -o 5 -p 5 -b /opt/fabric/bin

  # 多機部署 - 測試連線
  ./fabric-tool.sh deploy -f network-config.yaml -t

  # 多機部署 - 完整流程 (生成 + 部署 + 啟動)
  ./fabric-tool.sh deploy -f network-config.yaml -s

  # 多機部署 - 清理所有遠端節點
  ./fabric-tool.sh deploy -f network-config.yaml -c

╔═ 生成後的操作 ════════════════════════════════════════════════════════════╗

  cd generated-network

  # 啟動網路 + 建立 channel
  ./start.sh set_channel

  # 啟動網路 + channel + 部署預設 chaincode
  ./start.sh set_chaincode

  # 一鍵部署自訂 chaincode
  ./start.sh deploy mycc ./chaincode/go/contract mycc_label 1.0 1

  # 查看容器狀態
  ./docker_ps.sh

  # 停止並清理網路
  ./stop.sh

╔═ 詳細文檔 ════════════════════════════════════════════════════════════════╗

  請參考 README.md 了解更多信息：
  • 完整的命令說明和選項
  • 端口分配規則
  • 多機部署配置格式
  • Chaincode 部署流程
  • 常見問題排除指南

EOF
}

# 檢查前置需求
check_requirements() {
  local missing=0

  # 檢查 Docker
  if ! command -v docker &> /dev/null; then
    error "未安裝 Docker。請先安裝 Docker: https://docs.docker.com/get-docker/"
    ((missing++))
  else
    info "Docker: $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  fi

  # 檢查 Docker Compose (v2 插件或 v1 獨立命令皆可)
  if docker compose version &> /dev/null; then
    info "Docker Compose: $(docker compose version --short 2>/dev/null || echo v2)"
  elif command -v docker-compose &> /dev/null; then
    info "Docker Compose: $(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  else
    error "未安裝 Docker Compose。請先安裝: https://docs.docker.com/compose/install/"
    ((missing++))
  fi

  # 檢查 Fabric 工具
  if ! command -v cryptogen &> /dev/null && ! command -v configtxgen &> /dev/null; then
    warn "未找到 Fabric 工具 (cryptogen/configtxgen)"
    warn "請指定工具路徑: -b <路徑>"
    warn "或安裝: https://hyperledger-fabric.readthedocs.io/en/latest/install.html"
  fi

  if [ $missing -gt 0 ]; then
    error "缺少必要工具，請先安裝"
    return 1
  fi

  return 0
}

# 打印版本信息
print_version() {
  echo ""
  echo -e "${BOLD}${TOOL_NAME}${NC} ${GREEN}v${TOOL_VERSION}${NC}"
  echo ""
  echo "組件版本:"
  echo -e "  Hyperledger Fabric:  ${GREEN}${FABRIC_VERSION}${NC}"
  echo -e "  Fabric CA:           ${GREEN}${FABRIC_CA_VERSION}${NC}"
  echo ""
  echo "環境檢查:"

  if command -v docker &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Docker 已安裝"
  else
    echo -e "  ${RED}✗${NC} Docker 未安裝"
  fi

  if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} Docker Compose 已安裝"
  else
    echo -e "  ${RED}✗${NC} Docker Compose 未安裝"
  fi

  if command -v cryptogen &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} cryptogen 已安裝"
  else
    echo -e "  ${YELLOW}⚠${NC} cryptogen 未安裝 (可透過 -b 選項指定)"
  fi

  if command -v configtxgen &> /dev/null; then
    echo -e "  ${GREEN}✓${NC} configtxgen 已安裝"
  else
    echo -e "  ${YELLOW}⚠${NC} configtxgen 未安裝 (可透過 -b 選項指定)"
  fi

  echo ""
}

# 首字母大寫函數
capitalize() {
  echo "$(echo ${1:0:1} | tr '[:lower:]' '[:upper:]')${1:1}"
}

# Port 規劃函數
get_host_orderer_port()    { echo $(( 7050 + $1 * 1000 )); }
get_host_orderer_admin()   { echo $(( 7053 + $1 * 1000 )); }
get_host_orderer_metrics() { echo $(( 7440 + $1 * 1000 )); }
get_host_peer_port()       { echo $(( 7051 + $1 * 1000 )); }
get_host_peer_cc_port()    { echo $(( 7052 + $1 * 1000 )); }
get_host_ca_port()         { echo $(( 7054 + $1 * 1000 )); }
get_host_couchdb_port()    { echo $(( 5984 + $1 * 1000 )); }

# 根據組織名稱取得索引
org_index() {
  local name=$1
  for (( idx=0; idx<${#ORG_NAMES[@]}; idx++ )); do
    if [ "${ORG_NAMES[$idx]}" = "$name" ]; then echo $idx; return; fi
  done
  echo -1
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GENERATE 函數 - 生成網路配置
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

generate_network() {

# ====================== 預設值 ======================
NUM_ORDERERS=5
NUM_ORGS=5
CHANNEL_NAME="mychannel"
FABRIC_IMAGE_TAG="2.5"
FABRIC_CA_TAG="1.5.5"
OUTPUT_DIR="generated-network"
FABRIC_BIN_PATH=""
WORK_DIR=""
CHANNEL_CONFIG=""

# ====================== 顏色輸出 ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function printInfo()  { echo -e "${GREEN}[INFO]${NC} $1"; }
function printWarn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
function printError() { echo -e "${RED}[ERROR]${NC} $1"; }

# ====================== 解析參數 ======================
while getopts "o:p:c:C:d:b:w:h" opt; do
  case $opt in
    o) NUM_ORDERERS=$OPTARG ;;
    p) NUM_ORGS=$OPTARG ;;
    c) CHANNEL_NAME=$OPTARG ;;
    C) CHANNEL_CONFIG=$OPTARG ;;
    d) OUTPUT_DIR=$OPTARG ;;
    b) FABRIC_BIN_PATH=$OPTARG ;;
    w) WORK_DIR=$OPTARG ;;
    h)
      cat << 'HELPEOF'

  Hyperledger Fabric 網路生成器
  ============================
  根據指定參數自動生成完整的 Fabric 網路配置文件，
  包含 crypto-config、configtx、docker-compose、explorer 等。

  用法:
    ./generate-network.sh [選項]

  選項:
    -o <數量>    Orderer 節點數量 (預設: 5, 最少: 1, 建議奇數以符合 Raft 共識)
    -p <數量>    Peer 組織數量，每個組織含 1 個 peer + 1 個 CA + 1 個 CouchDB (預設: 5, 最少: 1)
    -c <名稱>    Channel 名稱，僅限小寫字母開頭 (預設: mychannel)
    -d <目錄>    輸出目錄 (預設: generated-network)
    -b <路徑>    Fabric 工具路徑，cryptogen/configtxgen 所在目錄 (預設: 使用 PATH)
    -w <路徑>    部署工作目錄，生成的檔案內會使用此絕對路徑 (預設: 使用相對路徑)
    -h           顯示此說明

  使用範例:
    # 基本用法：3 個 orderer、4 個 peer 組織
    ./generate-network.sh -o 3 -p 4 -c mychannel

    # 最小網路：1 個 orderer、1 個 peer 組織
    ./generate-network.sh -o 1 -p 1 -c testchannel

    # 指定輸出目錄
    ./generate-network.sh -o 5 -p 3 -c prodchannel -d /opt/fabric-network

    # 使用全部預設值 (5 orderer, 5 org, mychannel)
    ./generate-network.sh

  生成後操作:
    cd generated-network      # 進入輸出目錄
    bash start.sh             # 一鍵啟動網路 (含建立 channel、加入 peer、更新錨節點)
    bash docker_ps.sh         # 查看所有容器狀態
    bash restart.sh           # 重啟所有容器
    bash stop.sh              # 停止並清理整個網路

  Chaincode 部署:
    bash uint/deploy.sh <name> <file> <label>           # 打包並安裝 chaincode
    bash uint/set_chaincode.sh cli0 <pkg_id> ...        # 為各 org 審批 chaincode
    bash uint/chaincode_seting_all.sh <channel> ...     # commit 並 init chaincode
    bash start_with_chaincode.sh set_chaincode          # 一鍵: 啟動+channel+chaincode

  Port 分配規則:
    Orderer N  ->  主要: 7050+N*1000, Admin: 7053+N*1000, Metrics: 7440+N*1000
    Org N      ->  Peer: 7051+N*1000, CA: 7054+N*1000, CouchDB: 5984+N*1000

  注意事項:
    - Raft 共識建議使用奇數個 Orderer (1, 3, 5, 7...)
    - 需要預先安裝: docker, cryptogen, configtxgen
    - Channel 名稱只能包含小寫字母、數字、點和連字號

HELPEOF
      exit 0
      ;;
    \?) printError "無效選項: -$OPTARG"; exit 1 ;;
  esac
done

# ====================== 參數驗證 ======================
if ! [[ "$NUM_ORDERERS" =~ ^[0-9]+$ ]] || [ "$NUM_ORDERERS" -lt 1 ]; then
  printError "Orderer 數量必須為正整數 (最少 1)"; exit 1
fi
if [ "$NUM_ORDERERS" -gt 1 ] && [ "$((NUM_ORDERERS % 2))" -eq 0 ]; then
  printWarn "Raft 共識建議使用奇數個 Orderer 節點 (目前: ${NUM_ORDERERS})"
fi

# ====================== 組織與 Channel 配置解析 ======================
# 資料結構 (平行陣列，相容 bash 3):
#   ORG_NAMES[@]         - 組織名稱陣列 (例: hospital pharmacy insurance)
#   CHANNEL_NAMES[@]     - channel 名稱陣列
#   CHANNEL_ORGS_LIST[@] - 每個 channel 的組織名稱列表 (空格分隔)

declare -a ORG_NAMES=()
declare -a CHANNEL_NAMES=()
declare -a CHANNEL_ORGS_LIST=()

# 輔助函數: 首字母大寫 (用於 MSP ID)
function capitalize() { echo "$(echo ${1:0:1} | tr '[:lower:]' '[:upper:]')${1:1}"; }

if [ -n "$CHANNEL_CONFIG" ]; then
  if [ ! -f "$CHANNEL_CONFIG" ]; then
    printError "配置文件不存在: $CHANNEL_CONFIG"; exit 1
  fi

  # ─── 簡易 YAML 解析器 ───────────────────────────────────────
  # 支援結構:
  #   organizations: [- name]
  #   channels: { name: [- org] }
  #   orderers: [- {host:, dir:}]
  #   peers: { name: {host:, dir:} }
  #
  # 解析結果:
  #   ORG_NAMES[@]           組織名稱
  #   CHANNEL_NAMES[@]       channel 名稱
  #   CHANNEL_ORGS_LIST[@]   每個 channel 的 org (空格分隔)
  #   ORDERER_HOSTS[@]       orderer SSH 目標
  #   ORDERER_DIRS[@]        orderer 部署目錄
  #   PEER_HOSTS[@]          peer SSH 目標 (按 ORG_NAMES 順序)
  #   PEER_DIRS[@]           peer 部署目錄 (按 ORG_NAMES 順序)

  declare -a ORDERER_HOSTS=()
  declare -a ORDERER_DIRS=()
  declare -a PEER_HOSTS=()
  declare -a PEER_DIRS=()

  CURRENT_SECTION=""
  CURRENT_CHANNEL=""
  CURRENT_PEER=""
  CURRENT_ORDERER_IDX=-1

  while IFS= read -r line; do
    # 跳過空行和註解
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # 頂層 section 偵測
    if [[ "$line" =~ ^organizations:[[:space:]]*$ ]]; then
      CURRENT_SECTION="organizations"; CURRENT_CHANNEL=""; CURRENT_PEER=""; continue
    elif [[ "$line" =~ ^channels:[[:space:]]*$ ]]; then
      CURRENT_SECTION="channels"; CURRENT_CHANNEL=""; CURRENT_PEER=""; continue
    elif [[ "$line" =~ ^orderers:[[:space:]]*$ ]]; then
      CURRENT_SECTION="orderers"; CURRENT_CHANNEL=""; CURRENT_PEER=""; continue
    elif [[ "$line" =~ ^peers:[[:space:]]*$ ]]; then
      CURRENT_SECTION="peers"; CURRENT_CHANNEL=""; CURRENT_PEER=""; continue
    elif [[ "$line" =~ ^[a-z] ]]; then
      CURRENT_SECTION=""; CURRENT_CHANNEL=""; CURRENT_PEER=""; continue
    fi

    # ─── organizations ───
    if [ "$CURRENT_SECTION" = "organizations" ]; then
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+([a-z][a-z0-9]*) ]]; then
        ORG_NAMES+=("${BASH_REMATCH[1]}")
      fi
      continue
    fi

    # ─── channels ───
    if [ "$CURRENT_SECTION" = "channels" ]; then
      # channel 名稱: "  channelname:"
      if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9.-]*):[[:space:]]*$ ]]; then
        CURRENT_CHANNEL="${BASH_REMATCH[1]}"
        CHANNEL_NAMES+=("$CURRENT_CHANNEL")
        CHANNEL_ORGS_LIST+=("")
        continue
      fi
      # channel 成員: "    - orgname"
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+([a-z][a-z0-9]*) ]] && [ -n "$CURRENT_CHANNEL" ]; then
        org_name="${BASH_REMATCH[1]}"
        last_idx=$(( ${#CHANNEL_ORGS_LIST[@]} - 1 ))
        if [ -z "${CHANNEL_ORGS_LIST[$last_idx]}" ]; then
          CHANNEL_ORGS_LIST[$last_idx]="$org_name"
        else
          CHANNEL_ORGS_LIST[$last_idx]="${CHANNEL_ORGS_LIST[$last_idx]} $org_name"
        fi
        continue
      fi
    fi

    # ─── orderers ───
    if [ "$CURRENT_SECTION" = "orderers" ]; then
      # 新的 orderer 項目: "  - host: user@ip"
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+host:[[:space:]]*(.+) ]]; then
        ORDERER_HOSTS+=("${BASH_REMATCH[1]}")
        ORDERER_DIRS+=("")  # 預設空，等下一行 dir 填入
        CURRENT_ORDERER_IDX=$(( ${#ORDERER_HOSTS[@]} - 1 ))
        continue
      fi
      # orderer dir: "    dir: /path"
      if [[ "$line" =~ ^[[:space:]]+dir:[[:space:]]*(.+) ]] && [ $CURRENT_ORDERER_IDX -ge 0 ]; then
        ORDERER_DIRS[$CURRENT_ORDERER_IDX]="${BASH_REMATCH[1]}"
        continue
      fi
    fi

    # ─── peers ───
    if [ "$CURRENT_SECTION" = "peers" ]; then
      # peer org 名稱: "  orgname:"
      if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9]*):[[:space:]]*$ ]]; then
        CURRENT_PEER="${BASH_REMATCH[1]}"
        continue
      fi
      # peer host: "    host: user@ip"
      if [[ "$line" =~ ^[[:space:]]+host:[[:space:]]*(.+) ]] && [ -n "$CURRENT_PEER" ]; then
        # 按 org 順序存放，先暫存到臨時變數
        eval "PEER_HOST_${CURRENT_PEER}='${BASH_REMATCH[1]}'"
        continue
      fi
      # peer dir: "    dir: /path"
      if [[ "$line" =~ ^[[:space:]]+dir:[[:space:]]*(.+) ]] && [ -n "$CURRENT_PEER" ]; then
        eval "PEER_DIR_${CURRENT_PEER}='${BASH_REMATCH[1]}'"
        continue
      fi
    fi

  done < "$CHANNEL_CONFIG"

  # 將 peer host/dir 按 ORG_NAMES 順序整理到陣列
  for org in "${ORG_NAMES[@]}"; do
    eval "h=\${PEER_HOST_${org}:-}"
    eval "d=\${PEER_DIR_${org}:-}"
    PEER_HOSTS+=("$h")
    PEER_DIRS+=("$d")
  done

  # ─── 驗證 ───
  if [ ${#ORG_NAMES[@]} -eq 0 ]; then
    printError "配置文件中沒有定義任何組織 (organizations)"; exit 1
  fi
  if [ ${#CHANNEL_NAMES[@]} -eq 0 ]; then
    printError "配置文件中沒有定義任何 channel (channels)"; exit 1
  fi

  # 驗證 channel 中的組織名稱都有定義
  for (( ci=0; ci<${#CHANNEL_NAMES[@]}; ci++ )); do
    for org_name in ${CHANNEL_ORGS_LIST[$ci]}; do
      found=false
      for defined_org in "${ORG_NAMES[@]}"; do
        if [ "$org_name" = "$defined_org" ]; then found=true; break; fi
      done
      if [ "$found" = false ]; then
        printError "Channel ${CHANNEL_NAMES[$ci]} 中的組織 '${org_name}' 未在 organizations 中定義"; exit 1
      fi
    done
  done

  NUM_ORGS=${#ORG_NAMES[@]}

  # 如果配置文件有定義 orderers，覆蓋 -o 參數
  if [ ${#ORDERER_HOSTS[@]} -gt 0 ]; then
    NUM_ORDERERS=${#ORDERER_HOSTS[@]}
  fi

  printInfo "配置文件: ${CHANNEL_CONFIG}"
  printInfo "組織: ${ORG_NAMES[*]}"
  if [ ${#ORDERER_HOSTS[@]} -gt 0 ]; then
    printInfo "Orderer 節點: ${#ORDERER_HOSTS[@]} 個"
  fi
else
  # 無配置文件: 使用 -p 數量生成 org0, org1, ... 的名稱
  if ! [[ "$NUM_ORGS" =~ ^[0-9]+$ ]] || [ "$NUM_ORGS" -lt 1 ]; then
    printError "Peer 組織數量必須為正整數 (最少 1)"; exit 1
  fi
  for (( i=0; i<NUM_ORGS; i++ )); do
    ORG_NAMES+=("org${i}")
  done
  # 預設: 單一 channel，所有 org 加入
  if ! [[ "$CHANNEL_NAME" =~ ^[a-z][a-z0-9.-]*$ ]]; then
    printError "Channel 名稱只能包含小寫字母、數字、點和連字號，且必須以字母開頭"; exit 1
  fi
  CHANNEL_NAMES+=("$CHANNEL_NAME")
  CHANNEL_ORGS_LIST+=("${ORG_NAMES[*]}")
fi

# 輔助函數: 根據組織名稱取得索引
function org_index() {
  local name=$1
  for (( idx=0; idx<${#ORG_NAMES[@]}; idx++ )); do
    if [ "${ORG_NAMES[$idx]}" = "$name" ]; then echo $idx; return; fi
  done
  echo -1
}

# ====================== Fabric 工具路徑 ======================
if [ -n "$FABRIC_BIN_PATH" ]; then
  # 轉為絕對路徑
  FABRIC_BIN_PATH="$(cd "$FABRIC_BIN_PATH" 2>/dev/null && pwd)" || {
    printError "Fabric 工具路徑不存在: $FABRIC_BIN_PATH"; exit 1
  }
  if [ ! -x "${FABRIC_BIN_PATH}/cryptogen" ] || [ ! -x "${FABRIC_BIN_PATH}/configtxgen" ]; then
    printError "在 ${FABRIC_BIN_PATH} 中找不到 cryptogen 或 configtxgen"
    exit 1
  fi
  CRYPTOGEN="${FABRIC_BIN_PATH}/cryptogen"
  CONFIGTXGEN="${FABRIC_BIN_PATH}/configtxgen"
  printInfo "Fabric 工具路徑: ${FABRIC_BIN_PATH}"
else
  CRYPTOGEN="cryptogen"
  CONFIGTXGEN="configtxgen"
fi

# ====================== 工作目錄路徑 ======================
# OUTPUT_DIR 預設使用 home 目錄 + orderer/peer 數量命名
# 例: ~/3_orderer_4_peer
if [ "$OUTPUT_DIR" = "generated-network" ]; then
  # 使用者未指定 -d，改用自動命名
  OUTPUT_DIR="${HOME}/${NUM_ORDERERS}_orderer_${NUM_ORGS}_peer"
fi

# WORK_DIR: 遠端機器上的部署目錄名稱
# 統一使用 ~/<N_orderer_M_peer> 格式
DEPLOY_DIRNAME="${NUM_ORDERERS}_orderer_${NUM_ORGS}_peer"

# 覆蓋 YAML 中的 dir 設定，統一使用 home 目錄
# 更新所有 ORDERER_DIRS 和 PEER_DIRS
if [ -n "$CHANNEL_CONFIG" ]; then
  for (( i=0; i<${#ORDERER_HOSTS[@]}; i++ )); do
    ORD_HOST="${ORDERER_HOSTS[$i]}"
    if [ "$ORD_HOST" = "local" ] || [ -z "$ORD_HOST" ]; then
      ORDERER_DIRS[$i]="${HOME}/${DEPLOY_DIRNAME}"
    else
      # 遠端: 取 user 部分推算 home 目錄
      ORD_USER=$(echo "$ORD_HOST" | cut -d'@' -f1)
      ORDERER_DIRS[$i]="/home/${ORD_USER}/${DEPLOY_DIRNAME}"
    fi
  done
  for (( i=0; i<${#PEER_HOSTS[@]}; i++ )); do
    P_HOST="${PEER_HOSTS[$i]}"
    if [ "$P_HOST" = "local" ] || [ -z "$P_HOST" ]; then
      PEER_DIRS[$i]="${HOME}/${DEPLOY_DIRNAME}"
    else
      P_USER=$(echo "$P_HOST" | cut -d'@' -f1)
      PEER_DIRS[$i]="/home/${P_USER}/${DEPLOY_DIRNAME}"
    fi
  done
fi

# 決定生成的檔案中使用的路徑前綴
# WORK_DIR 取第一個定義的目錄 (本機 home)
if [ -z "$WORK_DIR" ]; then
  WORK_DIR="${HOME}/${DEPLOY_DIRNAME}"
fi
WORK_DIR="${WORK_DIR%/}"

# docker-compose 在 docker/ 子目錄下，引用上層用絕對路徑
VOL_PREFIX="${WORK_DIR}"
# configtx.yaml 永遠用相對路徑 (configtxgen 在本地目錄下執行)
CFG_PREFIX="."
# explorer 在 fabric-explorer/ 子目錄下
EXPLORER_PREFIX="${WORK_DIR}"
printInfo "部署工作目錄: ${WORK_DIR}"

printInfo "=========================================="
printInfo " Hyperledger Fabric 網路生成器"
printInfo "=========================================="
printInfo "Orderer 數量:   ${NUM_ORDERERS}"
printInfo "Peer 組織數量:  ${NUM_ORGS}"
printInfo "組織名稱:       ${ORG_NAMES[*]}"
printInfo "Channel 數量:   ${#CHANNEL_NAMES[@]}"
for (( ci=0; ci<${#CHANNEL_NAMES[@]}; ci++ )); do
  printInfo "  ${CHANNEL_NAMES[$ci]} -> ${CHANNEL_ORGS_LIST[$ci]}"
done
printInfo "輸出目錄:       ${OUTPUT_DIR}"
if [ -n "$FABRIC_BIN_PATH" ]; then
  printInfo "Fabric 工具:    ${FABRIC_BIN_PATH}"
fi
if [ -n "$WORK_DIR" ]; then
  printInfo "工作目錄:       ${WORK_DIR}"
fi
printInfo "=========================================="

# ====================== Port 規劃 ======================
# 所有容器內部使用固定 port，僅 host 映射不同
#
# Orderer:  host (7050 + i*1000) -> container 7050
#           admin host (7053 + i*1000) -> container 7053
#           metrics host (7440 + i*1000) -> container 7440
# Peer:     host (7051 + i*1000) -> container 7051
#           chaincode host (7052 + i*1000) -> container 7052
# CA:       host (7054 + i*1000) -> container 7054
# CouchDB:  host (5984 + i*1000) -> container 5984

function get_host_orderer_port()    { echo $(( 7050 + $1 * 1000 )); }
function get_host_orderer_admin()   { echo $(( 7053 + $1 * 1000 )); }
function get_host_orderer_metrics() { echo $(( 7440 + $1 * 1000 )); }
function get_host_peer_port()       { echo $(( 7051 + $1 * 1000 )); }
function get_host_peer_cc_port()    { echo $(( 7052 + $1 * 1000 )); }
function get_host_ca_port()         { echo $(( 7054 + $1 * 1000 )); }
function get_host_couchdb_port()    { echo $(( 5984 + $1 * 1000 )); }

# 容器內部固定 port
ORDERER_INTERNAL_PORT=7050
ORDERER_ADMIN_INTERNAL_PORT=7053
ORDERER_METRICS_INTERNAL_PORT=7440
PEER_INTERNAL_PORT=7051
PEER_CC_INTERNAL_PORT=7052
CA_INTERNAL_PORT=7054

# ====================== 建立目錄結構 ======================
printInfo "建立目錄結構..."
mkdir -p "${OUTPUT_DIR}"/{docker,channel-artifacts,organizations,chaincode/go}
mkdir -p "${OUTPUT_DIR}/fabric-explorer/connection-profile"

# ================================================================
# 1. 生成 crypto-config.yaml
# ================================================================
printInfo "生成 crypto-config.yaml..."

cat > "${OUTPUT_DIR}/organizations/crypto-config.yaml" << 'CRYPTO_HEADER'
OrdererOrgs:
  - Name: Orderer
    Domain: com
    EnableNodeOUs: true
    Specs:
CRYPTO_HEADER

for (( i=0; i<NUM_ORDERERS; i++ )); do
  echo "      - Hostname: orderer${i}" >> "${OUTPUT_DIR}/organizations/crypto-config.yaml"
done
echo "      - Hostname: ca" >> "${OUTPUT_DIR}/organizations/crypto-config.yaml"

echo "" >> "${OUTPUT_DIR}/organizations/crypto-config.yaml"
echo "PeerOrgs:" >> "${OUTPUT_DIR}/organizations/crypto-config.yaml"

for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  cat >> "${OUTPUT_DIR}/organizations/crypto-config.yaml" << EOF
  - Name: ${ORG_CAP}
    Domain: ${ORG}.com
    EnableNodeOUs: true
    Specs:
      - Hostname: peer0
      - Hostname: ca
    Users:
      Count: 1
EOF
done

# ================================================================
# 2. 生成 configtx.yaml
# ================================================================
printInfo "生成 configtx.yaml..."

# --- Organizations ---
cat > "${OUTPUT_DIR}/configtx.yaml" << 'EOF'
---
Organizations:
EOF

# OrdererOrg
cat >> "${OUTPUT_DIR}/configtx.yaml" << EOF

    - &OrdererOrg
        Name: OrdererOrg
        ID: OrdererMSP
        MSPDir: ${CFG_PREFIX}/organizations/crypto-config/ordererOrganizations/com/msp
        Policies:
            Readers:
                Type: Signature
                Rule: "OR('OrdererMSP.member')"
            Writers:
                Type: Signature
                Rule: "OR('OrdererMSP.member')"
            Admins:
                Type: Signature
                Rule: "OR('OrdererMSP.admin')"
        OrdererEndpoints:
EOF

for (( i=0; i<NUM_ORDERERS; i++ )); do
  echo "            - orderer${i}.com:$(get_host_orderer_port $i)" >> "${OUTPUT_DIR}/configtx.yaml"
done

# Peer Orgs
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  PEER_PORT=$(get_host_peer_port $i)
  cat >> "${OUTPUT_DIR}/configtx.yaml" << EOF

    - &${ORG_CAP}
        Name: ${ORG_CAP}MSP
        ID: ${ORG_CAP}MSP
        MSPDir: ${CFG_PREFIX}/organizations/crypto-config/peerOrganizations/${ORG}.com/msp
        Policies:
            Readers:
                Type: Signature
                Rule: "OR('${ORG_CAP}MSP.admin', '${ORG_CAP}MSP.peer', '${ORG_CAP}MSP.client')"
            Writers:
                Type: Signature
                Rule: "OR('${ORG_CAP}MSP.admin', '${ORG_CAP}MSP.client')"
            Admins:
                Type: Signature
                Rule: "OR('${ORG_CAP}MSP.admin')"
            Endorsement:
                Type: Signature
                Rule: "OR('${ORG_CAP}MSP.peer')"
        AnchorPeers:
            - Host: peer0.${ORG}.com
              Port: ${PEER_PORT}
EOF
done

# --- Capabilities / Application / Orderer / Channel defaults ---
cat >> "${OUTPUT_DIR}/configtx.yaml" << 'EOF'

Capabilities:
    Channel: &ChannelCapabilities
        V2_0: true
    Orderer: &OrdererCapabilities
        V2_0: true
    Application: &ApplicationCapabilities
        V2_0: true

Application: &ApplicationDefaults
    Organizations:
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: "ANY Readers"
        Writers:
            Type: ImplicitMeta
            Rule: "ANY Writers"
        Admins:
            Type: ImplicitMeta
            Rule: "MAJORITY Admins"
        LifecycleEndorsement:
            Type: ImplicitMeta
            Rule: "MAJORITY Endorsement"
        Endorsement:
            Type: ImplicitMeta
            Rule: "MAJORITY Endorsement"
    Capabilities:
        <<: *ApplicationCapabilities

Orderer: &OrdererDefaults
    OrdererType: etcdraft
    BatchTimeout: 1s
    BatchSize:
        MaxMessageCount: 100
        AbsoluteMaxBytes: 99 MB
        PreferredMaxBytes: 512 KB
EOF

# Orderer Addresses (使用 host port，因為 configtx 是從外部視角)
echo "    Addresses:" >> "${OUTPUT_DIR}/configtx.yaml"
for (( i=0; i<NUM_ORDERERS; i++ )); do
  echo "        - orderer${i}.com:$(get_host_orderer_port $i)" >> "${OUTPUT_DIR}/configtx.yaml"
done

# EtcdRaft Consenters (容器間通訊使用 host port，因為透過 Docker 網路解析)
echo "    EtcdRaft:" >> "${OUTPUT_DIR}/configtx.yaml"
echo "        Consenters:" >> "${OUTPUT_DIR}/configtx.yaml"
for (( i=0; i<NUM_ORDERERS; i++ )); do
  PORT=$(get_host_orderer_port $i)
  cat >> "${OUTPUT_DIR}/configtx.yaml" << EOF
        - Host: orderer${i}.com
          Port: ${PORT}
          ClientTLSCert: ${CFG_PREFIX}/organizations/crypto-config/ordererOrganizations/com/orderers/orderer${i}.com/tls/server.crt
          ServerTLSCert: ${CFG_PREFIX}/organizations/crypto-config/ordererOrganizations/com/orderers/orderer${i}.com/tls/server.crt
EOF
done

cat >> "${OUTPUT_DIR}/configtx.yaml" << 'EOF'
    Organizations:
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: "ANY Readers"
        Writers:
            Type: ImplicitMeta
            Rule: "ANY Writers"
        Admins:
            Type: ImplicitMeta
            Rule: "MAJORITY Admins"
        BlockValidation:
            Type: ImplicitMeta
            Rule: "ANY Writers"

Channel: &ChannelDefaults
    Policies:
        Readers:
            Type: ImplicitMeta
            Rule: "ANY Readers"
        Writers:
            Type: ImplicitMeta
            Rule: "ANY Writers"
        Admins:
            Type: ImplicitMeta
            Rule: "MAJORITY Admins"
    Capabilities:
        <<: *ChannelCapabilities

EOF

# --- Profiles ---
echo "Profiles:" >> "${OUTPUT_DIR}/configtx.yaml"
echo "" >> "${OUTPUT_DIR}/configtx.yaml"

cat >> "${OUTPUT_DIR}/configtx.yaml" << 'EOF'
    OrgsOrdererGenesis:
        <<: *ChannelDefaults
        Orderer:
            <<: *OrdererDefaults
            Organizations:
                - *OrdererOrg
            Capabilities:
                <<: *OrdererCapabilities
        Consortiums:
            SampleConsortium:
                Organizations:
EOF
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  echo "                    - *${ORG_CAP}" >> "${OUTPUT_DIR}/configtx.yaml"
done

# 為每個 channel 生成 profile
for (( ci=0; ci<${#CHANNEL_NAMES[@]}; ci++ )); do
  ch_name="${CHANNEL_NAMES[$ci]}"
  cat >> "${OUTPUT_DIR}/configtx.yaml" << EOF

    ${ch_name}:
        Consortium: SampleConsortium
        <<: *ChannelDefaults
        Application:
            <<: *ApplicationDefaults
            Organizations:
EOF
  for org_id in ${CHANNEL_ORGS_LIST[$ci]}; do
    echo "                - *$(capitalize ${org_id})" >> "${OUTPUT_DIR}/configtx.yaml"
  done
  cat >> "${OUTPUT_DIR}/configtx.yaml" << 'EOF'
            Capabilities:
                <<: *ApplicationCapabilities
EOF
done

# ================================================================
# 3. 生成 docker-compose-order.yaml
# ================================================================
printInfo "生成 docker-compose-order.yaml..."

cat > "${OUTPUT_DIR}/docker/docker-compose-order.yaml" << 'EOF'
version: '3.0'

networks:
  fabric-center:
    external: true

services:
EOF

for (( i=0; i<NUM_ORDERERS; i++ )); do
  HOST_PORT=$(get_host_orderer_port $i)
  HOST_ADMIN=$(get_host_orderer_admin $i)
  HOST_METRICS=$(get_host_orderer_metrics $i)
  cat >> "${OUTPUT_DIR}/docker/docker-compose-order.yaml" << EOF

  orderer${i}.com:
    container_name: orderer${i}.com
    image: hyperledger/fabric-orderer:${FABRIC_IMAGE_TAG}
    environment:
      - FABRIC_LOGGING_SPEC=INFO
      - ORDERER_GENERAL_LISTENADDRESS=0.0.0.0
      - ORDERER_GENERAL_LISTENPORT=${HOST_PORT}
      - ORDERER_GENERAL_GENESISMETHOD=file
      - ORDERER_GENERAL_GENESISFILE=/var/hyperledger/orderer/orderer.genesis.block
      - ORDERER_GENERAL_LOCALMSPID=OrdererMSP
      - ORDERER_GENERAL_LOCALMSPDIR=/var/hyperledger/orderer/msp
      - ORDERER_GENERAL_TLS_ENABLED=true
      - ORDERER_GENERAL_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_GENERAL_CLUSTER_CLIENTCERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_GENERAL_CLUSTER_CLIENTPRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_GENERAL_CLUSTER_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_ADMIN_TLS_ENABLED=true
      - ORDERER_ADMIN_TLS_CERTIFICATE=/var/hyperledger/orderer/tls/server.crt
      - ORDERER_ADMIN_TLS_PRIVATEKEY=/var/hyperledger/orderer/tls/server.key
      - ORDERER_ADMIN_TLS_ROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_ADMIN_TLS_CLIENTROOTCAS=[/var/hyperledger/orderer/tls/ca.crt]
      - ORDERER_ADMIN_LISTENADDRESS=0.0.0.0:${HOST_ADMIN}
      - ORDERER_OPERATIONS_LISTENADDRESS=0.0.0.0:${HOST_METRICS}
      - ORDERER_METRICS_PROVIDER=prometheus
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric
    command: orderer
    volumes:
      - ${VOL_PREFIX}/channel-artifacts/genesis.block:/var/hyperledger/orderer/orderer.genesis.block
      - ${VOL_PREFIX}/organizations/crypto-config/ordererOrganizations/com/orderers/orderer${i}.com/msp:/var/hyperledger/orderer/msp
      - ${VOL_PREFIX}/organizations/crypto-config/ordererOrganizations/com/orderers/orderer${i}.com/tls/:/var/hyperledger/orderer/tls
    ports:
      - ${HOST_PORT}:${HOST_PORT}
      - ${HOST_ADMIN}:${HOST_ADMIN}
      - ${HOST_METRICS}:${HOST_METRICS}
    networks:
      - fabric-center
EOF
done

# ================================================================
# 4. 生成每個 Org 的 docker-compose-orgN.yaml
# ================================================================
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  printInfo "生成 docker-compose-${ORG}.yaml..."
  HOST_PEER=$(get_host_peer_port $i)
  HOST_CC=$(get_host_peer_cc_port $i)
  HOST_CA=$(get_host_ca_port $i)
  HOST_COUCH=$(get_host_couchdb_port $i)

  cat > "${OUTPUT_DIR}/docker/docker-compose-${ORG}.yaml" << EOF
version: '3.0'

volumes:
  peer0.${ORG}.com:
  couchdb0.${ORG}.com:
  ca-${ORG}:

networks:
  fabric-center:
    external: true

services:

  ca-${ORG}:
    container_name: ca-${ORG}
    image: hyperledger/fabric-ca:${FABRIC_CA_TAG}
    environment:
      - FABRIC_CA_HOME=/etc/hyperledger/fabric-ca-server
      - FABRIC_CA_SERVER_CA_NAME=ca-${ORG}
      - FABRIC_CA_SERVER_TLS_ENABLED=true
      - FABRIC_CA_SERVER_TLS_KEYFILE=/etc/hyperledger/tls/peer/server.key
      - FABRIC_CA_SERVER_TLS_CERTFILE=/etc/hyperledger/tls/peer/server.crt
      - FABRIC_CA_SERVER_PORT=${HOST_CA}
      - FABRIC_CA_SERVER_CFG_AFFILIATIONS_ALLOWREMOVE=true
      - FABRIC_CA_SERVER_CFG_IDENTITIES_ALLOWREMOVE=true
    ports:
      - "${HOST_CA}:${HOST_CA}"
    command: sh -c "fabric-ca-server start -b admin:adminpw -d"
    volumes:
      - ${VOL_PREFIX}/organizations/crypto-config/peerOrganizations/${ORG}.com/tlsca:/etc/hyperledger/fabric-ca-server
      - ${VOL_PREFIX}/organizations/crypto-config/peerOrganizations/${ORG}.com/peers/ca.${ORG}.com/tls:/etc/hyperledger/tls/peer
      - ${VOL_PREFIX}/organizations/crypto-config/peerOrganizations/${ORG}.com/tlsca:/etc/hyperledger/tlsca
    networks:
      - fabric-center

  couchdb0.${ORG}.com:
    container_name: couchdb0.${ORG}.com
    image: hyperledger/fabric-couchdb
    environment:
      - COUCHDB_USER=admin
      - COUCHDB_PASSWORD=adminpw
    ports:
      - ${HOST_COUCH}:5984
    networks:
      - fabric-center

  peer0.${ORG}.com:
    container_name: peer0.${ORG}.com
    image: hyperledger/fabric-peer:${FABRIC_IMAGE_TAG}
    environment:
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_PEER_ID=peer0.${ORG}.com
      - CORE_PEER_ADDRESS=peer0.${ORG}.com:${HOST_PEER}
      - CORE_PEER_LISTENADDRESS=0.0.0.0:${HOST_PEER}
      - CORE_PEER_CHAINCODEADDRESS=peer0.${ORG}.com:${HOST_CC}
      - CORE_PEER_CHAINCODELISTENADDRESS=0.0.0.0:${HOST_CC}
      - CORE_PEER_GOSSIP_BOOTSTRAP=peer0.${ORG}.com:${HOST_PEER}
      - CORE_PEER_GOSSIP_EXTERNALENDPOINT=peer0.${ORG}.com:${HOST_PEER}
      - CORE_PEER_LOCALMSPID=${ORG_CAP}MSP
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_GOSSIP_USELEADERELECTION=true
      - CORE_PEER_GOSSIP_ORGLEADER=false
      - CORE_PEER_PROFILE_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/etc/hyperledger/fabric/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/etc/hyperledger/fabric/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/fabric/tls/ca.crt
      - CORE_CHAINCODE_EXECUTETIMEOUT=300s
      - CORE_LEDGER_STATE_STATEDATABASE=CouchDB
      - CORE_LEDGER_STATE_COUCHDBCONFIG_COUCHDBADDRESS=couchdb0.${ORG}.com:5984
      - CORE_LEDGER_STATE_COUCHDBCONFIG_USERNAME=admin
      - CORE_LEDGER_STATE_COUCHDBCONFIG_PASSWORD=adminpw
      - CORE_PEER_LIMITS_CONCURRENCY_GATEWAYSERVICE=100000
    depends_on:
      - couchdb0.${ORG}.com
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: peer node start
    volumes:
      - /var/run/:/host/var/run/
      - ${VOL_PREFIX}/organizations/crypto-config/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/msp:/etc/hyperledger/fabric/msp
      - ${VOL_PREFIX}/organizations/crypto-config/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/tls:/etc/hyperledger/fabric/tls
    ports:
      - ${HOST_PEER}:${HOST_PEER}
      - ${HOST_CC}:${HOST_CC}
    networks:
      - fabric-center
EOF
done

# ================================================================
# 5. 生成 docker-compose-cli.yaml
# ================================================================
printInfo "生成 docker-compose-cli.yaml..."

cat > "${OUTPUT_DIR}/docker/docker-compose-cli.yaml" << 'EOF'
version: '3.0'

networks:
  fabric-center:
    external: true

services:
EOF

for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  HOST_PEER=$(get_host_peer_port $i)
  cat >> "${OUTPUT_DIR}/docker/docker-compose-cli.yaml" << EOF

  cli${i}:
    container_name: cli${i}
    image: hyperledger/fabric-tools:${FABRIC_IMAGE_TAG}
    tty: true
    stdin_open: true
    environment:
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - FABRIC_LOGGING_SPEC=INFO
      - CORE_PEER_ID=cli${i}
      - CORE_PEER_ADDRESS=peer0.${ORG}.com:${HOST_PEER}
      - CORE_PEER_LOCALMSPID=${ORG_CAP}MSP
      - CORE_PEER_TLS_ENABLED=true
      - CORE_PEER_TLS_CERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/tls/server.crt
      - CORE_PEER_TLS_KEY_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/tls/server.key
      - CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/tls/ca.crt
      - CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG}.com/users/Admin@${ORG}.com/msp/
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: /bin/bash
    volumes:
      - /var/run/:/host/var/run/
      - ${VOL_PREFIX}/chaincode/go/:/opt/gopath/src/github.com/hyperledger/fabric-cluster/chaincode/go
      - ${VOL_PREFIX}/organizations/crypto-config:/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/
      - ${VOL_PREFIX}/channel-artifacts:/opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts
    networks:
      - fabric-center
EOF
done

# ================================================================
# 6. 生成 configtx.sh (通道配置腳本)
# ================================================================
printInfo "生成 configtx.sh..."

# 如果有指定 bin path，在生成的腳本中使用絕對路徑
GENERATED_CONFIGTXGEN="configtxgen"
if [ -n "$FABRIC_BIN_PATH" ]; then
  GENERATED_CONFIGTXGEN="${FABRIC_BIN_PATH}/configtxgen"
fi

cat > "${OUTPUT_DIR}/configtx.sh" << EOF
#!/bin/bash
set -e

export FABRIC_CFG_PATH=\${PWD}

echo "生成創世區塊..."
${GENERATED_CONFIGTXGEN} -profile OrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block -channelID fabric-channel
EOF

# 為每個 channel 生成通道配置和錨節點文件
for (( ci=0; ci<${#CHANNEL_NAMES[@]}; ci++ )); do
  ch_name="${CHANNEL_NAMES[$ci]}"
  cat >> "${OUTPUT_DIR}/configtx.sh" << EOF

echo "生成通道配置文件: ${ch_name}..."
${GENERATED_CONFIGTXGEN} -profile ${ch_name} -outputCreateChannelTx ./channel-artifacts/${ch_name}.tx -channelID ${ch_name}

echo "生成 ${ch_name} 錨節點文件..."
EOF
  for org_id in ${CHANNEL_ORGS_LIST[$ci]}; do
    cat >> "${OUTPUT_DIR}/configtx.sh" << EOF
${GENERATED_CONFIGTXGEN} -profile ${ch_name} -outputAnchorPeersUpdate ./channel-artifacts/${ch_name}_$(capitalize ${org_id})MSPanchors.tx -channelID ${ch_name} -asOrg $(capitalize ${org_id})MSP
EOF
  done
done

echo 'echo "通道配置生成完成"' >> "${OUTPUT_DIR}/configtx.sh"
chmod +x "${OUTPUT_DIR}/configtx.sh"

# ================================================================
# 7. 生成 ccp-generate.sh 及模板
# ================================================================
printInfo "生成 CCP 相關文件..."

cat > "${OUTPUT_DIR}/organizations/ccp-generate.sh" << 'CCPSCRIPT'
#!/bin/bash
set -e

function one_line_pem {
    echo "$(awk 'NF {sub(/\\n/, ""); printf "%s\\\\\\\n",$0;}' "$1")"
}

function json_ccp {
    local PP=$(one_line_pem "$6")
    local CP=$(one_line_pem "$7")
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${ORGMSP}/$2/" \
        -e "s/\${MORG}/$3/" \
        -e "s/\${P0PORT}/$4/" \
        -e "s/\${CAPORT}/$5/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        ccp-template.json
}

function yaml_ccp {
    local PP=$(one_line_pem "$6")
    local CP=$(one_line_pem "$7")
    sed -e "s/\${ORG}/$1/" \
        -e "s/\${ORGMSP}/$2/" \
        -e "s/\${MORG}/$3/" \
        -e "s/\${P0PORT}/$4/" \
        -e "s/\${CAPORT}/$5/" \
        -e "s#\${PEERPEM}#$PP#" \
        -e "s#\${CAPEM}#$CP#" \
        ccp-template.yaml | sed -e $'s/\\\\n/\\\n          /g'
}
CCPSCRIPT

for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  PEER_PORT=$(get_host_peer_port $i)
  CA_PORT=$(get_host_ca_port $i)
  cat >> "${OUTPUT_DIR}/organizations/ccp-generate.sh" << EOF

ORG=${ORG_CAP}
MORG=${ORG}
ORGMSP=${ORG_CAP}
P0PORT=${PEER_PORT}
CAPORT=${CA_PORT}
PEERPEM=crypto-config/peerOrganizations/${ORG}.com/tlsca/tlsca.${ORG}.com-cert.pem
CAPEM=crypto-config/peerOrganizations/${ORG}.com/ca/ca.${ORG}.com-cert.pem

echo "\$(json_ccp \$ORG \$ORGMSP \$MORG \$P0PORT \$CAPORT \$PEERPEM \$CAPEM)" > crypto-config/peerOrganizations/${ORG}.com/connection-${ORG}.json
echo "\$(yaml_ccp \$ORG \$ORGMSP \$MORG \$P0PORT \$CAPORT \$PEERPEM \$CAPEM)" > crypto-config/peerOrganizations/${ORG}.com/connection-${ORG}.yaml
EOF
done
chmod +x "${OUTPUT_DIR}/organizations/ccp-generate.sh"

# CCP 模板
cat > "${OUTPUT_DIR}/organizations/ccp-template.json" << 'EOF'
{
    "name": "test-network-${ORG}",
    "version": "1.0.0",
    "client": {
        "organization": "${ORG}",
        "connection": {
            "timeout": {
                "peer": { "endorser": "300" }
            }
        }
    },
    "organizations": {
        "${ORG}": {
            "mspid": "${ORGMSP}MSP",
            "peers": ["peer0.${MORG}.com"]
        }
    },
    "peers": {
        "peer0.${MORG}.com": {
            "url": "grpcs://peer0.${MORG}.com:${P0PORT}",
            "tlsCACerts": { "pem": "${PEERPEM}" },
            "grpcOptions": {
                "ssl-target-name-override": "peer0.${MORG}.com",
                "hostnameOverride": "peer0.${MORG}.com"
            }
        }
    }
}
EOF

cat > "${OUTPUT_DIR}/organizations/ccp-template.yaml" << 'EOF'
---
name: test-network-org${ORG}
version: 1.0.0
client:
  organization: ${ORG}
  connection:
    timeout:
      peer:
        endorser: '300'
      orderer: '300'
organizations:
  ${ORG}:
    mspid: ${ORGMSP}MSP
    peers:
    - peer0.${MORG}.com
peers:
  peer0.${MORG}.com:
    url: grpcs://peer0.${MORG}.com:${P0PORT}
    tlsCACerts:
      pem: |
          ${PEERPEM}
    grpcOptions:
      ssl-target-name-override: peer0.${MORG}.com
      hostnameOverride: peer0.${MORG}.com
EOF

# ================================================================
# 8. 生成 restart.sh
# ================================================================
printInfo "生成 restart.sh..."

COMPOSE_FILES="-f ./docker/docker-compose-order.yaml"
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  COMPOSE_FILES="${COMPOSE_FILES} -f ./docker/docker-compose-${ORG}.yaml"
done
COMPOSE_FILES="${COMPOSE_FILES} -f ./docker/docker-compose-cli.yaml"

cat > "${OUTPUT_DIR}/restart.sh" << EOF
#!/bin/bash
set -e

echo "重啟所有 Fabric 容器..."

# 清理舊的鏈碼容器
DOCKER_IMAGE_IDS=\$(docker images | awk '(\$1 ~ /dev-peer.*/) {print \$3}')
if [ -n "\$DOCKER_IMAGE_IDS" ] && [ "\$DOCKER_IMAGE_IDS" != " " ]; then
  echo "清理鏈碼映像..."
  docker rmi -f \$DOCKER_IMAGE_IDS
fi

docker compose ${COMPOSE_FILES} restart

echo "重啟完成"
EOF
chmod +x "${OUTPUT_DIR}/restart.sh"

# ================================================================
# 9. 生成 docker_ps.sh
# ================================================================
printInfo "生成 docker_ps.sh..."

cat > "${OUTPUT_DIR}/docker_ps.sh" << 'EOF'
#!/bin/bash
echo "=== Orderer 節點 ==="
docker ps -a --filter "name=orderer" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== Peer 節點 ==="
docker ps -a --filter "name=peer" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== CouchDB ==="
docker ps -a --filter "name=couchdb" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "=== CLI ==="
docker ps -a --filter "name=cli" --format "table {{.Names}}\t{{.Status}}"
echo ""
echo "=== CA ==="
docker ps -a --filter "name=ca-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
EOF
chmod +x "${OUTPUT_DIR}/docker_ps.sh"

# ================================================================
# 10. 生成 start.sh (從本機啟動所有節點 + 建立 channel + 部署 chaincode)
# ================================================================
printInfo "生成 start.sh..."

ORDERER0_PORT=$(get_host_orderer_port 0)

# --- 開頭: shebang + help ---
cat > "${OUTPUT_DIR}/start.sh" << 'STARTEOF'
#!/bin/bash

function printhelp(){
	printf "用法:\n"
	printf "\t./start.sh up                                                # 啟動所有節點\n"
	printf "\t./start.sh restart                                           # 重啟所有容器\n"
	printf "\t./start.sh set_channel                                       # 啟動 + 建立 channel\n"
	printf "\t./start.sh set_chaincode                                     # 啟動 + channel + chaincode\n"
	printf "\t./start.sh deploy <name> <file> <label> <version> <sequence> # 部署 chaincode\n"
	printf "\t./start.sh deploy <name> <file> <label> <version> <sequence> <package_id>\n"
}

STARTEOF

# --- docker_up(): 啟動所有節點 (本機 + SSH 遠端) ---
cat >> "${OUTPUT_DIR}/start.sh" << 'EOF'
function docker_up(){
	echo "=========================================="
	echo " 啟動所有節點"
	echo "=========================================="
EOF

# 啟動所有 orderer
for (( i=0; i<NUM_ORDERERS; i++ )); do
  ORD_HOST="${ORDERER_HOSTS[$i]:-}"
  ORD_DIR="${ORDERER_DIRS[$i]:-}"
  if [ -z "$ORD_HOST" ] || [ "$ORD_HOST" = "local" ]; then
    cat >> "${OUTPUT_DIR}/start.sh" << EOF

	echo "[本機] 啟動 orderer${i}..."
	docker network create fabric-center 2>/dev/null || true
	docker compose -f ./docker/docker-compose-order.yaml up -d orderer${i}.com
EOF
  else
    cat >> "${OUTPUT_DIR}/start.sh" << EOF

	echo "[遠端] 啟動 orderer${i} @ ${ORD_HOST}..."
	ssh ${ORD_HOST} "cd ${ORD_DIR} && docker network create fabric-center 2>/dev/null; docker compose -f ./docker/docker-compose-order.yaml up -d orderer${i}.com"
EOF
  fi
done

cat >> "${OUTPUT_DIR}/start.sh" << 'EOF'

	echo ""
	echo "等待 Orderer 就緒..."
	sleep 5
EOF

# 啟動所有 peer + cli
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  P_HOST="${PEER_HOSTS[$i]:-}"
  P_DIR="${PEER_DIRS[$i]:-}"
  if [ -z "$P_HOST" ] || [ "$P_HOST" = "local" ]; then
    cat >> "${OUTPUT_DIR}/start.sh" << EOF

	echo "[本機] 啟動 ${ORG}..."
	docker compose -f ./docker/docker-compose-${ORG}.yaml up -d
	docker compose -f ./docker/docker-compose-cli.yaml up -d cli${i}
EOF
  else
    cat >> "${OUTPUT_DIR}/start.sh" << EOF

	echo "[遠端] 啟動 ${ORG} @ ${P_HOST}..."
	ssh ${P_HOST} "cd ${P_DIR} && docker network create fabric-center 2>/dev/null; docker compose -f ./docker/docker-compose-${ORG}.yaml up -d; docker compose -f ./docker/docker-compose-cli.yaml up -d cli${i}"
EOF
  fi
done

cat >> "${OUTPUT_DIR}/start.sh" << 'EOF'

	echo ""
	echo "所有節點啟動完成"
	docker ps -a | grep -E "orderer|peer|couch|cli" || true
}
EOF

# --- restartAllDocker() ---
{
  echo ""
  echo "function restartAllDocker(){"
  echo "	echo \"重啟所有容器...\""
  # 本機 compose restart
  COMPOSE_ARGS="-f ./docker/docker-compose-order.yaml"
  for (( i=0; i<NUM_ORGS; i++ )); do
    COMPOSE_ARGS="${COMPOSE_ARGS} -f ./docker/docker-compose-${ORG_NAMES[$i]}.yaml"
  done
  COMPOSE_ARGS="${COMPOSE_ARGS} -f ./docker/docker-compose-cli.yaml"
  echo "	docker compose ${COMPOSE_ARGS} restart"
  # 遠端 restart
  for (( i=1; i<NUM_ORGS; i++ )); do
    P_HOST="${PEER_HOSTS[$i]:-}"
    P_DIR="${PEER_DIRS[$i]:-}"
    ORG="${ORG_NAMES[$i]}"
    if [ -n "$P_HOST" ] && [ "$P_HOST" != "local" ]; then
      echo "	ssh ${P_HOST} \"cd ${P_DIR} && docker compose -f ./docker/docker-compose-${ORG}.yaml restart\""
    fi
  done
  cat << 'RESTART_BODY'
	DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
	if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
		echo "No images available for restart"
	else
		docker restart $DOCKER_IMAGE_IDS 2>/dev/null || true
	fi
}
RESTART_BODY
} >> "${OUTPUT_DIR}/start.sh"

# --- setchannel() ---
cat >> "${OUTPUT_DIR}/start.sh" << 'EOF'

function setchannel(){
EOF

for (( ci=0; ci<${#CHANNEL_NAMES[@]}; ci++ )); do
  ch_name="${CHANNEL_NAMES[$ci]}"
  FIRST_ORG=$(echo ${CHANNEL_ORGS_LIST[$ci]} | awk '{print $1}')
  FIRST_ORG_IDX=$(org_index $FIRST_ORG)

  cat >> "${OUTPUT_DIR}/start.sh" << EOF

	printf "\\n建立 Channel: ${ch_name}...\\n"
	docker exec -it cli${FIRST_ORG_IDX} peer channel create -o orderer0.com:${ORDERER0_PORT} -c ${ch_name} -f ./channel-artifacts/${ch_name}.tx --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/msp/tlscacerts/tlsca.com-cert.pem

	printf "分發 ${ch_name} block...\\n"
	docker cp cli${FIRST_ORG_IDX}:/opt/gopath/src/github.com/hyperledger/fabric/peer/${ch_name}.block ./
EOF

  for org_id in ${CHANNEL_ORGS_LIST[$ci]}; do
    if [ "$org_id" != "$FIRST_ORG" ]; then
      ORG_IDX=$(org_index $org_id)
      echo "	docker cp ./${ch_name}.block cli${ORG_IDX}:/opt/gopath/src/github.com/hyperledger/fabric/peer/" >> "${OUTPUT_DIR}/start.sh"
    fi
  done

  cat >> "${OUTPUT_DIR}/start.sh" << EOF

	printf "Org 加入 ${ch_name}...\\n"
EOF
  for org_id in ${CHANNEL_ORGS_LIST[$ci]}; do
    ORG_IDX=$(org_index $org_id)
    echo "	docker exec -it cli${ORG_IDX} peer channel join -b ./${ch_name}.block" >> "${OUTPUT_DIR}/start.sh"
  done

  cat >> "${OUTPUT_DIR}/start.sh" << EOF

	printf "更新 ${ch_name} 錨節點...\\n"
EOF
  for org_id in ${CHANNEL_ORGS_LIST[$ci]}; do
    ORG_IDX=$(org_index $org_id)
    ORG_ID_CAP=$(capitalize $org_id)
    echo "	docker exec -it cli${ORG_IDX} peer channel update -o orderer0.com:${ORDERER0_PORT} -c ${ch_name} -f ./channel-artifacts/${ch_name}_${ORG_ID_CAP}MSPanchors.tx --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem" >> "${OUTPUT_DIR}/start.sh"
  done
done

cat >> "${OUTPUT_DIR}/start.sh" << 'EOF'

	printf "\n所有 channel 設定完成\n"
	rm -rf *.block
}
EOF

# --- set_chaincode() ---
DEFAULT_CHANNEL="${CHANNEL_NAMES[0]}"
{
  echo ""
  echo "function set_chaincode(){"
  for (( i=0; i<NUM_ORGS; i++ )); do
    echo "	./uint/set_chaincode.sh cli${i} \$package_id \${channel_name:-${DEFAULT_CHANNEL}} \$contract \$chaincode_version \$chaincode_sequence"
  done
  echo "}"
} >> "${OUTPUT_DIR}/start.sh"

# --- chaincode_commit_invoke() ---
cat >> "${OUTPUT_DIR}/start.sh" << EOF

function chaincode_commit_invoke(){
	./uint/chaincode_seting_all.sh \${channel_name:-${DEFAULT_CHANNEL}} \$contract \$chaincode_version \$chaincode_sequence
}
EOF

# --- setup() ---
cat >> "${OUTPUT_DIR}/start.sh" << 'EOF'

function setup(){
	if [ "$set_data" = "up" ]; then
		docker_up

	elif [ "$set_data" = "restart" ]; then
		restartAllDocker

	elif [ "$set_data" = "set_channel" ]; then
		docker_up
		sleep 5
		setchannel

	elif [ "$set_data" = "set_chaincode" ]; then
		docker_up
		sleep 5
		setchannel
		./uint/deploy.sh $contract $contract_file $contract_1
		set_chaincode
		chaincode_commit_invoke
		rm -rf *.block

	elif [ "$set_data" = "deploy" ]; then
		./uint/deploy.sh $contract $contract_file $contract_1
		set_chaincode
		chaincode_commit_invoke
		rm -rf *.block

	else
		printhelp
	fi
}

if [ $# -eq 1 ] || [ $# -eq 6 ] || [ $# -eq 7 ]; then
	set_data=$1
	contract=$2
	contract_file=$3
	contract_1=$4
	chaincode_version=$5
	chaincode_sequence=$6
	package_id=$7
	setup
else
	printhelp
fi
EOF
chmod +x "${OUTPUT_DIR}/start.sh"

# ================================================================
# 11. 生成 stop.sh
# ================================================================
printInfo "生成 stop.sh..."

cat > "${OUTPUT_DIR}/stop.sh" << 'STOPEOF'
#!/bin/bash
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    echo "No images available for deletion"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

ss=$1

STOPEOF

# 本機停止 (第一個 org + orderer + cli)
cat >> "${OUTPUT_DIR}/stop.sh" << EOF
echo "停止本機容器..."
docker compose -f ./docker/docker-compose-order.yaml -f ./docker/docker-compose-${ORG_NAMES[0]}.yaml -f ./docker/docker-compose-cli.yaml down \$1
EOF

# 遠端停止各 org
for (( i=1; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  REMOTE_HOST="${PEER_HOSTS[$i]:-}"
  REMOTE_DIR="${PEER_DIRS[$i]:-}"

  if [ -n "$REMOTE_HOST" ] && [ "$REMOTE_HOST" != "local" ]; then
    cat >> "${OUTPUT_DIR}/stop.sh" << EOF

echo "停止 ${ORG} @ ${REMOTE_HOST}..."
ssh ${REMOTE_HOST} "cd ${REMOTE_DIR} && docker compose -f ./docker/docker-compose-${ORG}.yaml down \${ss}"
EOF
  else
    cat >> "${OUTPUT_DIR}/stop.sh" << EOF

echo "停止 ${ORG} (本機)..."
docker compose -f ./docker/docker-compose-${ORG}.yaml down \$1
EOF
  fi
done

cat >> "${OUTPUT_DIR}/stop.sh" << 'STOPEOF'

if [ "$ss" = "-v" ]; then
    removeUnwantedImages
fi
STOPEOF
chmod +x "${OUTPUT_DIR}/stop.sh"

# ================================================================
# 11b. 生成 all_node_start.sh (從本機啟動所有節點)
# ================================================================
printInfo "生成 all_node_start.sh..."

cat > "${OUTPUT_DIR}/all_node_start.sh" << 'HEADER'
#!/bin/bash
set -e
echo "=========================================="
echo " 啟動所有節點"
echo "=========================================="
HEADER

# 啟動本機 orderer (如果有)
for (( i=0; i<NUM_ORDERERS; i++ )); do
  ORD_HOST="${ORDERER_HOSTS[$i]:-}"
  ORD_DIR="${ORDERER_DIRS[$i]:-}"
  if [ -z "$ORD_HOST" ] || [ "$ORD_HOST" = "local" ]; then
    cat >> "${OUTPUT_DIR}/all_node_start.sh" << EOF

echo "[本機] 啟動 orderer${i}..."
cd ${ORD_DIR:-\$(pwd)}
docker network create fabric-center 2>/dev/null || true
docker compose -f ./docker/docker-compose-order.yaml up -d orderer${i}.com
EOF
  else
    cat >> "${OUTPUT_DIR}/all_node_start.sh" << EOF

echo "[遠端] 啟動 orderer${i} @ ${ORD_HOST}..."
ssh ${ORD_HOST} "cd ${ORD_DIR} && docker network create fabric-center 2>/dev/null; docker compose -f ./docker/docker-compose-order.yaml up -d orderer${i}.com"
EOF
  fi
done

cat >> "${OUTPUT_DIR}/all_node_start.sh" << 'EOF'

echo ""
echo "等待 Orderer 就緒..."
sleep 5
EOF

# 啟動所有 peer org
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  P_HOST="${PEER_HOSTS[$i]:-}"
  P_DIR="${PEER_DIRS[$i]:-}"
  if [ -z "$P_HOST" ] || [ "$P_HOST" = "local" ]; then
    cat >> "${OUTPUT_DIR}/all_node_start.sh" << EOF

echo "[本機] 啟動 ${ORG}..."
cd ${P_DIR:-\$(pwd)}
docker compose -f ./docker/docker-compose-${ORG}.yaml up -d
docker compose -f ./docker/docker-compose-cli.yaml up -d cli${i}
EOF
  else
    cat >> "${OUTPUT_DIR}/all_node_start.sh" << EOF

echo "[遠端] 啟動 ${ORG} @ ${P_HOST}..."
ssh ${P_HOST} "cd ${P_DIR} && docker network create fabric-center 2>/dev/null; docker compose -f ./docker/docker-compose-${ORG}.yaml up -d; docker compose -f ./docker/docker-compose-cli.yaml up -d cli${i}"
EOF
  fi
done

cat >> "${OUTPUT_DIR}/all_node_start.sh" << 'EOF'

echo ""
echo "=========================================="
echo " 所有節點啟動完成"
echo "=========================================="
echo ""
echo "查看狀態: bash docker_ps.sh"
echo "建立 Channel: ./start.sh set_channel"
EOF
chmod +x "${OUTPUT_DIR}/all_node_start.sh"

# ================================================================
# 12. 生成 fabric-explorer 配置
# ================================================================
printInfo "生成 Fabric Explorer 配置..."

# config.json
{
  echo '{'
  echo '  "network-configs": {'
  for (( i=0; i<NUM_ORGS; i++ )); do
    ORG="${ORG_NAMES[$i]}"
    COMMA=","
    if [ $i -eq $((NUM_ORGS-1)) ]; then COMMA=""; fi
    echo "    \"${ORG}.com\": {"
    echo "      \"name\": \"${ORG}.com\","
    echo "      \"profile\": \"./connection-profile/${ORG}-network.json\""
    echo "    }${COMMA}"
  done
  echo '  },'
  echo '  "license": "Apache-2.0"'
  echo '}'
} > "${OUTPUT_DIR}/fabric-explorer/config.json"

# explorer docker-compose
cat > "${OUTPUT_DIR}/fabric-explorer/docker-compose.yaml" << EOF
version: '2.1'

volumes:
  pgdata:
  walletstore:

networks:
  mynetwork.com:
    external:
      name: fabric-center

services:

  explorerdb.mynetwork.com:
    image: hyperledger/explorer-db:latest
    container_name: explorerdb.mynetwork.com
    hostname: explorerdb.mynetwork.com
    environment:
      - DATABASE_DATABASE=fabricexplorer
      - DATABASE_USERNAME=hppoc
      - DATABASE_PASSWORD=password
    healthcheck:
      test: "pg_isready -h localhost -p 5432 -q -U postgres"
      interval: 30s
      timeout: 10s
      retries: 5
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - mynetwork.com

  explorer.mynetwork.com:
    image: hyperledger/explorer:latest
    container_name: explorer.mynetwork.com
    hostname: explorer.mynetwork.com
    environment:
      - DATABASE_HOST=explorerdb.mynetwork.com
      - DATABASE_DATABASE=fabricexplorer
      - DATABASE_USERNAME=hppoc
      - DATABASE_PASSWD=password
      - LOG_LEVEL_APP=info
      - LOG_LEVEL_DB=info
      - LOG_LEVEL_CONSOLE=debug
      - LOG_CONSOLE_STDOUT=true
      - DISCOVERY_AS_LOCALHOST=false
      - PORT=8055
    volumes:
      - ./config.json:/opt/explorer/app/platform/fabric/config.json
      - ./connection-profile/:/opt/explorer/app/platform/fabric/connection-profile
      - ${EXPLORER_PREFIX}/organizations/crypto-config/:/tmp/crypto
      - walletstore:/opt/explorer/wallet
    ports:
      - 8055:8055
    depends_on:
      explorerdb.mynetwork.com:
        condition: service_healthy
    networks:
      - mynetwork.com
EOF

# explorer connection profiles
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  ORG_CAP="$(capitalize ${ORG_NAMES[$i]})"
  PEER_PORT=$(get_host_peer_port $i)
  cat > "${OUTPUT_DIR}/fabric-explorer/connection-profile/${ORG}-network.json" << EOF
{
  "name": "${ORG}.com",
  "version": "1.0.0",
  "client": {
    "tlsEnable": true,
    "adminCredential": {
      "id": "exploreradmin",
      "password": "exploreradminpw"
    },
    "enableAuthentication": true,
    "organization": "${ORG_CAP}MSP",
    "connection": {
      "timeout": {
        "peer": { "endorser": "300" },
        "orderer": "300"
      }
    }
  },
  "channels": {
    "${CHANNEL_NAME}": {
      "peers": { "peer0.${ORG}.com": {} }
    }
  },
  "organizations": {
    "${ORG_CAP}MSP": {
      "mspid": "${ORG_CAP}MSP",
      "adminPrivateKey": {
        "path": "/tmp/crypto/peerOrganizations/${ORG}.com/users/Admin@${ORG}.com/msp/keystore/priv_sk"
      },
      "peers": ["peer0.${ORG}.com"],
      "signedCert": {
        "path": "/tmp/crypto/peerOrganizations/${ORG}.com/users/Admin@${ORG}.com/msp/signcerts/Admin@${ORG}.com-cert.pem"
      }
    }
  },
  "peers": {
    "peer0.${ORG}.com": {
      "tlsCACerts": {
        "path": "/tmp/crypto/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/tls/ca.crt"
      },
      "url": "grpcs://peer0.${ORG}.com:${PEER_PORT}"
    }
  }
}
EOF
done

# ================================================================
# 13. 生成 uint/ 操作腳本 (依照 example 模式)
# ================================================================
printInfo "生成 uint/ 操作腳本..."
mkdir -p "${OUTPUT_DIR}/uint"

# --- uint/all_cmd.sh ---
# 在所有遠端 peer 機器上執行指定命令 (本機除外)
cat > "${OUTPUT_DIR}/uint/all_cmd.sh" << 'ALLCMD_HEADER'
#!/bin/bash
# 在所有遠端 peer 機器上執行指定命令
# 用法: ./uint/all_cmd.sh "要執行的命令"
ALLCMD_HEADER

for (( i=1; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  REMOTE_HOST="${PEER_HOSTS[$i]:-}"
  REMOTE_DIR="${PEER_DIRS[$i]:-}"

  if [ -n "$REMOTE_HOST" ] && [ "$REMOTE_HOST" != "local" ]; then
    cat >> "${OUTPUT_DIR}/uint/all_cmd.sh" << EOF

printf "\\n==============\\n"
printf "${ORG} @ ${REMOTE_HOST}\\n\\n"
ssh -t ${REMOTE_HOST} "cd ${REMOTE_DIR} && \$@"
EOF
  fi
done

echo 'printf "\n==============\n"' >> "${OUTPUT_DIR}/uint/all_cmd.sh"
chmod +x "${OUTPUT_DIR}/uint/all_cmd.sh"

# --- uint/ssh_docker.sh ---
cat > "${OUTPUT_DIR}/uint/ssh_docker.sh" << 'EOF'
#!/bin/bash
# 透過 SSH 在遠端機器上操作 Docker Compose
# 用法: ./uint/ssh_docker.sh <user> <ip> <org> <docker_cmd> [docker_args]
#
# 範例:
#   ./uint/ssh_docker.sh clc1 192.168.0.11 org1 up -d
#   ./uint/ssh_docker.sh clc1 192.168.0.11 org1 down -v

user=$1
ip=$2
org=$3
docker_set1=$4
docker_set2=$5
workdir=$(basename $(pwd))

ssh ${user}@${ip} docker network create fabric-center 2>/dev/null || true
ssh ${user}@${ip} "docker compose -f ~/${workdir}/docker/docker-compose-order.yaml -f ~/${workdir}/docker/docker-compose-${org}.yaml ${docker_set1} ${docker_set2}"
ssh ${user}@${ip} "docker ps -a | grep orderer"
ssh ${user}@${ip} "docker ps -a | grep peer"
ssh ${user}@${ip} "docker ps -a | grep couch"
ssh ${user}@${ip} "docker ps -a | grep cli"
EOF
chmod +x "${OUTPUT_DIR}/uint/ssh_docker.sh"

# --- uint/deploy.sh ---
# 打包 chaincode 並分發到所有 CLI 容器安裝
cat > "${OUTPUT_DIR}/uint/deploy.sh" << 'DEPLOY_HEADER'
#!/bin/bash
# 打包 Chaincode 並分發安裝到所有 Peer
# 用法: ./uint/deploy.sh <chaincode_name> <chaincode_file> <label_name>
#
# 範例:
#   ./uint/deploy.sh mycc mycc mycc_1

set -e

chaincode_name=$1
chaincode_file=$2
label_name=$3

if [ -z "$chaincode_name" ] || [ -z "$chaincode_file" ] || [ -z "$label_name" ]; then
  echo "用法: ./uint/deploy.sh <chaincode_name> <chaincode_file> <label_name>"
  exit 1
fi

echo "打包 Chaincode: ${chaincode_name}..."
docker exec -it cli0 peer lifecycle chaincode package ${chaincode_name}.tar.gz \
  --path /opt/gopath/src/github.com/hyperledger/fabric-cluster/chaincode/go/${chaincode_file} \
  --lang golang \
  --label ${label_name}

echo "從 cli0 取出 chaincode 包..."
docker cp cli0:/opt/gopath/src/github.com/hyperledger/fabric/peer/${chaincode_name}.tar.gz ./

DEPLOY_HEADER

# 分發到所有 CLI 容器
for (( i=1; i<NUM_ORGS; i++ )); do
  cat >> "${OUTPUT_DIR}/uint/deploy.sh" << EOF
echo "分發到 cli${i}..."
docker cp ./\${chaincode_name}.tar.gz cli${i}:/opt/gopath/src/github.com/hyperledger/fabric/peer/
EOF
done

echo "" >> "${OUTPUT_DIR}/uint/deploy.sh"
echo "echo \"安裝 Chaincode 到所有 Peer...\"" >> "${OUTPUT_DIR}/uint/deploy.sh"

for (( i=0; i<NUM_ORGS; i++ )); do
  cat >> "${OUTPUT_DIR}/uint/deploy.sh" << EOF
echo "安裝到 cli${i}..."
docker exec -it cli${i} peer lifecycle chaincode install \${chaincode_name}.tar.gz
EOF
done

cat >> "${OUTPUT_DIR}/uint/deploy.sh" << 'EOF'

echo "Chaincode 打包及安裝完成"
echo "請使用以下命令查詢 package ID:"
echo "  docker exec cli0 peer lifecycle chaincode queryinstalled"
EOF
chmod +x "${OUTPUT_DIR}/uint/deploy.sh"

# --- uint/set_chaincode.sh ---
# 為單一 Org 審批 chaincode
ORDERER0_PORT=$(get_host_orderer_port 0)
cat > "${OUTPUT_DIR}/uint/set_chaincode.sh" << EOF
#!/bin/bash
# 為指定 Org 審批 Chaincode
# 用法: ./uint/set_chaincode.sh <cli_name> <package_id> <channel_name> <chaincode_name> <version> <sequence>
#
# 範例:
#   ./uint/set_chaincode.sh cli0 mycc_1:abc123... ${CHANNEL_NAME} mycc 1.0 1

cli_name=\$1
package_id=\$2
channel_name=\$3
chaincode_name=\$4
chaincode_version=\$5
chaincode_sequence=\$6

if [ -z "\$cli_name" ] || [ -z "\$package_id" ] || [ -z "\$channel_name" ] || [ -z "\$chaincode_name" ]; then
  echo "用法: ./uint/set_chaincode.sh <cli_name> <package_id> <channel_name> <chaincode_name> <version> <sequence>"
  exit 1
fi

echo "[\${cli_name}] 審批 Chaincode: \${chaincode_name}..."
docker exec -it \${cli_name} peer lifecycle chaincode approveformyorg \\
  -o orderer0.com:${ORDERER0_PORT} \\
  --ordererTLSHostnameOverride orderer0.com \\
  --init-required \\
  --channelID \${channel_name} \\
  --name \${chaincode_name} \\
  --version \${chaincode_version} \\
  --package-id \${package_id} \\
  --sequence \${chaincode_sequence} \\
  --tls true \\
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/msp/tlscacerts/tlsca.com-cert.pem

echo "[\${cli_name}] 檢查 Commit 就緒狀態..."
docker exec -it \${cli_name} peer lifecycle chaincode checkcommitreadiness \\
  -o orderer0.com:${ORDERER0_PORT} \\
  --ordererTLSHostnameOverride orderer0.com \\
  --init-required \\
  --channelID \${channel_name} \\
  --name \${chaincode_name} \\
  --version \${chaincode_version} \\
  --sequence \${chaincode_sequence} \\
  --tls true \\
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/msp/tlscacerts/tlsca.com-cert.pem \\
  --output json
EOF
chmod +x "${OUTPUT_DIR}/uint/set_chaincode.sh"

# --- uint/chaincode_seting_all.sh ---
# Commit chaincode 並 invoke init (需要所有 org 背書)
cat > "${OUTPUT_DIR}/uint/chaincode_seting_all.sh" << 'CHAINCODE_HEADER'
#!/bin/bash
# Commit Chaincode 並執行 Init (所有 Org 背書)
# 用法: ./uint/chaincode_seting_all.sh <channel_name> <chaincode_name> <version> <sequence>
#
# 範例:
#   ./uint/chaincode_seting_all.sh mychannel mycc 1.0 1

set -e

channel_name=$1
chaincode_name=$2
chaincode_version=$3
chaincode_sequence=$4

if [ -z "$channel_name" ] || [ -z "$chaincode_name" ] || [ -z "$chaincode_version" ] || [ -z "$chaincode_sequence" ]; then
  echo "用法: ./uint/chaincode_seting_all.sh <channel_name> <chaincode_name> <version> <sequence>"
  exit 1
fi

CHAINCODE_HEADER

# 生成各 org 的地址和 TLS 變數
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  PEER_PORT=$(get_host_peer_port $i)
  cat >> "${OUTPUT_DIR}/uint/chaincode_seting_all.sh" << EOF
${ORG}_addr=peer0.${ORG}.com:${PEER_PORT}
${ORG}_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${ORG}.com/peers/peer0.${ORG}.com/tls/ca.crt
EOF
done

echo "" >> "${OUTPUT_DIR}/uint/chaincode_seting_all.sh"

# 構建 commit 命令的 peerAddresses 參數
PEER_ARGS=""
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  PEER_ARGS="${PEER_ARGS} --peerAddresses \${${ORG}_addr} --tlsRootCertFiles \${${ORG}_tls}"
done

cat >> "${OUTPUT_DIR}/uint/chaincode_seting_all.sh" << EOF
echo "Commit Chaincode: \${chaincode_name}..."
docker exec -it cli0 peer lifecycle chaincode commit \\
  -o orderer0.com:${ORDERER0_PORT} \\
  --channelID \${channel_name} \\
  --name \${chaincode_name} \\
  --version \${chaincode_version} \\
  --sequence \${chaincode_sequence} \\
  --init-required \\
  --tls true \\
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem \\
 ${PEER_ARGS}

echo "查詢 Committed Chaincode..."
docker exec -it cli0 peer lifecycle chaincode querycommitted \\
  --channelID \${channel_name} \\
  --name \${chaincode_name} \\
  -o orderer0.com:${ORDERER0_PORT} \\
  --tls \\
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem

echo "執行 Chaincode Init..."
docker exec -it cli0 peer chaincode invoke \\
  -o orderer0.com:${ORDERER0_PORT} \\
  --ordererTLSHostnameOverride orderer0.com \\
  --tls \\
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem \\
  --isInit \\
  --channelID \${channel_name} \\
  --name \${chaincode_name} \\
 ${PEER_ARGS} \\
  -c '{"function":"InitLedger","Args":[]}'

echo "Chaincode Commit 及 Init 完成"
EOF
chmod +x "${OUTPUT_DIR}/uint/chaincode_seting_all.sh"

# ================================================================
# 14. 生成加密材料 (cryptogen) 和通道配置 (configtxgen)
# ================================================================
printInfo "生成加密材料 (cryptogen)..."

pushd "${OUTPUT_DIR}" > /dev/null

if [ -d "./organizations/crypto-config/ordererOrganizations" ]; then
  printWarn "加密材料已存在，刪除後重新生成..."
  rm -rf ./organizations/crypto-config/ordererOrganizations
  rm -rf ./organizations/crypto-config/peerOrganizations
fi

${CRYPTOGEN} generate --config=./organizations/crypto-config.yaml --output=./organizations/crypto-config
printInfo "加密材料生成完成"

# 生成通道配置
printInfo "生成通道配置 (configtxgen)..."
export FABRIC_CFG_PATH=${PWD}

if [ -d "./channel-artifacts" ]; then
  rm -rf ./channel-artifacts/*
fi
mkdir -p ./channel-artifacts

bash ./configtx.sh
printInfo "通道配置生成完成"

# 生成 CCP
printInfo "生成 CCP 連線設定..."
pushd organizations > /dev/null
bash ./ccp-generate.sh 2>/dev/null || true
popd > /dev/null

popd > /dev/null

# ================================================================
# 完成 — 輸出摘要
# ================================================================
echo ""
printInfo "=========================================="
printInfo " 所有配置文件已生成至: ${OUTPUT_DIR}/"
printInfo "=========================================="
echo ""
printInfo "生成的文件:"
echo "  ${OUTPUT_DIR}/"
echo "  ├── configtx.yaml"
echo "  ├── configtx.sh"
echo "  ├── start.sh"
echo "  ├── stop.sh"
echo "  ├── restart.sh"
echo "  ├── docker_ps.sh"
echo "  ├── docker/"
echo "  │   ├── docker-compose-order.yaml"
for (( i=0; i<NUM_ORGS; i++ )); do
  echo "  │   ├── docker-compose-${ORG_NAMES[$i]}.yaml"
done
echo "  │   └── docker-compose-cli.yaml"
echo "  ├── uint/"
echo "  │   ├── all_cmd.sh"
echo "  │   ├── ssh_docker.sh"
echo "  │   ├── deploy.sh"
echo "  │   ├── set_chaincode.sh"
echo "  │   └── chaincode_seting_all.sh"
echo "  ├── organizations/"
echo "  │   ├── crypto-config.yaml"
echo "  │   ├── ccp-generate.sh"
echo "  │   ├── ccp-template.json"
echo "  │   └── ccp-template.yaml"
echo "  ├── channel-artifacts/"
echo "  ├── chaincode/go/"
echo "  └── fabric-explorer/"
echo "      ├── config.json"
echo "      ├── docker-compose.yaml"
echo "      └── connection-profile/"
for (( i=0; i<NUM_ORGS; i++ )); do
  echo "          ├── ${ORG_NAMES[$i]}-network.json"
done
echo ""
printInfo "Port 分配:"
printf "  %-20s %-10s %-10s %-10s\n" "節點" "主要Port" "Admin" "Metrics"
printf "  %-20s %-10s %-10s %-10s\n" "----" "-------" "-----" "-------"
for (( i=0; i<NUM_ORDERERS; i++ )); do
  printf "  %-20s %-10s %-10s %-10s\n" \
    "orderer${i}.com" "$(get_host_orderer_port $i)" "$(get_host_orderer_admin $i)" "$(get_host_orderer_metrics $i)"
done
echo ""
printf "  %-20s %-10s %-10s %-10s\n" "節點" "Peer" "CA" "CouchDB"
printf "  %-20s %-10s %-10s %-10s\n" "----" "----" "--" "-------"
for (( i=0; i<NUM_ORGS; i++ )); do
  ORG="${ORG_NAMES[$i]}"
  printf "  %-20s %-10s %-10s %-10s\n" \
    "peer0.${ORG}.com" "$(get_host_peer_port $i)" "$(get_host_ca_port $i)" "$(get_host_couchdb_port $i)"
done
echo ""
printInfo "使用步驟:"
echo "  cd ${OUTPUT_DIR}"
echo ""
echo "  ./start.sh up                                                    # 僅啟動容器"
echo "  ./start.sh set_channel                                           # 啟動 + 建立 channel"
echo "  ./start.sh set_chaincode                                         # 啟動 + channel + chaincode"
echo "  ./start.sh deploy <name> <file> <label> <ver> <seq>              # 部署指定 chaincode"
echo "  ./start.sh deploy <name> <file> <label> <ver> <seq> <pkg_id>     # 部署 (指定 package_id)"
echo "  ./start.sh restart                                               # 重啟容器"
echo ""
echo "  bash stop.sh                                                     # 停止並清理網路"
echo "  bash docker_ps.sh                                                # 查看容器狀態"
echo ""
}

deploy_network() {

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 預設配置
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONFIG_FILE="network-config.yaml"
GENERATED_DIR="generated-network"
DRY_RUN=false
DEPLOY_ONLY=false
AUTO_START=false
CLEANUP=false
TEST_SSH=false
FABRIC_BIN_PATH=""

# 顏色與輸出函數沿用腳本頂部的全域定義 (勿在此重複宣告 readonly，會在 set -e 下中斷)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 參數解析
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

print_help() {
  cat << 'EOF'

╔═ Hyperledger Fabric 多機部署工具 ═════════════════════════════════════════╗

  讀取配置文件，自動生成網路配置並透過 SSH/SCP 分發到各目標機器。

  用法:
    ./deploy.sh [選項]

╔═ 選項 ════════════════════════════════════════════════════════════════════╗

  -f <檔案>    部署配置文件 (預設: network-config.yaml)
  -b <路徑>    Fabric 工具路徑 (cryptogen/configtxgen)
  -t           測試所有遠端機器的 SSH 連線
  -g           僅生成配置，不部署 (dry-run)
  -d           僅部署，跳過生成 (使用已存在的 generated-network)
  -s           部署後自動啟動所有節點
  -c           清理所有遠端節點 (停止容器並刪除部署目錄)
  -h           顯示此說明

╔═ 使用範例 ════════════════════════════════════════════════════════════════╗

  # 1. 測試 SSH 連線
  ./deploy.sh -f network-config.yaml -t

  # 2. 完整流程：生成 + 部署 + 自動啟動
  ./deploy.sh -f network-config.yaml -s

  # 3. 生成配置但不部署 (dry-run)
  ./deploy.sh -f network-config.yaml -g

  # 4. 僅部署（已生成）
  ./deploy.sh -f network-config.yaml -d

  # 5. 清理所有遠端節點
  ./deploy.sh -f network-config.yaml -c

╔═ 配置文件格式 ════════════════════════════════════════════════════════════╗

  # network-config.yaml
  channel: mychannel

  organizations:
    - org0
    - org1
    - org2

  orderers:
    - host: user@192.168.1.10
      dir: /opt/fabric-network
    - host: user@192.168.1.11
      dir: /opt/fabric-network

  peers:
    org0:
      host: user@192.168.1.20
      dir: /opt/fabric-network
    org1:
      host: user@192.168.1.21
      dir: /opt/fabric-network

╔═ 前置條件 ════════════════════════════════════════════════════════════════╗

  ✓ 目標機器已設定 SSH 無密碼登入 (執行: ssh-copy-id user@host)
  ✓ 目標機器已安裝 Docker 和 Docker Compose
  ✓ 本機已安裝 Fabric 工具 (cryptogen, configtxgen)

EOF
}

while getopts "f:b:tgdsch" opt; do
  case $opt in
    f) CONFIG_FILE="$OPTARG" ;;
    b) FABRIC_BIN_PATH="$OPTARG" ;;
    t) TEST_SSH=true ;;
    g) DRY_RUN=true ;;
    d) DEPLOY_ONLY=true ;;
    s) AUTO_START=true ;;
    c) CLEANUP=true ;;
    h) print_help; exit 0 ;;
    \?) error "無效選項: -$OPTARG"; exit 1 ;;
  esac
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 配置文件檢查
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ ! -f "$CONFIG_FILE" ]; then
  error "找不到配置文件: $CONFIG_FILE"
  info "請建立配置文件，參考格式見 -h 選項"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 配置解析
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

declare -a ORDERER_NODES=()
declare -a PEER_NODES=()
declare -a ALL_HOSTS=()
declare -a ORG_NAMES=()
CHANNEL_NAME="mychannel"

CURRENT_SECTION=""
CURRENT_PEER=""
CURRENT_PEER_HOST=""
CURRENT_PEER_DIR=""
CURRENT_ORD_HOST=""
CURRENT_ORD_DIR=""
ORDERER_IDX=0

# 刷新 orderer 配置
flush_orderer() {
  if [ -n "$CURRENT_ORD_HOST" ]; then
    ORDERER_NODES+=("${ORDERER_IDX}:${CURRENT_ORD_HOST}:${CURRENT_ORD_DIR}")
    local already_in=false
    for h in "${ALL_HOSTS[@]}"; do
      [ "$h" = "$CURRENT_ORD_HOST" ] && already_in=true && break
    done
    [ "$already_in" = false ] && ALL_HOSTS+=("$CURRENT_ORD_HOST")
    ORDERER_IDX=$((ORDERER_IDX + 1))
    CURRENT_ORD_HOST=""
    CURRENT_ORD_DIR=""
  fi
}

# 刷新 peer 配置
flush_peer() {
  if [ -n "$CURRENT_PEER" ] && [ -n "$CURRENT_PEER_HOST" ]; then
    PEER_NODES+=("${CURRENT_PEER}:${CURRENT_PEER_HOST}:${CURRENT_PEER_DIR}")
    local already_in=false
    for h in "${ALL_HOSTS[@]}"; do
      [ "$h" = "$CURRENT_PEER_HOST" ] && already_in=true && break
    done
    [ "$already_in" = false ] && ALL_HOSTS+=("$CURRENT_PEER_HOST")
    CURRENT_PEER=""
    CURRENT_PEER_HOST=""
    CURRENT_PEER_DIR=""
  fi
}

# 解析 YAML 配置
while IFS= read -r line; do
  # 跳過空行和註解
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # Section 偵測
  if [[ "$line" =~ ^organizations:[[:space:]]*$ ]]; then
    flush_orderer; flush_peer
    CURRENT_SECTION="organizations"; continue
  elif [[ "$line" =~ ^channels:[[:space:]]*$ ]]; then
    flush_orderer; flush_peer
    CURRENT_SECTION="channels"; continue
  elif [[ "$line" =~ ^orderers:[[:space:]]*$ ]]; then
    flush_orderer; flush_peer
    CURRENT_SECTION="orderers"; ORDERER_IDX=0; continue
  elif [[ "$line" =~ ^peers:[[:space:]]*$ ]]; then
    flush_orderer; flush_peer
    CURRENT_SECTION="peers"; continue
  elif [[ "$line" =~ ^[a-z] ]]; then
    flush_orderer; flush_peer
    CURRENT_SECTION=""; continue
  fi

  # organizations section
  if [ "$CURRENT_SECTION" = "organizations" ]; then
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+([a-z][a-z0-9]*) ]]; then
      ORG_NAMES+=("${BASH_REMATCH[1]}")
    fi
    continue
  fi

  # channels section
  if [ "$CURRENT_SECTION" = "channels" ]; then
    if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9.-]*):[[:space:]]*$ ]]; then
      CHANNEL_NAME="${BASH_REMATCH[1]}"
    fi
    continue
  fi

  # orderers section
  if [ "$CURRENT_SECTION" = "orderers" ]; then
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+host:[[:space:]]*(.+) ]]; then
      flush_orderer
      CURRENT_ORD_HOST="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]+dir:[[:space:]]*(.+) ]]; then
      CURRENT_ORD_DIR="${BASH_REMATCH[1]}"
      continue
    fi
  fi

  # peers section
  if [ "$CURRENT_SECTION" = "peers" ]; then
    if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9]*):[[:space:]]*$ ]]; then
      flush_peer
      CURRENT_PEER="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]+host:[[:space:]]*(.+) ]] && [ -n "$CURRENT_PEER" ]; then
      CURRENT_PEER_HOST="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]+dir:[[:space:]]*(.+) ]] && [ -n "$CURRENT_PEER" ]; then
      CURRENT_PEER_DIR="${BASH_REMATCH[1]}"
      continue
    fi
  fi

done < "$CONFIG_FILE"

flush_orderer
flush_peer

NUM_ORDERERS=${#ORDERER_NODES[@]}
NUM_ORGS=${#PEER_NODES[@]}

# 驗證配置
if [ "$NUM_ORDERERS" -eq 0 ]; then
  error "配置文件中沒有定義任何 orderer 節點"
  exit 1
fi
if [ "$NUM_ORGS" -eq 0 ]; then
  error "配置文件中沒有定義任何 peer 節點"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 自動決定部署目錄
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DEPLOY_DIRNAME="${NUM_ORDERERS}_orderer_${NUM_ORGS}_peer"
GENERATED_DIR="${HOME}/${DEPLOY_DIRNAME}"

# 填充遠端目錄
declare -a ORDERER_NODES_FINAL=()
for node in "${ORDERER_NODES[@]}"; do
  IFS=':' read -r idx ssh_target remote_dir <<< "$node"
  if [ -z "$remote_dir" ]; then
    if [[ "$ssh_target" == "local" || "$ssh_target" == "localhost" ]]; then
      remote_dir="${HOME}/${DEPLOY_DIRNAME}"
    else
      ORD_USER=$(echo "$ssh_target" | cut -d'@' -f1)
      remote_dir="/home/${ORD_USER}/${DEPLOY_DIRNAME}"
    fi
  fi
  ORDERER_NODES_FINAL+=("${idx}:${ssh_target}:${remote_dir}")
done
ORDERER_NODES=("${ORDERER_NODES_FINAL[@]}")

declare -a PEER_NODES_FINAL=()
for node in "${PEER_NODES[@]}"; do
  IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
  if [ -z "$remote_dir" ]; then
    if [[ "$ssh_target" == "local" || "$ssh_target" == "localhost" ]]; then
      remote_dir="${HOME}/${DEPLOY_DIRNAME}"
    else
      P_USER=$(echo "$ssh_target" | cut -d'@' -f1)
      remote_dir="/home/${P_USER}/${DEPLOY_DIRNAME}"
    fi
  fi
  PEER_NODES_FINAL+=("${org_name}:${ssh_target}:${remote_dir}")
done
PEER_NODES=("${PEER_NODES_FINAL[@]}")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 顯示配置摘要
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
step "部署配置摘要"
echo ""
info "配置文件:       $CONFIG_FILE"
info "Channel:        $CHANNEL_NAME"
info "部署目錄:       ${DEPLOY_DIRNAME}"
info "本機生成路徑:   ${GENERATED_DIR}"
info "Orderer 數量:   $NUM_ORDERERS"
info "Peer 組織數量:  $NUM_ORGS"
info "目標機器數量:   ${#ALL_HOSTS[@]}"
echo ""

info "節點分配:"
for node in "${ORDERER_NODES[@]}"; do
  IFS=':' read -r idx ssh_target remote_dir <<< "$node"
  printf "  ${GREEN}orderer%-3s${NC} → ${CYAN}%s${NC}:${DIM}%s${NC}\n" "${idx}" "$ssh_target" "$remote_dir"
done
for node in "${PEER_NODES[@]}"; do
  IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
  printf "  ${GREEN}%-12s${NC} → ${CYAN}%s${NC}:${DIM}%s${NC}\n" "${org_name}" "$ssh_target" "$remote_dir"
done
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 輔助函數：本機/遠端操作
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

is_local() {
  [[ "$1" == "local" || "$1" == "localhost" ]]
}

# 在目標機器上執行命令
run_on() {
  local host="$1"; shift
  if is_local "$host"; then
    eval "$@"
  else
    ssh "$host" "$@"
  fi
}

# 複製文件到目標機器 (支援遞迴)
copy_to() {
  local src="$1" host="$2" dest="$3"
  local dest_parent

  debug "copy_to: src=$src host=$host dest=$dest"

  # 驗證源文件/目錄
  if [ ! -e "$src" ]; then
    warn "源文件/目錄不存在: $src (跳過)"
    return 0
  fi

  dest_parent=$(dirname "$dest")

  # 本機複製
  if is_local "$host"; then
    mkdir -p "$dest_parent" 2>/dev/null || true

    if [ -d "$src" ]; then
      # 若目標目錄已存在，先移除避免 cp -r 產生嵌套 (dest/src-name/...)
      rm -rf "$dest"
      cp -r "$src" "$dest" 2>/dev/null || {
        warn "  無法複製目錄 (本機): $src"
        return 1
      }
    else
      cp "$src" "$dest" 2>/dev/null || {
        warn "  無法複製文件 (本機): $src"
        return 1
      }
    fi

    debug "✓ 已複製 (本機): $src → $dest"
    return 0
  fi

  # ─── 遠端複製 (使用 SCP) ───
  # 只建立父目錄，且若目標目錄已存在先移除，
  # 否則 scp -r 會把來源目錄放入既有目錄內，形成 dest/src-name/ 的錯誤嵌套
  debug "準備遠端目錄: ssh $host mkdir -p $dest_parent"

  if [ -d "$src" ]; then
    if ! ssh "$host" "rm -rf '$dest' && mkdir -p '$dest_parent'" 2>/dev/null; then
      warn "  無法準備遠端目錄: $host:$dest_parent"
      return 1
    fi
  else
    if ! ssh "$host" "mkdir -p '$dest_parent'" 2>/dev/null; then
      warn "  無法在遠端建立目錄: $host:$dest_parent"
      return 1
    fi
  fi

  # 執行 SCP 傳送 (-r 遞迴, -C 壓縮, -p 保留時間戳)
  debug "開始 SCP 傳送: scp -r -C -p $src $host:$dest"

  if scp -r -C -p "$src" "${host}:${dest}" 2>/tmp/scp_error_$$.log; then
    debug "✓ 已複製 (遠端): $src → $host:$dest"
    rm -f "/tmp/scp_error_$$.log"
    return 0
  else
    local scp_error=$(cat "/tmp/scp_error_$$.log" 2>/dev/null)
    warn "  無法複製到遠端:"
    warn "  源: $src"
    warn "  目標: $host:$dest"
    [ -n "$scp_error" ] && warn "  錯誤: $scp_error"
    rm -f "/tmp/scp_error_$$.log"
    return 1
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SSH 連線測試
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

test_ssh_connections() {
  step "測試 SSH 連線"
  echo ""

  local failed=0
  for host in "${ALL_HOSTS[@]}"; do
    if is_local "$host"; then
      success "本機"
    elif ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" &>/dev/null; then
      success "$host"
    else
      error "$host (連線失敗)"
      failed=1
    fi
  done

  if [ $failed -eq 1 ]; then
    error "部分機器 SSH 連線失敗"
    echo "解決方案:"
    echo "  1. 執行: ssh-copy-id user@host (配置無密碼登入)"
    echo "  2. 確認 SSH 服務運行: ssh user@host 'systemctl status ssh'"
    echo "  3. 檢查防火牆: ssh user@host 'sudo ufw status' (如適用)"
    return 1
  fi

  success "所有機器連線正常"
  echo ""
  return 0
}

if [ "$TEST_SSH" = true ]; then
  test_ssh_connections
  exit $?
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 清理遠端節點
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$CLEANUP" = true ]; then
  step "清理所有遠端節點"
  echo ""

  for node in "${ORDERER_NODES[@]}"; do
    IFS=':' read -r idx ssh_target remote_dir <<< "$node"
    info "清理 orderer${idx} @ $ssh_target"
    run_on "$ssh_target" "
      set +e
      [ -d ${remote_dir} ] && cd ${remote_dir} && \
      docker compose -f ./docker/docker-compose-order.yaml down -v 2>/dev/null
      rm -rf ${remote_dir} 2>/dev/null
      echo '已清理'
    " 2>/dev/null | sed 's/^/  /'
  done

  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    info "清理 $org_name @ $ssh_target"
    run_on "$ssh_target" "
      set +e
      [ -d ${remote_dir} ] && cd ${remote_dir} && \
      docker compose -f ./docker/docker-compose-${org_name}.yaml down -v 2>/dev/null && \
      docker compose -f ./docker/docker-compose-cli.yaml down -v 2>/dev/null && \
      docker rm -f \$(docker ps -aq --filter name=dev-peer) 2>/dev/null
      rm -rf ${remote_dir} 2>/dev/null
      echo '已清理'
    " 2>/dev/null | sed 's/^/  /'
  done

  success "清理完成"
  echo ""
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 驗證 SSH 連線
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if ! test_ssh_connections; then
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 生成配置 (本機)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$DEPLOY_ONLY" = false ]; then
  step "本機生成網路配置"
  echo ""

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  GEN_ARGS=(-o "$NUM_ORDERERS" -p "$NUM_ORGS" -c "$CHANNEL_NAME" -d "$GENERATED_DIR")

  [ -n "$FABRIC_BIN_PATH" ] && GEN_ARGS+=(-b "$FABRIC_BIN_PATH")

  bash "${SCRIPT_DIR}/generate-network.sh" "${GEN_ARGS[@]}"
  echo ""

  # 驗證生成結果
  if [ ! -d "$GENERATED_DIR" ]; then
    error "網路配置生成失敗"
    exit 1
  fi

  success "網路配置已生成至 $GENERATED_DIR"
  echo ""
fi

if [ "$DRY_RUN" = true ]; then
  info "Dry-run 模式：配置已生成，未執行部署"
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 驗證生成目錄
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ ! -d "$GENERATED_DIR" ]; then
  error "生成目錄不存在: $GENERATED_DIR (請先生成配置)"
  exit 1
fi

if [ ! -d "$GENERATED_DIR/docker" ]; then
  error "缺少 docker 目錄: $GENERATED_DIR/docker"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 部署公共文件到各機器
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

deploy_common_files() {
  local ssh_target=$1
  local remote_dir=$2
  local label=$3
  local retry=0
  local max_retries=3

  debug "為 $label 建立目錄結構"

  # 建立遠端目錄結構 (使用 -p 確保父目錄存在)
  # 注意：shell 的 {...} 展開可能在遠端失敗，改用順序建立
  while [ $retry -lt $max_retries ]; do
    if run_on "$ssh_target" "mkdir -p '${remote_dir}' && mkdir -p '${remote_dir}/docker' '${remote_dir}/channel-artifacts' '${remote_dir}/organizations' '${remote_dir}/chaincode/go'"; then
      debug "目錄結構建立成功"
      break
    else
      retry=$((retry + 1))
      if [ $retry -lt $max_retries ]; then
        warn "  目錄建立失敗，重試 ($retry/$max_retries)..."
        sleep 2
      fi
    fi
  done

  if [ $retry -eq $max_retries ]; then
    error "無法在 $label 建立目錄結構"
    return 1
  fi

  # 驗證本機生成文件存在
  if [ ! -d "${GENERATED_DIR}/organizations/crypto-config" ]; then
    warn "  加密材料不存在: ${GENERATED_DIR}/organizations/crypto-config (跳過)"
  else
    # 傳送加密材料
    info "  [$label] 傳送加密材料..."
    if ! copy_to "${GENERATED_DIR}/organizations/crypto-config" "$ssh_target" "${remote_dir}/organizations/crypto-config"; then
      warn "  加密材料傳送失敗，但繼續..."
    fi
  fi

  # 傳送通道配置
  if [ -d "${GENERATED_DIR}/channel-artifacts" ]; then
    info "  [$label] 傳送通道配置..."
    if ! copy_to "${GENERATED_DIR}/channel-artifacts" "$ssh_target" "${remote_dir}/channel-artifacts"; then
      warn "  通道配置傳送失敗，但繼續..."
    fi
  fi

  if [ -f "${GENERATED_DIR}/configtx.yaml" ]; then
    copy_to "${GENERATED_DIR}/configtx.yaml" "$ssh_target" "${remote_dir}/configtx.yaml" || true
  fi

  debug "公共文件部署完成 [$label]"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 部署 Orderer 節點
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "部署 Orderer 節點"
echo ""

for node in "${ORDERER_NODES[@]}"; do
  IFS=':' read -r idx ssh_target remote_dir <<< "$node"
  LABEL="orderer${idx} @ ${ssh_target}"

  info "部署 $LABEL"
  deploy_common_files "$ssh_target" "$remote_dir" "$LABEL"

  # 傳送 orderer docker-compose
  info "  [$LABEL] 傳送 docker-compose..."
  copy_to "${GENERATED_DIR}/docker/docker-compose-order.yaml" "$ssh_target" "${remote_dir}/docker/docker-compose-order.yaml"

  # 生成啟動腳本
  ORDERER_HOST_PORT=$(( 7050 + idx * 1000 ))
  ORDERER_ADMIN_PORT=$(( 7053 + idx * 1000 ))

  cat > "/tmp/node-start-orderer${idx}.sh" << NODEEOF
#!/bin/bash
set -e
echo "正在啟動 orderer${idx}..."

# 偵測 docker compose
if docker compose version &> /dev/null; then
  DC="docker compose"
elif command -v docker-compose &> /dev/null; then
  DC="docker-compose"
else
  echo "錯誤: 找不到 docker compose"; exit 1
fi

cd ${remote_dir}
docker network create fabric-center 2>/dev/null || true
\$DC -f ./docker/docker-compose-order.yaml up -d orderer${idx}.com

echo "✓ orderer${idx} 已啟動 (Port: ${ORDERER_HOST_PORT})"
docker ps --filter "name=orderer${idx}.com" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
NODEEOF

  copy_to "/tmp/node-start-orderer${idx}.sh" "$ssh_target" "${remote_dir}/node-start.sh"
  run_on "$ssh_target" "chmod +x ${remote_dir}/node-start.sh"
  rm -f "/tmp/node-start-orderer${idx}.sh"

  success "  [$LABEL] 部署完成"
done

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 部署 Peer 節點
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "部署 Peer 節點"
echo ""

PEER_DEPLOY_IDX=0
for node in "${PEER_NODES[@]}"; do
  IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
  LABEL="${org_name} @ ${ssh_target}"

  info "部署 $LABEL"
  deploy_common_files "$ssh_target" "$remote_dir" "$LABEL"

  # 傳送 peer docker-compose
  info "  [$LABEL] 傳送 docker-compose..."
  copy_to "${GENERATED_DIR}/docker/docker-compose-${org_name}.yaml" "$ssh_target" "${remote_dir}/docker/docker-compose-${org_name}.yaml"
  copy_to "${GENERATED_DIR}/docker/docker-compose-cli.yaml" "$ssh_target" "${remote_dir}/docker/docker-compose-cli.yaml"

  # 傳送 chaincode (如果存在)
  if [ -d "${GENERATED_DIR}/chaincode/go" ]; then
    info "  [$LABEL] 傳送 chaincode..."
    copy_to "${GENERATED_DIR}/chaincode/go" "$ssh_target" "${remote_dir}/chaincode/go"
  fi

  # 生成啟動腳本
  PEER_HOST_PORT=$(( 7051 + PEER_DEPLOY_IDX * 1000 ))

  cat > "/tmp/node-start-${org_name}.sh" << NODEEOF
#!/bin/bash
set -e
echo "正在啟動 ${org_name}..."

if docker compose version &> /dev/null; then
  DC="docker compose"
elif command -v docker-compose &> /dev/null; then
  DC="docker-compose"
else
  echo "錯誤: 找不到 docker compose"; exit 1
fi

cd ${remote_dir}
docker network create fabric-center 2>/dev/null || true
\$DC -f ./docker/docker-compose-${org_name}.yaml up -d
sleep 2
\$DC -f ./docker/docker-compose-cli.yaml up -d cli${PEER_DEPLOY_IDX}

echo "✓ ${org_name} 已啟動 (Port: ${PEER_HOST_PORT})"
docker ps --filter "name=${org_name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
NODEEOF

  copy_to "/tmp/node-start-${org_name}.sh" "$ssh_target" "${remote_dir}/node-start.sh"
  run_on "$ssh_target" "chmod +x ${remote_dir}/node-start.sh"
  rm -f "/tmp/node-start-${org_name}.sh"

  success "  [$LABEL] 部署完成"
  PEER_DEPLOY_IDX=$((PEER_DEPLOY_IDX + 1))
done

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 部署完成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

success "所有節點部署完成"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 自動啟動 (可選)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$AUTO_START" = true ]; then
  step "自動啟動所有節點"
  echo ""

  # 啟動 orderer
  info "啟動 Orderer..."
  for node in "${ORDERER_NODES[@]}"; do
    IFS=':' read -r idx ssh_target remote_dir <<< "$node"
    run_on "$ssh_target" "bash ${remote_dir}/node-start.sh" 2>&1 | sed 's/^/  /'
  done

  sleep 3

  # 啟動 peer
  info "啟動 Peer..."
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    run_on "$ssh_target" "bash ${remote_dir}/node-start.sh" 2>&1 | sed 's/^/  /'
  done

  echo ""
  success "所有節點已啟動"
  echo ""
else
  info "跳過自動啟動 (使用 -s 選項啟用)"
  echo ""
  info "手動啟動節點:"
  for node in "${ORDERER_NODES[@]}"; do
    IFS=':' read -r idx ssh_target remote_dir <<< "$node"
    echo "  ssh ${ssh_target} 'bash ${remote_dir}/node-start.sh'"
  done
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    echo "  ssh ${ssh_target} 'bash ${remote_dir}/node-start.sh'"
  done
  echo ""
fi
}

main() {
  local command="${1:-help}"

  # 移除第一個參數（命令）
  shift 2>/dev/null || true

  case "$command" in
    generate)
      print_banner

      # 檢查前置需求
      if ! check_requirements; then
        return 1
      fi

      # 執行生成
      generate_network "$@"

      if [ $? -eq 0 ]; then
        echo ""
        success "網路配置生成完成！"
        echo -e "${DIM}後續步驟:${NC}"
        echo "  cd generated-network"
        echo "  ./start.sh set_channel"
        echo ""
      fi
      ;;

    deploy)
      print_banner

      # 檢查前置需求
      if ! check_requirements; then
        return 1
      fi

      # 執行部署
      deploy_network "$@"

      if [ $? -eq 0 ]; then
        echo ""
        success "部署流程完成！"
        echo ""
      fi
      ;;

    version)
      print_version
      ;;

    help|--help|-h)
      print_banner
      print_usage
      ;;

    *)
      print_banner
      error "未知命令: ${BOLD}${command}${NC}"
      echo ""
      echo -e "${DIM}執行${NC} ${BOLD}./fabric-tool.sh help${NC} ${DIM}查看可用命令${NC}"
      echo ""
      return 1
      ;;
  esac
}

# 運行主程序
main "$@"
