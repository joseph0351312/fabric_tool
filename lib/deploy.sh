#!/bin/bash
#
# Hyperledger Fabric 多機部署腳本
# 讀取配置文件，透過 scp/ssh 將節點配置分發到各目標機器並啟動
#
# 用法:
#   ./deploy.sh [選項]
#
# 選項:
#   -f <配置文件>    指定部署配置文件 (預設: network-config.yaml)
#   -g              僅生成配置，不部署 (dry-run)
#   -d              僅部署 (跳過生成，使用已存在的 generated-network)
#   -s              部署後自動啟動各節點
#   -c              清理所有遠端節點 (停止容器並刪除部署目錄)
#   -t              測試所有遠端機器的 SSH 連線
#   -h              顯示說明
#
# 使用範例:
#   # 完整流程：生成 + 部署
#   ./deploy.sh -f network-config.yaml
#
#   # 生成 + 部署 + 自動啟動
#   ./deploy.sh -f network-config.yaml -s
#
#   # 僅測試 SSH 連線
#   ./deploy.sh -f network-config.yaml -t
#
#   # 僅生成配置 (不部署)
#   ./deploy.sh -f network-config.yaml -g
#
#   # 清理所有遠端節點
#   ./deploy.sh -f network-config.yaml -c
#
# 前置條件:
#   - 目標機器已設定 SSH 無密碼登入 (ssh-copy-id)
#   - 目標機器已安裝 Docker 和 Docker Compose
#   - 本機已安裝 cryptogen, configtxgen (Fabric 工具)
#

set -e

# ====================== 預設值 ======================
CONFIG_FILE="network-config.yaml"
GENERATED_DIR="generated-network"
DRY_RUN=false
DEPLOY_ONLY=false
AUTO_START=false
CLEANUP=false
TEST_SSH=false
FABRIC_BIN_PATH=""

# ====================== 顏色輸出 ======================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

function printInfo()  { echo -e "${GREEN}[INFO]${NC} $1"; }
function printWarn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
function printError() { echo -e "${RED}[ERROR]${NC} $1"; }
function printStep()  { echo -e "${CYAN}[STEP]${NC} $1"; }

# ====================== 解析參數 ======================
while getopts "f:b:gdscth" opt; do
  case $opt in
    f) CONFIG_FILE=$OPTARG ;;
    b) FABRIC_BIN_PATH=$OPTARG ;;
    g) DRY_RUN=true ;;
    d) DEPLOY_ONLY=true ;;
    s) AUTO_START=true ;;
    c) CLEANUP=true ;;
    t) TEST_SSH=true ;;
    h)
      cat << 'HELPEOF'

  Hyperledger Fabric 多機部署工具
  ================================
  讀取配置文件，自動生成網路配置並透過 scp/ssh 分發到各目標機器。

  用法:
    ./deploy.sh [選項]

  選項:
    -f <配置文件>    指定部署配置文件 (預設: network-config.yaml)
    -g              僅生成配置，不部署 (dry-run)
    -d              僅部署，跳過生成 (使用已存在的 generated-network)
    -s              部署後自動啟動各節點
    -c              清理所有遠端節點 (停止容器並刪除部署目錄)
    -t              測試所有遠端機器的 SSH 連線
    -h              顯示此說明

  使用範例:
    # 完整流程：生成配置 + 部署到各機器
    ./deploy.sh -f network-config.yaml

    # 生成 + 部署 + 自動啟動所有節點
    ./deploy.sh -f network-config.yaml -s

    # 先測試 SSH 連線是否正常
    ./deploy.sh -f network-config.yaml -t

    # 僅生成配置，手動檢查後再部署
    ./deploy.sh -f network-config.yaml -g

    # 僅部署 (已經生成過配置)
    ./deploy.sh -f network-config.yaml -d

    # 清理所有遠端節點
    ./deploy.sh -f network-config.yaml -c

  配置文件格式 (network-config.yaml):
    channel: mychannel
    orderer:0:user@192.168.1.10:/opt/fabric-network
    orderer:1:user@192.168.1.11:/opt/fabric-network
    peer:0:user@192.168.1.20:/opt/fabric-network
    peer:1:user@192.168.1.21:/opt/fabric-network

  前置條件:
    - 目標機器已設定 SSH 無密碼登入
    - 目標機器已安裝 Docker 和 Docker Compose
    - 本機已安裝 cryptogen, configtxgen

  部署後各機器的目錄結構:
    /opt/fabric-network/
    ├── docker/
    │   ├── docker-compose-order.yaml   (orderer 機器)
    │   ├── docker-compose-orgN.yaml    (peer 機器)
    │   └── docker-compose-cli.yaml     (peer 機器)
    ├── organizations/crypto-config/     (所有機器)
    ├── channel-artifacts/               (所有機器)
    └── node-start.sh                    (各機器的啟動腳本)

HELPEOF
      exit 0
      ;;
    \?) printError "無效選項: -$OPTARG"; exit 1 ;;
  esac
done

# ====================== 讀取配置文件 ======================
if [ ! -f "$CONFIG_FILE" ]; then
  printError "找不到配置文件: $CONFIG_FILE"
  printInfo "請建立配置文件，參考範例: network-config.yaml"
  exit 1
fi

# 解析配置 (支援 YAML 結構格式)
declare -a ORDERER_NODES=()   # index:user@host:path
declare -a PEER_NODES=()      # orgname:user@host:path
declare -a ALL_HOSTS=()       # 所有不重複的 user@host
declare -a ORG_NAMES=()       # 組織名稱
declare -a CHANNEL_NAMES_DEPLOY=()
CHANNEL_NAME="mychannel"
HAS_CHANNEL_CONFIG=false

CURRENT_SECTION=""
CURRENT_PEER=""
CURRENT_PEER_HOST=""
CURRENT_PEER_DIR=""
CURRENT_ORD_HOST=""
CURRENT_ORD_DIR=""
ORDERER_IDX=0

# 輔助函數: 存入待處理的 orderer
function flush_orderer() {
  if [ -n "$CURRENT_ORD_HOST" ]; then
    ORDERER_NODES+=("${ORDERER_IDX}:${CURRENT_ORD_HOST}:${CURRENT_ORD_DIR}")
    local already_in=false
    for h in "${ALL_HOSTS[@]}"; do
      if [ "$h" = "$CURRENT_ORD_HOST" ]; then already_in=true; break; fi
    done
    if [ "$already_in" = false ]; then
      ALL_HOSTS+=("$CURRENT_ORD_HOST")
    fi
    ORDERER_IDX=$((ORDERER_IDX + 1))
    CURRENT_ORD_HOST=""
    CURRENT_ORD_DIR=""
  fi
}

# 輔助函數: 存入待處理的 peer
function flush_peer() {
  if [ -n "$CURRENT_PEER" ] && [ -n "$CURRENT_PEER_HOST" ]; then
    PEER_NODES+=("${CURRENT_PEER}:${CURRENT_PEER_HOST}:${CURRENT_PEER_DIR}")
    local already_in=false
    for h in "${ALL_HOSTS[@]}"; do
      if [ "$h" = "$CURRENT_PEER_HOST" ]; then already_in=true; break; fi
    done
    if [ "$already_in" = false ]; then
      ALL_HOSTS+=("$CURRENT_PEER_HOST")
    fi
    CURRENT_PEER=""
    CURRENT_PEER_HOST=""
    CURRENT_PEER_DIR=""
  fi
}

while IFS= read -r line; do
  # 跳過空行和註解
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

  # 頂層 section 偵測 (切換時 flush 前一 section 的未存入項目)
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

  # ─── organizations ───
  if [ "$CURRENT_SECTION" = "organizations" ]; then
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+([a-z][a-z0-9]*) ]]; then
      ORG_NAMES+=("${BASH_REMATCH[1]}")
    fi
    continue
  fi

  # ─── channels ───
  if [ "$CURRENT_SECTION" = "channels" ]; then
    if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9.-]*):[[:space:]]*$ ]]; then
      HAS_CHANNEL_CONFIG=true
      ch_name="${BASH_REMATCH[1]}"
      CHANNEL_NAMES_DEPLOY+=("$ch_name")
      if [ "$CHANNEL_NAME" = "mychannel" ]; then
        CHANNEL_NAME="$ch_name"
      fi
    fi
    continue
  fi

  # ─── orderers ───
  if [ "$CURRENT_SECTION" = "orderers" ]; then
    # "  - host: user@ip"
    if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+host:[[:space:]]*(.+) ]]; then
      local_match="${BASH_REMATCH[1]}"
      flush_orderer
      CURRENT_ORD_HOST="$local_match"
      CURRENT_ORD_DIR=""
      continue
    fi
    # "    dir: /path" (optional, backward compatible)
    if [[ "$line" =~ ^[[:space:]]+dir:[[:space:]]*(.+) ]]; then
      CURRENT_ORD_DIR="${BASH_REMATCH[1]}"
      continue
    fi
  fi

  # ─── peers ───
  if [ "$CURRENT_SECTION" = "peers" ]; then
    # peer org 名稱: "  orgname:"
    if [[ "$line" =~ ^[[:space:]]+([a-z][a-z0-9]*):[[:space:]]*$ ]]; then
      local_match="${BASH_REMATCH[1]}"
      flush_peer
      CURRENT_PEER="$local_match"
      CURRENT_PEER_HOST=""
      CURRENT_PEER_DIR=""
      continue
    fi
    # "    host: user@ip"
    if [[ "$line" =~ ^[[:space:]]+host:[[:space:]]*(.+) ]] && [ -n "$CURRENT_PEER" ]; then
      CURRENT_PEER_HOST="${BASH_REMATCH[1]}"
      continue
    fi
    # "    dir: /path" (optional, backward compatible)
    if [[ "$line" =~ ^[[:space:]]+dir:[[:space:]]*(.+) ]] && [ -n "$CURRENT_PEER" ]; then
      CURRENT_PEER_DIR="${BASH_REMATCH[1]}"
      continue
    fi
  fi

done < "$CONFIG_FILE"

# 處理最後一個未存入的項目
flush_orderer
flush_peer

NUM_ORDERERS=${#ORDERER_NODES[@]}
NUM_ORGS=${#PEER_NODES[@]}

# 如果 YAML 沒有 peers section 但有 organizations，用 org 數量
if [ "$NUM_ORGS" -eq 0 ] && [ ${#ORG_NAMES[@]} -gt 0 ]; then
  NUM_ORGS=${#ORG_NAMES[@]}
fi

if [ "$NUM_ORDERERS" -eq 0 ]; then
  printError "配置文件中沒有定義任何 orderer 節點 (orderers)"; exit 1
fi
if [ "$NUM_ORGS" -eq 0 ]; then
  printError "配置文件中沒有定義任何 peer 節點 (peers)"; exit 1
fi

# ====================== 自動決定部署目錄 ======================
# 資料夾名稱: N_orderer_M_peer (N=orderer數量, M=peer數量)
# 本機:  ~/N_orderer_M_peer
# 遠端:  /home/<user>/N_orderer_M_peer
DEPLOY_DIRNAME="${NUM_ORDERERS}_orderer_${NUM_ORGS}_peer"
GENERATED_DIR="${HOME}/${DEPLOY_DIRNAME}"

# 為每個沒有指定 dir 的節點自動填入 home 目錄
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

printInfo "=========================================="
printInfo " Hyperledger Fabric 多機部署"
printInfo "=========================================="
printInfo "配置文件:       $CONFIG_FILE"
printInfo "Channel:        $CHANNEL_NAME"
printInfo "部署目錄名稱:   ${DEPLOY_DIRNAME}"
printInfo "Orderer 數量:   $NUM_ORDERERS"
printInfo "Peer 組織數量:  $NUM_ORGS"
printInfo "目標機器數量:   ${#ALL_HOSTS[@]}"
printInfo "=========================================="
echo ""

# 顯示節點分配
printInfo "節點分配:"
for node in "${ORDERER_NODES[@]}"; do
  IFS=':' read -r idx ssh_target remote_dir <<< "$node"
  printf "  orderer%-3s -> %s:%s\n" "${idx}" "$ssh_target" "$remote_dir"
done
for node in "${PEER_NODES[@]}"; do
  IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
  printf "  %-12s -> %s:%s\n" "${org_name}" "$ssh_target" "$remote_dir"
done
echo ""

# ====================== 本機/遠端操作輔助函數 ======================
# 判斷 host 是否為本機
function is_local() { [[ "$1" == "local" || "$1" == "localhost" ]]; }

# 在目標機器上執行命令 (自動判斷本機/遠端)
function run_on() {
  local host="$1"; shift
  if is_local "$host"; then
    eval "$@"
  else
    ssh "$host" "$@"
  fi
}

# 複製文件到目標機器 (自動判斷本機/遠端)
function copy_to() {
  local src="$1" host="$2" dest="$3"
  if is_local "$host"; then
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
  else
    scp -r "$src" "${host}:${dest}"
  fi
}

# ====================== SSH 連線測試 ======================
function test_ssh_connections() {
  printStep "測試連線..."
  local failed=0
  for host in "${ALL_HOSTS[@]}"; do
    if is_local "$host"; then
      printInfo "  ✓ $host (本機)"
    elif ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" &>/dev/null; then
      printInfo "  ✓ $host 連線成功"
    else
      printError "  ✗ $host 連線失敗"
      failed=1
    fi
  done
  if [ $failed -eq 1 ]; then
    printError "部分機器 SSH 連線失敗，請檢查:"
    echo "  1. 是否已執行 ssh-copy-id user@host"
    echo "  2. 目標機器 SSH 服務是否正常"
    echo "  3. 防火牆是否開放 22 port"
    return 1
  fi
  printInfo "所有機器連線正常"
  return 0
}

if [ "$TEST_SSH" = true ]; then
  test_ssh_connections
  exit $?
fi

# ====================== 清理遠端節點 ======================
if [ "$CLEANUP" = true ]; then
  printStep "清理所有遠端節點..."
  echo ""

  for node in "${ORDERER_NODES[@]}"; do
    IFS=':' read -r idx ssh_target remote_dir <<< "$node"
    printInfo "清理 orderer${idx} @ ${ssh_target}..."
    run_on "$ssh_target" "
      cd ${remote_dir} 2>/dev/null && \
      docker compose -f ./docker/docker-compose-order.yaml down -v 2>/dev/null; \
      rm -rf ${remote_dir}
    " 2>/dev/null || printWarn "  orderer${idx} 清理時有警告 (可能目錄不存在)"
  done

  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    printInfo "清理 ${org_name} @ ${ssh_target}..."
    run_on "$ssh_target" "
      cd ${remote_dir} 2>/dev/null && \
      docker compose -f ./docker/docker-compose-${org_name}.yaml down -v 2>/dev/null; \
      docker compose -f ./docker/docker-compose-cli.yaml down -v 2>/dev/null; \
      docker rm -f \$(docker ps -aq --filter name=dev-peer) 2>/dev/null; \
      docker rmi -f \$(docker images -q --filter reference=dev-peer*) 2>/dev/null; \
      rm -rf ${remote_dir}
    " 2>/dev/null || printWarn "  ${org_name} 清理時有警告 (可能目錄不存在)"
  done

  printInfo "所有遠端節點已清理完成"
  exit 0
fi

# ====================== 測試連線 ======================
printStep "驗證 SSH 連線..."
if ! test_ssh_connections; then
  exit 1
fi
echo ""

# ====================== 生成配置 ======================
if [ "$DEPLOY_ONLY" = false ]; then
  printStep "生成網路配置文件..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  GEN_ARGS=(-o "$NUM_ORDERERS" -p "$NUM_ORGS" -c "$CHANNEL_NAME" -d "$GENERATED_DIR")
  if [ -n "$FABRIC_BIN_PATH" ]; then
    GEN_ARGS+=(-b "$FABRIC_BIN_PATH")
  fi
  if [ "$HAS_CHANNEL_CONFIG" = true ]; then
    GEN_ARGS+=(-C "$CONFIG_FILE")
  fi
  bash "${SCRIPT_DIR}/generate-network.sh" "${GEN_ARGS[@]}"
  echo ""

  # 解析工具路徑
  if [ -n "$FABRIC_BIN_PATH" ]; then
    FABRIC_BIN_PATH="$(cd "$FABRIC_BIN_PATH" 2>/dev/null && pwd)"
    CRYPTOGEN="${FABRIC_BIN_PATH}/cryptogen"
  else
    CRYPTOGEN="cryptogen"
  fi

  # 在本機生成加密材料和通道配置
  printStep "生成加密材料和通道配置..."
  pushd "$GENERATED_DIR" > /dev/null

  if [ ! -d "./organizations/crypto-config/ordererOrganizations" ]; then
    $CRYPTOGEN generate --config=./organizations/crypto-config.yaml --output=./organizations/crypto-config
    printInfo "加密材料生成完成"
  else
    printWarn "加密材料已存在，跳過"
  fi

  if [ ! -f "./channel-artifacts/genesis.block" ]; then
    export FABRIC_CFG_PATH=${PWD}
    bash ./configtx.sh
    printInfo "通道配置生成完成"
  else
    printWarn "通道配置已存在，跳過"
  fi

  # 生成 CCP
  pushd organizations > /dev/null
  bash ./ccp-generate.sh 2>/dev/null || true
  popd > /dev/null

  popd > /dev/null
  echo ""
fi

if [ "$DRY_RUN" = true ]; then
  printInfo "Dry-run 模式：配置已生成至 ${GENERATED_DIR}/，未執行部署"
  exit 0
fi

# 確認 generated-network 存在
if [ ! -d "$GENERATED_DIR" ]; then
  printError "找不到 ${GENERATED_DIR}/ 目錄，請先生成配置 (不要加 -d 選項)"
  exit 1
fi

# ====================== 部署到各機器 ======================
printStep "開始部署到各目標機器..."
echo ""

# --- 輔助函數：傳送共用文件 ---
function deploy_common_files() {
  local ssh_target=$1
  local remote_dir=$2
  local label=$3

  printInfo "  [${label}] 建立目錄..."
  run_on "$ssh_target" "mkdir -p ${remote_dir}/{docker,channel-artifacts,organizations,chaincode/go}"

  printInfo "  [${label}] 傳送加密材料..."
  copy_to "${GENERATED_DIR}/organizations/crypto-config" "$ssh_target" "${remote_dir}/organizations/crypto-config"

  printInfo "  [${label}] 傳送通道配置..."
  if is_local "$ssh_target"; then
    cp -r "${GENERATED_DIR}/channel-artifacts/"* "${remote_dir}/channel-artifacts/" 2>/dev/null || true
    cp "${GENERATED_DIR}/configtx.yaml" "${remote_dir}/"
  else
    scp -r "${GENERATED_DIR}/channel-artifacts/"* "${ssh_target}:${remote_dir}/channel-artifacts/" 2>/dev/null || true
    scp "${GENERATED_DIR}/configtx.yaml" "${ssh_target}:${remote_dir}/"
  fi
}

# --- 部署 Orderer 節點 ---
for node in "${ORDERER_NODES[@]}"; do
  IFS=':' read -r idx ssh_target remote_dir <<< "$node"
  LABEL="orderer${idx} @ ${ssh_target}"
  printInfo "部署 ${LABEL}..."

  deploy_common_files "$ssh_target" "$remote_dir" "$LABEL"

  # 生成該 orderer 專屬的 docker-compose (只包含自己)
  printInfo "  [${LABEL}] 生成單節點 orderer compose..."

  # 直接傳送完整的 orderer compose，遠端只啟動自己的 service
  copy_to "${GENERATED_DIR}/docker/docker-compose-order.yaml" "$ssh_target" "${remote_dir}/docker/docker-compose-order.yaml"

  # 生成遠端啟動腳本
  ORDERER_HOST_PORT=$(( 7050 + idx * 1000 ))
  ORDERER_ADMIN_PORT=$(( 7053 + idx * 1000 ))
  ORDERER_METRICS_PORT=$(( 7440 + idx * 1000 ))

  cat > "/tmp/node-start-orderer${idx}.sh" << NODEEOF
#!/bin/bash
set -e
echo "啟動 orderer${idx}..."

# 偵測 docker compose
if docker compose version &> /dev/null; then
  DC="docker compose"
elif command -v docker-compose &> /dev/null; then
  DC="docker-compose"
else
  echo "錯誤: 找不到 docker compose"; exit 1
fi

cd ${remote_dir}

# 建立 Docker 網路
docker network create fabric-center 2>/dev/null || true

# 僅啟動此 orderer
\$DC -f ./docker/docker-compose-order.yaml up -d orderer${idx}.com

echo "orderer${idx} 已啟動"
echo "  主要 Port: ${ORDERER_HOST_PORT}"
echo "  Admin Port: ${ORDERER_ADMIN_PORT}"
echo "  Metrics Port: ${ORDERER_METRICS_PORT}"
docker ps --filter "name=orderer${idx}.com" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
NODEEOF

  copy_to "/tmp/node-start-orderer${idx}.sh" "$ssh_target" "${remote_dir}/node-start.sh"
  run_on "$ssh_target" "chmod +x ${remote_dir}/node-start.sh"
  rm -f "/tmp/node-start-orderer${idx}.sh"

  # 生成遠端停止腳本
  cat > "/tmp/node-stop-orderer${idx}.sh" << NODEEOF
#!/bin/bash
echo "停止 orderer${idx}..."
cd ${remote_dir}
if docker compose version &> /dev/null; then
  docker compose -f ./docker/docker-compose-order.yaml down -v orderer${idx}.com 2>/dev/null || \
  docker compose -f ./docker/docker-compose-order.yaml stop orderer${idx}.com
else
  docker-compose -f ./docker/docker-compose-order.yaml stop orderer${idx}.com
fi
echo "orderer${idx} 已停止"
NODEEOF

  copy_to "/tmp/node-stop-orderer${idx}.sh" "$ssh_target" "${remote_dir}/node-stop.sh"
  run_on "$ssh_target" "chmod +x ${remote_dir}/node-stop.sh"
  rm -f "/tmp/node-stop-orderer${idx}.sh"

  printInfo "  [${LABEL}] 部署完成"
  echo ""
done

# --- 部署 Peer 節點 ---
PEER_DEPLOY_IDX=0
for node in "${PEER_NODES[@]}"; do
  IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
  LABEL="${org_name} @ ${ssh_target}"
  printInfo "部署 ${LABEL}..."

  deploy_common_files "$ssh_target" "$remote_dir" "$LABEL"

  # 傳送該 org 的 docker-compose
  printInfo "  [${LABEL}] 傳送 docker-compose 文件..."
  copy_to "${GENERATED_DIR}/docker/docker-compose-${org_name}.yaml" "$ssh_target" "${remote_dir}/docker/docker-compose-${org_name}.yaml"
  copy_to "${GENERATED_DIR}/docker/docker-compose-cli.yaml" "$ssh_target" "${remote_dir}/docker/docker-compose-cli.yaml"

  # 傳送 chaincode (如果有)
  if [ -d "${GENERATED_DIR}/chaincode/go" ] && [ "$(ls -A ${GENERATED_DIR}/chaincode/go 2>/dev/null)" ]; then
    printInfo "  [${LABEL}] 傳送 chaincode..."
    if is_local "$ssh_target"; then
      cp -r "${GENERATED_DIR}/chaincode/go/"* "${remote_dir}/chaincode/go/" 2>/dev/null || true
    else
      scp -r "${GENERATED_DIR}/chaincode/go/"* "${ssh_target}:${remote_dir}/chaincode/go/" 2>/dev/null || true
    fi
  fi

  # 生成遠端啟動腳本
  PEER_HOST_PORT=$(( 7051 + PEER_DEPLOY_IDX * 1000 ))
  CA_HOST_PORT=$(( 7054 + PEER_DEPLOY_IDX * 1000 ))
  COUCH_HOST_PORT=$(( 5984 + PEER_DEPLOY_IDX * 1000 ))

  cat > "/tmp/node-start-${org_name}.sh" << NODEEOF
#!/bin/bash
set -e
echo "啟動 ${org_name}..."

# 偵測 docker compose
if docker compose version &> /dev/null; then
  DC="docker compose"
elif command -v docker-compose &> /dev/null; then
  DC="docker-compose"
else
  echo "錯誤: 找不到 docker compose"; exit 1
fi

cd ${remote_dir}

# 建立 Docker 網路
docker network create fabric-center 2>/dev/null || true

# 啟動 Org 服務 (CA + CouchDB + Peer)
\$DC -f ./docker/docker-compose-${org_name}.yaml up -d

echo "等待 Peer 啟動..."
sleep 3

# 啟動 CLI
\$DC -f ./docker/docker-compose-cli.yaml up -d cli${PEER_DEPLOY_IDX}

echo ""
echo "${org_name} 已啟動"
echo "  Peer Port: ${PEER_HOST_PORT}"
echo "  CA Port: ${CA_HOST_PORT}"
echo "  CouchDB Port: ${COUCH_HOST_PORT}"
docker ps --filter "name=${org_name}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
docker ps --filter "name=cli${PEER_DEPLOY_IDX}" --format "table {{.Names}}\t{{.Status}}"
NODEEOF

  copy_to "/tmp/node-start-${org_name}.sh" "$ssh_target" "${remote_dir}/node-start.sh"
  run_on "$ssh_target" "chmod +x ${remote_dir}/node-start.sh"
  rm -f "/tmp/node-start-${org_name}.sh"

  # 生成遠端停止腳本
  cat > "/tmp/node-stop-${org_name}.sh" << NODEEOF
#!/bin/bash
echo "停止 ${org_name}..."
cd ${remote_dir}
if docker compose version &> /dev/null; then
  DC="docker compose"
else
  DC="docker-compose"
fi
\$DC -f ./docker/docker-compose-cli.yaml stop cli${PEER_DEPLOY_IDX} 2>/dev/null || true
\$DC -f ./docker/docker-compose-${org_name}.yaml down -v
echo "${org_name} 已停止"
NODEEOF

  copy_to "/tmp/node-stop-${org_name}.sh" "$ssh_target" "${remote_dir}/node-stop.sh"
  run_on "$ssh_target" "chmod +x ${remote_dir}/node-stop.sh"
  rm -f "/tmp/node-stop-${org_name}.sh"

  printInfo "  [${LABEL}] 部署完成"
  PEER_DEPLOY_IDX=$((PEER_DEPLOY_IDX + 1))
  echo ""
done

printInfo "=========================================="
printInfo " 所有節點部署完成"
printInfo "=========================================="

# ====================== 自動啟動 ======================
if [ "$AUTO_START" = true ]; then
  echo ""
  printStep "自動啟動所有節點..."
  echo ""

  # 先啟動所有 orderer
  printInfo "啟動 Orderer 節點..."
  for node in "${ORDERER_NODES[@]}"; do
    IFS=':' read -r idx ssh_target remote_dir <<< "$node"
    printInfo "  啟動 orderer${idx} @ ${ssh_target}..."
    run_on "$ssh_target" "bash ${remote_dir}/node-start.sh" 2>&1 | sed 's/^/    /'
    echo ""
  done

  printInfo "等待 Orderer 叢集就緒..."
  sleep 5

  # 啟動所有 peer
  printInfo "啟動 Peer 節點..."
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    printInfo "  啟動 ${org_name} @ ${ssh_target}..."
    run_on "$ssh_target" "bash ${remote_dir}/node-start.sh" 2>&1 | sed 's/^/    /'
    echo ""
  done

  sleep 3

  # 在第一個 peer 機器上建立 channel 並讓所有 peer 加入
  printInfo "建立 Channel: ${CHANNEL_NAME}..."
  FIRST_PEER_NODE="${PEER_NODES[0]}"
  IFS=':' read -r first_idx first_ssh first_dir <<< "$FIRST_PEER_NODE"

  FIRST_ORDERER_NODE="${ORDERER_NODES[0]}"
  IFS=':' read -r ord_idx ord_ssh ord_dir <<< "$FIRST_ORDERER_NODE"
  # 取得 orderer0 的 IP (從 ssh target 中提取)
  ORDERER0_HOST=$(echo "$ord_ssh" | cut -d'@' -f2)
  if is_local "$ord_ssh"; then ORDERER0_HOST="localhost"; fi
  ORDERER0_PORT=$(( 7050 + ord_idx * 1000 ))

  # 建立 channel
  run_on "$first_ssh" "
    docker exec cli0 peer channel create \
      -o ${ORDERER0_HOST}:${ORDERER0_PORT} \
      --ordererTLSHostnameOverride orderer${ord_idx}.com \
      -c ${CHANNEL_NAME} \
      -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.tx \
      --outputBlock /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.block \
      --tls \
      --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer${ord_idx}.com/msp/tlscacerts/tlsca.com-cert.pem
  " 2>&1 | sed 's/^/    /'

  sleep 2

  # 從第一個 peer 機器取回 channel block，分發給其他 peer
  printInfo "分發 Channel Block 到各 Peer..."
  BLOCK_CONTAINER_PATH="/opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}.block"

  # 先從第一個 peer 的 cli 容器中複製 block 出來
  run_on "$first_ssh" "docker cp cli0:${BLOCK_CONTAINER_PATH} /tmp/${CHANNEL_NAME}.block"
  if is_local "$first_ssh"; then
    cp "/tmp/${CHANNEL_NAME}.block" "/tmp/${CHANNEL_NAME}.block" 2>/dev/null || true
  else
    scp "${first_ssh}:/tmp/${CHANNEL_NAME}.block" "/tmp/${CHANNEL_NAME}.block"
  fi

  # 各 peer 加入 channel
  PEER_JOIN_IDX=0
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    printInfo "  ${org_name} 加入 Channel..."

    # 將 block 傳到該機器並複製進 cli 容器
    if is_local "$ssh_target"; then
      docker cp "/tmp/${CHANNEL_NAME}.block" "cli${PEER_JOIN_IDX}:${BLOCK_CONTAINER_PATH}"
    else
      scp "/tmp/${CHANNEL_NAME}.block" "${ssh_target}:/tmp/${CHANNEL_NAME}.block"
      run_on "$ssh_target" "docker cp /tmp/${CHANNEL_NAME}.block cli${PEER_JOIN_IDX}:${BLOCK_CONTAINER_PATH}"
    fi

    run_on "$ssh_target" "
      docker exec cli${PEER_JOIN_IDX} peer channel join \
        -b ${BLOCK_CONTAINER_PATH}
    " 2>&1 | sed 's/^/    /'
    PEER_JOIN_IDX=$((PEER_JOIN_IDX + 1))
    sleep 1
  done

  sleep 2

  # 更新錨節點
  printInfo "更新錨節點..."
  PEER_JOIN_IDX=0
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    ORG_CAP="$(echo ${org_name:0:1} | tr '[:lower:]' '[:upper:]')${org_name:1}"
    printInfo "  更新 ${org_name} 錨節點..."
    run_on "$ssh_target" "
      docker exec cli${PEER_JOIN_IDX} peer channel update \
        -o ${ORDERER0_HOST}:${ORDERER0_PORT} \
        --ordererTLSHostnameOverride orderer${ord_idx}.com \
        -c ${CHANNEL_NAME} \
        -f /opt/gopath/src/github.com/hyperledger/fabric/peer/channel-artifacts/${CHANNEL_NAME}_${ORG_CAP}MSPanchors.tx \
        --tls \
        --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer${ord_idx}.com/msp/tlscacerts/tlsca.com-cert.pem
    " 2>&1 | sed 's/^/    /'
    PEER_JOIN_IDX=$((PEER_JOIN_IDX + 1))
    sleep 1
  done

  rm -f "/tmp/${CHANNEL_NAME}.block"

  echo ""
  printInfo "=========================================="
  printInfo " 網路啟動完成!"
  printInfo "=========================================="
else
  echo ""
  printInfo "部署完成，請依序在各機器上執行啟動:"
  echo ""
  echo "  1. 先啟動所有 Orderer:"
  for node in "${ORDERER_NODES[@]}"; do
    IFS=':' read -r idx ssh_target remote_dir <<< "$node"
    echo "     ssh ${ssh_target} 'bash ${remote_dir}/node-start.sh'"
  done
  echo ""
  echo "  2. 再啟動所有 Peer:"
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    echo "     ssh ${ssh_target} 'bash ${remote_dir}/node-start.sh'  # ${org_name}"
  done
  echo ""
  echo "  3. 建立 Channel 並加入 (在任一 peer 機器上操作)"
  echo ""
  echo "  停止節點:"
  for node in "${PEER_NODES[@]}"; do
    IFS=':' read -r org_name ssh_target remote_dir <<< "$node"
    echo "     ssh ${ssh_target} 'bash ${remote_dir}/node-stop.sh'   # ${org_name}"
  done
  echo ""
fi
