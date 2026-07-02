#!/bin/bash
################################################################################
#                                                                              #
#  Hyperledger Fabric 多機部署腳本                                             #
#  讀取配置文件，自動生成網路配置並透過 SCP/SSH 分發到各目標機器               #
#                                                                              #
#  功能：                                                                      #
#    • 解析部署配置（YAML 格式）                                              #
#    • 本機生成完整的 Fabric 網路配置                                          #
#    • 將文件分發到各遠端主機                                                  #
#    • 在遠端主機上啟動或停止節點                                              #
#    • 支持多機 channel 建立和自動化部署                                       #
#                                                                              #
################################################################################

set -e

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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 顏色定義
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 輸出函數
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

error() {
  echo -e "${RED}✗${NC} $*" >&2
}

warn() {
  echo -e "${YELLOW}⚠${NC} $*" >&2
}

success() {
  echo -e "${GREEN}✓${NC} $*"
}

info() {
  echo -e "${BLUE}ℹ${NC} $*"
}

step() {
  echo -e "${CYAN}→${NC} ${BOLD}$*${NC}"
}

debug() {
  [ "$DEBUG" = "1" ] && echo -e "${DIM}[DEBUG]${NC} $*"
}

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
  debug "copy_to: src=$src host=$host dest=$dest"

  if [ ! -e "$src" ]; then
    warn "源文件/目錄不存在: $src (跳過)"
    return 0
  fi

  if is_local "$host"; then
    mkdir -p "$(dirname "$dest")"
    if [ -d "$src" ]; then
      cp -r "$src" "$dest" 2>/dev/null || true
    else
      cp "$src" "$dest" 2>/dev/null || true
    fi
    debug "✓ 已複製 (本機): $src → $dest"
  else
    if [ -d "$src" ]; then
      scp -r "$src" "${host}:${dest}" 2>/dev/null || {
        warn "無法複製目錄: $src → $host:$dest"
        return 1
      }
    else
      scp "$src" "${host}:${dest}" 2>/dev/null || {
        warn "無法複製文件: $src → $host:$dest"
        return 1
      }
    fi
    debug "✓ 已複製 (遠端): $src → $host:$dest"
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

  # 建立遠端目錄結構
  debug "為 $label 建立目錄結構"
  run_on "$ssh_target" "mkdir -p ${remote_dir}/{docker,channel-artifacts,organizations,chaincode/go}"

  # 傳送加密材料
  info "  [$label] 傳送加密材料..."
  copy_to "${GENERATED_DIR}/organizations/crypto-config" "$ssh_target" "${remote_dir}/organizations/crypto-config"

  # 傳送通道配置
  info "  [$label] 傳送通道配置..."
  copy_to "${GENERATED_DIR}/channel-artifacts" "$ssh_target" "${remote_dir}/channel-artifacts"
  copy_to "${GENERATED_DIR}/configtx.yaml" "$ssh_target" "${remote_dir}/configtx.yaml"
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
