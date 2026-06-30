#!/bin/bash
#
# Hyperledger Fabric 統整管理腳本
# 整合所有操作：生成配置、本機部署、多機部署、啟停管理
#
# 用法: ./fabric.sh <命令> [選項]
#
# 命令:
#   generate    生成網路配置文件
#   deploy      多機部署 (讀取配置文件，scp/ssh 分發)
#   start       本機啟動網路
#   stop        本機停止網路
#   restart     本機重啟網路
#   status      查看容器狀態
#   clean       清理所有容器和生成的文件
#   help        顯示此說明
#
# 範例:
#   ./fabric.sh generate -o 3 -p 4 -c mychannel
#   ./fabric.sh generate -o 3 -p 4 -c mychannel -d /opt/my-network
#   ./fabric.sh deploy -f tools/network-config.yaml -s
#   ./fabric.sh start
#   ./fabric.sh stop
#   ./fabric.sh status
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"

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

# ====================== Help ======================
function show_help() {
  cat << 'HELPEOF'

  ╔══════════════════════════════════════════════════════╗
  ║     Hyperledger Fabric 統整管理工具                  ║
  ╚══════════════════════════════════════════════════════╝

  用法: ./fabric.sh <命令> [選項]

  命令:
    generate    生成網路配置文件 (configtx, docker-compose, crypto 等)
    deploy      多機部署 (讀取配置文件，透過 scp/ssh 分發到各機器)
    start       本機一鍵啟動網路 (含建立 channel)
    stop        本機停止網路並清理
    restart     本機重啟所有容器
    status      查看所有容器狀態
    clean       徹底清理 (容器 + 加密材料 + 通道配置)
    help        顯示此說明

  ─────────────────────────────────────────────────────
  generate 選項:
    -o <數量>    Orderer 節點數量 (預設: 5)
    -p <數量>    Peer 組織數量 (預設: 5)
    -c <名稱>    Channel 名稱 (預設: mychannel)
    -d <目錄>    輸出目錄，支援絕對/相對路徑 (預設: generated-network)

  ─────────────────────────────────────────────────────
  deploy 選項:
    -f <文件>    部署配置文件 (預設: tools/network-config.yaml)
    -g          僅生成，不部署 (dry-run)
    -d          僅部署，跳過生成
    -s          部署後自動啟動
    -c          清理所有遠端節點
    -t          測試 SSH 連線

  ─────────────────────────────────────────────────────
  使用範例:

    # 生成 3 orderer + 4 peer 的網路配置
    ./fabric.sh generate -o 3 -p 4 -c mychannel

    # 生成配置到指定目錄
    ./fabric.sh generate -o 3 -p 2 -c testchannel -d /opt/fabric-network

    # 多機部署 (自動啟動)
    ./fabric.sh deploy -f tools/network-config.yaml -s

    # 測試遠端 SSH 連線
    ./fabric.sh deploy -f tools/network-config.yaml -t

    # 本機啟動 (需先 generate)
    ./fabric.sh start

    # 查看狀態
    ./fabric.sh status

    # 停止並清理
    ./fabric.sh stop

    # 徹底清理
    ./fabric.sh clean

  ─────────────────────────────────────────────────────
  目錄結構:
    ./fabric.sh                        # 本腳本 (統整入口)
    ./tools/
    ├── generate-network.sh            # 網路配置生成器
    ├── deploy.sh                      # 多機部署腳本
    └── network-config.yaml            # 多機部署配置範例
    ./generated-network/               # 生成的配置 (預設輸出目錄)
    └── ...

HELPEOF
}

# ====================== generate ======================
function cmd_generate() {
  if [ ! -f "${TOOLS_DIR}/generate-network.sh" ]; then
    printError "找不到 ${TOOLS_DIR}/generate-network.sh"
    exit 1
  fi
  bash "${TOOLS_DIR}/generate-network.sh" "$@"
}

# ====================== deploy ======================
function cmd_deploy() {
  if [ ! -f "${TOOLS_DIR}/deploy.sh" ]; then
    printError "找不到 ${TOOLS_DIR}/deploy.sh"
    exit 1
  fi
  bash "${TOOLS_DIR}/deploy.sh" "$@"
}

# ====================== start ======================
function cmd_start() {
  # 找到 generated-network 目錄
  local work_dir="generated-network"

  # 允許 -d 指定工作目錄
  while getopts "d:" opt; do
    case $opt in
      d) work_dir=$OPTARG ;;
    esac
  done

  if [ ! -d "$work_dir" ]; then
    printError "找不到工作目錄: $work_dir"
    printInfo "請先執行: ./fabric.sh generate -o <N> -p <N> -c <channel>"
    exit 1
  fi

  if [ ! -f "$work_dir/start.sh" ]; then
    printError "找不到 $work_dir/start.sh"
    exit 1
  fi

  printStep "啟動網路 (工作目錄: $work_dir)..."
  pushd "$work_dir" > /dev/null
  bash ./start.sh
  popd > /dev/null
}

# ====================== stop ======================
function cmd_stop() {
  local work_dir="generated-network"

  while getopts "d:" opt; do
    case $opt in
      d) work_dir=$OPTARG ;;
    esac
  done

  if [ ! -d "$work_dir" ]; then
    printError "找不到工作目錄: $work_dir"
    exit 1
  fi

  if [ ! -f "$work_dir/stop.sh" ]; then
    printError "找不到 $work_dir/stop.sh"
    exit 1
  fi

  printStep "停止網路 (工作目錄: $work_dir)..."
  pushd "$work_dir" > /dev/null
  bash ./stop.sh
  popd > /dev/null
}

# ====================== restart ======================
function cmd_restart() {
  local work_dir="generated-network"

  while getopts "d:" opt; do
    case $opt in
      d) work_dir=$OPTARG ;;
    esac
  done

  if [ ! -d "$work_dir" ]; then
    printError "找不到工作目錄: $work_dir"
    exit 1
  fi

  if [ ! -f "$work_dir/restart.sh" ]; then
    printError "找不到 $work_dir/restart.sh"
    exit 1
  fi

  printStep "重啟網路 (工作目錄: $work_dir)..."
  pushd "$work_dir" > /dev/null
  bash ./restart.sh
  popd > /dev/null
}

# ====================== status ======================
function cmd_status() {
  local work_dir="generated-network"

  while getopts "d:" opt; do
    case $opt in
      d) work_dir=$OPTARG ;;
    esac
  done

  if [ -f "$work_dir/docker_ps.sh" ]; then
    pushd "$work_dir" > /dev/null
    bash ./docker_ps.sh
    popd > /dev/null
  else
    # fallback: 直接查詢 docker
    echo "=== Orderer 節點 ==="
    docker ps -a --filter "name=orderer" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    echo ""
    echo "=== Peer 節點 ==="
    docker ps -a --filter "name=peer" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    echo ""
    echo "=== CouchDB ==="
    docker ps -a --filter "name=couchdb" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    echo ""
    echo "=== CLI ==="
    docker ps -a --filter "name=cli" --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
    echo ""
    echo "=== CA ==="
    docker ps -a --filter "name=ca-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
  fi
}

# ====================== clean ======================
function cmd_clean() {
  local work_dir="generated-network"

  while getopts "d:" opt; do
    case $opt in
      d) work_dir=$OPTARG ;;
    esac
  done

  printStep "徹底清理..."

  # 先停止
  if [ -f "$work_dir/stop.sh" ]; then
    printInfo "停止所有容器..."
    pushd "$work_dir" > /dev/null
    bash ./stop.sh 2>/dev/null || true
    popd > /dev/null
  fi

  # 清理鏈碼容器和映像
  printInfo "清理鏈碼容器..."
  CHAINCODE_CONTAINERS=$(docker ps -aq --filter "name=dev-peer" 2>/dev/null || true)
  if [ -n "$CHAINCODE_CONTAINERS" ]; then
    docker rm -f $CHAINCODE_CONTAINERS 2>/dev/null || true
  fi

  CHAINCODE_IMAGES=$(docker images -q --filter "reference=dev-peer*" 2>/dev/null || true)
  if [ -n "$CHAINCODE_IMAGES" ]; then
    docker rmi -f $CHAINCODE_IMAGES 2>/dev/null || true
  fi

  # 刪除生成的目錄
  if [ -d "$work_dir" ]; then
    printInfo "刪除工作目錄: $work_dir"
    rm -rf "$work_dir"
  fi

  printInfo "清理完成"
}

# ====================== 主入口 ======================
COMMAND=${1:-help}
shift 2>/dev/null || true

case "$COMMAND" in
  generate)
    cmd_generate "$@"
    ;;
  deploy)
    cmd_deploy "$@"
    ;;
  start)
    cmd_start "$@"
    ;;
  stop)
    cmd_stop "$@"
    ;;
  restart)
    cmd_restart "$@"
    ;;
  status)
    cmd_status "$@"
    ;;
  clean)
    cmd_clean "$@"
    ;;
  help|-h|--help)
    show_help
    ;;
  *)
    printError "未知命令: $COMMAND"
    echo ""
    echo "可用命令: generate | deploy | start | stop | restart | status | clean | help"
    echo "執行 ./fabric.sh help 查看完整說明"
    exit 1
    ;;
esac
