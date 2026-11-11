#!/bin/bash
################################################################################
#                                                                              #
#  Fabric 部署診斷工具                                                         #
#  用於診斷 SSH/SCP 連線和文件傳送問題                                          #
#                                                                              #
################################################################################

set -e

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

error() { echo -e "${RED}✗${NC} $*" >&2; }
warn() { echo -e "${YELLOW}⚠${NC} $*" >&2; }
success() { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${BLUE}ℹ${NC} $*"; }
step() { echo -e "\n${CYAN}→${NC} ${BOLD}$*${NC}"; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 參數解析
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONFIG_FILE="network-config.yaml"

while getopts "f:h" opt; do
  case $opt in
    f) CONFIG_FILE="$OPTARG" ;;
    h)
      cat << 'EOF'
Fabric 部署診斷工具

用法:
  ./diagnose-deploy.sh [-f config.yaml]

選項:
  -f <檔案>    指定配置文件 (預設: network-config.yaml)
  -h           顯示此說明

範例:
  ./diagnose-deploy.sh -f network-config.yaml
EOF
      exit 0
      ;;
    \?) error "無效選項: -$OPTARG"; exit 1 ;;
  esac
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 檢查配置文件
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ ! -f "$CONFIG_FILE" ]; then
  error "找不到配置文件: $CONFIG_FILE"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 解析主機列表
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

declare -a HOSTS=()

# 簡單的配置解析 (提取 host: 行)
while IFS= read -r line; do
  if [[ "$line" =~ ^[[:space:]]*host:[[:space:]]*(.+)$ ]]; then
    host_str="${BASH_REMATCH[1]}"
    # 移除末尾空格
    host_str="${host_str%"${host_str##*[! ]}"}"
    [ -n "$host_str" ] && [ "$host_str" != "local" ] && [ "$host_str" != "localhost" ] && HOSTS+=("$host_str")
  fi
done < "$CONFIG_FILE"

# 移除重複
HOSTS=($(printf '%s\n' "${HOSTS[@]}" | sort -u))

if [ ${#HOSTS[@]} -eq 0 ]; then
  warn "配置文件中沒有發現遠端主機"
  exit 0
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 開始診斷
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
step "Fabric 部署診斷"
echo ""
info "配置文件: $CONFIG_FILE"
info "發現 ${#HOSTS[@]} 個遠端主機"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 檢查本機環境
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "本機環境檢查"

# SSH 客戶端
if command -v ssh &>/dev/null; then
  SSH_VERSION=$(ssh -V 2>&1 | head -1)
  success "SSH: $SSH_VERSION"
else
  error "SSH 未安裝"
  exit 1
fi

# SCP 工具
if command -v scp &>/dev/null; then
  success "SCP: 已安裝"
else
  error "SCP 未安裝 (通常隨 SSH 一起安裝)"
  exit 1
fi

# SSH 配置
if [ -f ~/.ssh/config ]; then
  success "~/.ssh/config: 存在"
else
  warn "~/.ssh/config: 不存在 (非必需)"
fi

# SSH 密鑰
if [ -f ~/.ssh/id_rsa ] || [ -f ~/.ssh/id_ed25519 ]; then
  success "SSH 私鑰: 存在"
else
  warn "SSH 私鑰: 未找到 (需要 ~/.ssh/id_rsa 或 ~/.ssh/id_ed25519)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. 檢查遠端主機連線
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "遠端主機連線診斷"
echo ""

for host in "${HOSTS[@]}"; do
  echo "測試: $host"

  # 提取用戶名和地址
  if [[ "$host" =~ ^([^@]+)@(.+)$ ]]; then
    user="${BASH_REMATCH[1]}"
    addr="${BASH_REMATCH[2]}"
  else
    warn "  無效的主機格式: $host (應為 user@host)"
    continue
  fi

  # 1. 測試 SSH 連線
  echo -n "  SSH 連線... "
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" &>/dev/null; then
    success "✓ 連線正常"
  else
    error "✗ 連線失敗"
    echo "    解決方案:"
    echo "      1. 確認目標主機是否在線: ping $addr"
    echo "      2. 確認 SSH 服務運行: ssh $host 'systemctl status ssh'"
    echo "      3. 配置無密碼登入: ssh-copy-id $host"
    continue
  fi

  # 2. 檢查遠端目錄
  echo -n "  遠端 /home/$user/... "
  if ssh "$host" "test -d /home/$user" &>/dev/null; then
    success "✓ 目錄存在"
  else
    error "✗ 目錄不存在"
    echo "    提示: 檢查用戶名是否正確"
    continue
  fi

  # 3. 檢查 Docker
  echo -n "  遠端 Docker... "
  if ssh "$host" "docker ps &>/dev/null" &>/dev/null; then
    success "✓ 可用"
  else
    warn "⚠ 無法訪問 (可能需要 sudo)"
    echo "    檢查: ssh $host 'sudo docker ps'"
  fi

  # 4. 測試 SCP 傳送
  echo -n "  SCP 傳送測試... "

  # 建立臨時文件
  TEST_FILE="/tmp/test-scp-$RANDOM.txt"
  echo "test-scp-$(date +%s)" > "$TEST_FILE"

  # 測試 SCP
  if scp -C "$TEST_FILE" "$host:/tmp/" &>/dev/null; then
    success "✓ 傳送成功"

    # 清理
    ssh "$host" "rm -f /tmp/$(basename $TEST_FILE)" 2>/dev/null || true
  else
    error "✗ 傳送失敗"
    echo "    可能的原因:"
    echo "      • SSH 連線問題 (已驗證)"
    echo "      • 遠端磁盤空間不足: ssh $host 'df -h'"
    echo "      • 遠端 /tmp 無寫入權限: ssh $host 'touch /tmp/test-write.txt'"
  fi

  rm -f "$TEST_FILE"
  echo ""
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. 測試部署目錄結構
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "部署目錄結構診斷"
echo ""

for host in "${HOSTS[@]}"; do
  echo "測試: $host"

  if [[ "$host" =~ ^([^@]+)@(.+)$ ]]; then
    user="${BASH_REMATCH[1]}"
  else
    continue
  fi

  # 假設部署目錄 (根據機器數量)
  DEPLOY_DIR="/home/$user/3_orderer_4_peer"

  echo -n "  建立測試目錄... "
  if ssh "$host" "mkdir -p '$DEPLOY_DIR/test' && echo 'ok' > '$DEPLOY_DIR/test/write-test.txt' && rm -rf '$DEPLOY_DIR/test'" &>/dev/null; then
    success "✓ 可讀寫"
  else
    error "✗ 無法建立目錄"
    echo "    檢查:"
    echo "      • 磁盤空間: ssh $host 'df -h /home/$user'"
    echo "      • 權限: ssh $host 'ls -ld /home/$user'"
  fi

  echo ""
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 完成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
step "診斷完成"
echo ""
success "如果上述檢查都通過，可以執行部署："
echo "  ./fabric-tool.sh deploy -f $CONFIG_FILE -s"
echo ""
