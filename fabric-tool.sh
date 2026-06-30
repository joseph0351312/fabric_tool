#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Hyperledger Fabric Network Tool                            ║
# ║  一鍵生成、部署、管理 Fabric 網路                              ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# ─── 常數 ───────────────────────────────────────────────────────
readonly TOOL_VERSION="1.0.0"
readonly TOOL_NAME="Hyperledger Fabric Network Tool"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 顏色 ───────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ─── 函數 ───────────────────────────────────────────────────────

print_banner() {
  echo ""
  echo -e "${CYAN}  ╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}  ║${NC}${BOLD}   Hyperledger Fabric Network Tool  ${DIM}v${TOOL_VERSION}${NC}${CYAN}    ║${NC}"
  echo -e "${CYAN}  ╚═══════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_usage() {
  echo -e "${BOLD}用法:${NC}  ./fabric-tool.sh <命令> [選項]"
  echo ""
  echo -e "${BOLD}命令:${NC}"
  echo -e "  ${GREEN}generate${NC}    根據配置生成完整的 Fabric 網路文件"
  echo -e "  ${GREEN}deploy${NC}      多機部署 (透過 SSH 分發並啟動)"
  echo -e "  ${GREEN}version${NC}     顯示版本資訊"
  echo -e "  ${GREEN}help${NC}        顯示此說明"
  echo ""
  echo -e "${BOLD}generate 選項:${NC}"
  echo -e "  -C <檔案>    網路配置文件 (定義組織名稱與 channel 成員)"
  echo -e "  -o <數量>    Orderer 節點數量 ${DIM}(預設: 5, 建議奇數)${NC}"
  echo -e "  -p <數量>    Peer 組織數量 ${DIM}(預設: 5, 無 -C 時使用)${NC}"
  echo -e "  -c <名稱>    Channel 名稱 ${DIM}(預設: mychannel, 無 -C 時使用)${NC}"
  echo -e "  -d <目錄>    輸出目錄 ${DIM}(預設: generated-network)${NC}"
  echo -e "  -b <路徑>    Fabric 工具路徑 ${DIM}(cryptogen/configtxgen 所在目錄)${NC}"
  echo ""
  echo -e "${BOLD}deploy 選項:${NC}"
  echo -e "  -f <檔案>    部署配置文件 ${DIM}(預設: network-config.yaml)${NC}"
  echo    "  -b <路徑>    Fabric 工具路徑"
  echo    "  -g           僅生成配置，不部署 (dry-run)"
  echo    "  -d           僅部署，跳過生成"
  echo    "  -s           部署後自動啟動"
  echo    "  -c           清理所有遠端節點"
  echo    "  -t           測試 SSH 連線"
  echo ""
  echo -e "${BOLD}範例:${NC}"
  echo -e "  ${DIM}# 使用 YAML 配置 (推薦)${NC}"
  echo    "  ./fabric-tool.sh generate -o 3 -C network-config.yaml"
  echo ""
  echo -e "  ${DIM}# 快速生成 (自動命名 org0~org3)${NC}"
  echo    "  ./fabric-tool.sh generate -o 3 -p 4 -c mychannel"
  echo ""
  echo -e "  ${DIM}# 多機部署 + 自動啟動${NC}"
  echo    "  ./fabric-tool.sh deploy -f network-config.yaml -s"
  echo ""
  echo -e "${BOLD}生成後使用:${NC}"
  echo    "  cd generated-network"
  echo -e "  ./start.sh set_channel       ${DIM}# 啟動 + 建立所有 channel${NC}"
  echo -e "  ./start.sh set_chaincode     ${DIM}# 啟動 + channel + 部署 chaincode${NC}"
  echo -e "  ./start.sh up                ${DIM}# 僅啟動容器${NC}"
  echo -e "  ./start.sh restart           ${DIM}# 重啟容器${NC}"
  echo -e "  bash stop.sh                 ${DIM}# 停止並清理${NC}"
  echo -e "  bash docker_ps.sh            ${DIM}# 查看容器狀態${NC}"
  echo ""
}

# ─── 主邏輯 ──────────────────────────────────────────────────────

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
  generate)
    print_banner
    bash "${SCRIPT_DIR}/lib/generate-network.sh" "$@"
    ;;

  deploy)
    print_banner
    bash "${SCRIPT_DIR}/lib/deploy.sh" "$@"
    ;;

  version)
    echo -e "${BOLD}${TOOL_NAME}${NC} v${TOOL_VERSION}"
    echo -e "  Fabric Image:  ${GREEN}2.5${NC}"
    echo -e "  Fabric CA:     ${GREEN}1.5.5${NC}"
    ;;

  help|--help|-h)
    print_banner
    print_usage
    ;;

  *)
    echo -e "${RED}✗${NC} 未知命令: ${BOLD}${COMMAND}${NC}"
    echo ""
    print_usage
    exit 1
    ;;
esac
