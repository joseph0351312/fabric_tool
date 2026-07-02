#!/bin/bash
################################################################################
#                                                                              #
#  Hyperledger Fabric Network Tool                                            #
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

  # 檢查 Docker Compose
  if ! command -v docker-compose &> /dev/null; then
    error "未安裝 Docker Compose。請先安裝: https://docs.docker.com/compose/install/"
    ((missing++))
  else
    info "Docker Compose: $(docker-compose --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
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

# 檢查依賴庫和腳本
check_dependencies() {
  local lib_file="${SCRIPT_DIR}/lib/generate-network.sh"
  local deploy_file="${SCRIPT_DIR}/lib/deploy.sh"

  if [ ! -f "$lib_file" ]; then
    error "找不到生成腳本: $lib_file"
    echo -e "${DIM}確保你在專案根目錄運行此工具${NC}"
    return 1
  fi

  if [ ! -f "$deploy_file" ]; then
    error "找不到部署腳本: $deploy_file"
    echo -e "${DIM}確保你在專案根目錄運行此工具${NC}"
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

  if command -v docker-compose &> /dev/null; then
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

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 主程序入口
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
  local command="${1:-help}"

  # 移除第一個參數（命令）
  shift 2>/dev/null || true

  case "$command" in
    generate)
      print_banner

      # 檢查依賴
      if ! check_dependencies; then
        return 1
      fi

      # 執行生成
      bash "${SCRIPT_DIR}/lib/generate-network.sh" "$@"

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

      # 檢查依賴
      if ! check_dependencies; then
        return 1
      fi

      # 執行部署
      bash "${SCRIPT_DIR}/lib/deploy.sh" "$@"

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
