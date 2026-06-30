#!/bin/bash
#
# Hyperledger Fabric 網路生成腳本
# 根據指定的 orderer 數量、peer(org) 數量、channel 名稱，自動生成所有配置文件
#
# 用法: ./generate-network.sh [選項]
#   -o <數量>    Orderer 節點數量 (預設: 5, 最少: 1)
#   -p <數量>    Peer 組織數量 (預設: 5, 最少: 1)
#   -c <名稱>    Channel 名稱 (預設: mychannel)
#   -d <目錄>    輸出目錄 (預設: generated-network)
#   -b <路徑>    Fabric 工具路徑 (cryptogen/configtxgen 所在目錄)
#   -w <路徑>    部署工作目錄，生成的檔案內會使用此絕對路徑 (預設: 使用相對路徑)
#   -h           顯示此說明
#
# 範例:
#   ./generate-network.sh -o 3 -p 4 -c mychannel
#   ./generate-network.sh -o 1 -p 2 -c testchannel -d my-network
#

set -e

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
