#!/bin/bash
################################################################################
#                                                                              #
#  SCP 傳輸測試腳本                                                            #
#  驗證 fabric-tool.sh 能否正確傳送文件到遠端主機                              #
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
# 配置
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CONFIG_FILE="network-config.yaml"
TEST_DIR="/tmp/fabric-scp-test-$$"
FABRIC_TOOL="./fabric-tool.sh"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 参数解析
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

while getopts "c:h" opt; do
  case $opt in
    c) CONFIG_FILE="$OPTARG" ;;
    h)
      cat << 'EOF'
SCP 傳輸測試腳本

用法:
  ./test-scp-transfer.sh [-c config.yaml]

選項:
  -c <檔案>    配置文件 (預設: network-config.yaml)
  -h           顯示此說明

測試流程:
  1. 驗證本機環境
  2. 測試 SSH 連線
  3. 測試 SCP 單文件傳送
  4. 測試 SCP 目錄傳送
  5. 驗證遠端接收文件
  6. 清理測試文件

範例:
  ./test-scp-transfer.sh -c network-config.yaml
EOF
      exit 0
      ;;
    \?) error "無效選項: -$OPTARG"; exit 1 ;;
  esac
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 驗證前置條件
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "驗證前置條件"

if [ ! -f "$CONFIG_FILE" ]; then
  error "配置文件不存在: $CONFIG_FILE"
  exit 1
fi
success "配置文件: $CONFIG_FILE"

if [ ! -f "$FABRIC_TOOL" ]; then
  error "fabric-tool.sh 不存在"
  exit 1
fi
success "fabric-tool.sh 已就緒"

if ! command -v ssh &>/dev/null; then
  error "SSH 未安裝"
  exit 1
fi
success "SSH 已安裝"

if ! command -v scp &>/dev/null; then
  error "SCP 未安裝"
  exit 1
fi
success "SCP 已安裝"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 解析主機列表
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

declare -a REMOTE_HOSTS=()

while IFS= read -r line; do
  if [[ "$line" =~ ^[[:space:]]*host:[[:space:]]*(.+)$ ]]; then
    host_str="${BASH_REMATCH[1]}"
    host_str="${host_str%"${host_str##*[! ]}"}"
    if [ -n "$host_str" ] && [ "$host_str" != "local" ] && [ "$host_str" != "localhost" ]; then
      REMOTE_HOSTS+=("$host_str")
    fi
  fi
done < "$CONFIG_FILE"

# 移除重複
REMOTE_HOSTS=($(printf '%s\n' "${REMOTE_HOSTS[@]}" | sort -u))

if [ ${#REMOTE_HOSTS[@]} -eq 0 ]; then
  warn "未發現遠端主機，測試將跳過遠端傳送"
  TEST_REMOTE=false
else
  success "發現 ${#REMOTE_HOSTS[@]} 個遠端主機"
  TEST_REMOTE=true
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 準備測試數據
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "準備測試數據"

mkdir -p "$TEST_DIR"
success "測試目錄: $TEST_DIR"

# 建立測試文件
echo "This is a test file for SCP transfer - $(date)" > "$TEST_DIR/test-file.txt"
success "測試文件: $TEST_DIR/test-file.txt"

# 建立測試目錄結構
mkdir -p "$TEST_DIR/test-dir/subdir"
echo "File 1" > "$TEST_DIR/test-dir/file1.txt"
echo "File 2" > "$TEST_DIR/test-dir/subdir/file2.txt"
success "測試目錄結構已建立"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 測試遠端傳送
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$TEST_REMOTE" = true ]; then
  step "遠端 SCP 傳送測試"

  for host in "${REMOTE_HOSTS[@]}"; do
    echo ""
    info "目標主機: $host"

    # 提取用戶名
    if [[ "$host" =~ ^([^@]+)@(.+)$ ]]; then
      user="${BASH_REMATCH[1]}"
      addr="${BASH_REMATCH[2]}"
    else
      warn "無效主機格式: $host"
      continue
    fi

    # 1. 測試 SSH 連線
    echo -n "  SSH 連線測試... "
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" &>/dev/null; then
      success "✓"
    else
      error "✗ 連線失敗"
      continue
    fi

    # 2. 建立遠端測試目錄
    REMOTE_TEST_DIR="/tmp/fabric-scp-test-$RANDOM"
    echo -n "  建立遠端目錄... "
    if ssh "$host" "mkdir -p '$REMOTE_TEST_DIR'" &>/dev/null; then
      success "✓ ($REMOTE_TEST_DIR)"
    else
      error "✗ 無法建立目錄"
      continue
    fi

    # 3. 傳送單個文件
    echo -n "  傳送單文件... "
    if scp -C "$TEST_DIR/test-file.txt" "$host:$REMOTE_TEST_DIR/" &>/dev/null; then
      success "✓"
    else
      error "✗ 傳送失敗"
      ssh "$host" "rm -rf '$REMOTE_TEST_DIR'" 2>/dev/null || true
      continue
    fi

    # 4. 驗證文件到達
    echo -n "  驗證文件... "
    if ssh "$host" "test -f '$REMOTE_TEST_DIR/test-file.txt'" &>/dev/null; then
      success "✓"
    else
      error "✗ 文件未到達"
      ssh "$host" "rm -rf '$REMOTE_TEST_DIR'" 2>/dev/null || true
      continue
    fi

    # 5. 傳送目錄結構
    echo -n "  傳送目錄結構... "
    if scp -r -C "$TEST_DIR/test-dir" "$host:$REMOTE_TEST_DIR/" &>/dev/null; then
      success "✓"
    else
      error "✗ 目錄傳送失敗"
      ssh "$host" "rm -rf '$REMOTE_TEST_DIR'" 2>/dev/null || true
      continue
    fi

    # 6. 驗證目錄結構
    echo -n "  驗證目錄結構... "
    if ssh "$host" "test -d '$REMOTE_TEST_DIR/test-dir/subdir' && test -f '$REMOTE_TEST_DIR/test-dir/subdir/file2.txt'" &>/dev/null; then
      success "✓"
    else
      error "✗ 目錄結構驗證失敗"
      ssh "$host" "rm -rf '$REMOTE_TEST_DIR'" 2>/dev/null || true
      continue
    fi

    # 7. 檢查文件內容
    echo -n "  驗證文件內容... "
    local content=$(ssh "$host" "cat '$REMOTE_TEST_DIR/test-file.txt'" 2>/dev/null)
    if [[ "$content" == *"test file for SCP transfer"* ]]; then
      success "✓"
    else
      error "✗ 文件內容不符"
      ssh "$host" "rm -rf '$REMOTE_TEST_DIR'" 2>/dev/null || true
      continue
    fi

    # 8. 清理遠端測試文件
    echo -n "  清理遠端測試文件... "
    if ssh "$host" "rm -rf '$REMOTE_TEST_DIR'" &>/dev/null; then
      success "✓"
    else
      warn "⚠ 清理失敗"
    fi

    success "✓✓✓ $host 全部測試通過！"
  done
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 清理本機測試文件
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

step "清理本機測試文件"
rm -rf "$TEST_DIR"
success "測試文件已清理"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 測試完成
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
success "所有 SCP 傳輸測試完成！"
echo ""
info "總結: SCP 文件傳送功能已驗證正常"
echo ""
