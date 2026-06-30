# Hyperledger Fabric Network Tool

一鍵生成、部署、管理 Hyperledger Fabric 網路的命令列工具。

根據指定的 Orderer 數量和 Peer 組織數量，自動生成所有配置文件、Docker Compose、操作腳本，支援單機部署和多機 SSH 部署。

## 前置需求

- Docker & Docker Compose
- Hyperledger Fabric 工具 (`cryptogen`, `configtxgen`)
  - [Fabric 安裝指南](https://hyperledger-fabric.readthedocs.io/en/latest/install.html)
- 多機部署需設定 SSH 無密碼登入 (`ssh-copy-id`)

## 快速開始

```bash
# 生成 3 orderer + 4 peer 的網路
./fabric-tool.sh generate -o 3 -p 4 -c mychannel

# 進入生成目錄，啟動 + 建立 channel
cd generated-network
./start.sh set_channel
```

## 命令說明

### generate — 生成網路配置

```bash
./fabric-tool.sh generate [選項]

選項:
  -o <數量>    Orderer 節點數量 (預設: 5, 建議奇數)
  -p <數量>    Peer 組織數量 (預設: 5)
  -c <名稱>    Channel 名稱 (預設: mychannel)
  -d <目錄>    輸出目錄 (預設: generated-network)
  -b <路徑>    Fabric 工具路徑 (cryptogen/configtxgen 所在目錄)
```

範例:
```bash
# 最小網路
./fabric-tool.sh generate -o 1 -p 1 -c testchannel

# 生產級網路，指定工具路徑
./fabric-tool.sh generate -o 5 -p 5 -c prodchannel -b /opt/fabric/bin
```

### deploy — 多機部署

```bash
./fabric-tool.sh deploy [選項]

選項:
  -f <檔案>    部署配置文件 (預設: network-config.yaml)
  -b <路徑>    Fabric 工具路徑
  -g           僅生成配置，不部署
  -d           僅部署，跳過生成
  -s           部署後自動啟動
  -c           清理所有遠端節點
  -t           測試 SSH 連線
```

範例:
```bash
# 測試 SSH 連線
./fabric-tool.sh deploy -f network-config.yaml -t

# 完整部署 + 自動啟動
./fabric-tool.sh deploy -f network-config.yaml -s

# 清理遠端節點
./fabric-tool.sh deploy -f network-config.yaml -c
```

## 生成的目錄結構

```
generated-network/
├── start.sh                      # 啟動腳本 (支援子命令)
├── stop.sh                       # 停止 (支援 -v 清理映像)
├── restart.sh                    # 重啟容器
├── docker_ps.sh                  # 查看容器狀態
├── configtx.sh                   # 通道配置生成
├── configtx.yaml                 # Fabric 通道配置
├── docker/
│   ├── docker-compose-order.yaml # Orderer 容器
│   ├── docker-compose-orgN.yaml  # 各 Org 容器 (Peer + CA + CouchDB)
│   └── docker-compose-cli.yaml   # CLI 容器
├── uint/
│   ├── deploy.sh                 # 打包 + 安裝 chaincode
│   ├── set_chaincode.sh          # 審批 chaincode
│   ├── chaincode_seting_all.sh   # commit + init chaincode
│   ├── all_cmd.sh                # 遠端批次命令
│   └── ssh_docker.sh             # 遠端 docker 操作
├── organizations/
│   ├── crypto-config.yaml        # 加密材料配置
│   ├── ccp-generate.sh           # 連線設定生成
│   ├── ccp-template.json
│   └── ccp-template.yaml
├── channel-artifacts/            # 通道配置產物
├── chaincode/go/                 # Chaincode 原始碼 (放這裡)
└── fabric-explorer/              # Blockchain Explorer 配置
```

## start.sh 子命令

```bash
./start.sh up                                                        # 僅啟動容器
./start.sh restart                                                   # 重啟容器
./start.sh set_channel                                               # 啟動 + 建立 channel
./start.sh set_chaincode                                             # 啟動 + channel + chaincode
./start.sh deploy <name> <file> <label> <ver> <seq>                  # 部署指定 chaincode
./start.sh deploy <name> <file> <label> <ver> <seq> <package_id>     # 部署 (指定 package_id)
```

## 操作流程

### 單機部署

```bash
# 1. 生成
./fabric-tool.sh generate -o 3 -p 4

# 2. 啟動 + 建立 channel
cd generated-network
./start.sh set_channel

# 3. 部署 chaincode (一鍵)
./start.sh deploy mycc mycc mycc_1 1.0 1

# 或分步操作:
bash uint/deploy.sh mycc mycc mycc_1
docker exec cli0 peer lifecycle chaincode queryinstalled
bash uint/set_chaincode.sh cli0 <package_id> mychannel mycc 1.0 1
# ... 每個 org 都要審批
bash uint/chaincode_seting_all.sh mychannel mycc 1.0 1
```

### 多機部署

```bash
# 1. 編輯部署配置
cp network-config.yaml.example network-config.yaml
vim network-config.yaml

# 2. 測試連線
./fabric-tool.sh deploy -f network-config.yaml -t

# 3. 部署 + 啟動
./fabric-tool.sh deploy -f network-config.yaml -s
```

### 部署配置格式

```yaml
# network-config.yaml
channel: mychannel

# orderer:編號:user@host:遠端目錄
orderer:0:user@192.168.1.10:/opt/fabric-network
orderer:1:user@192.168.1.11:/opt/fabric-network
orderer:2:user@192.168.1.12:/opt/fabric-network

# peer:編號:user@host:遠端目錄
peer:0:user@192.168.1.20:/opt/fabric-network
peer:1:user@192.168.1.21:/opt/fabric-network
```

## Port 分配規則

| 節點類型 | Port 規則 | 範例 (N=0) | 範例 (N=1) |
|---------|----------|-----------|-----------|
| Orderer 主要 | 7050 + N×1000 | 7050 | 8050 |
| Orderer Admin | 7053 + N×1000 | 7053 | 8053 |
| Orderer Metrics | 7440 + N×1000 | 7440 | 8440 |
| Peer | 7051 + N×1000 | 7051 | 8051 |
| CA | 7054 + N×1000 | 7054 | 8054 |
| CouchDB | 5984 + N×1000 | 5984 | 6984 |

## 專案結構

```
fabric-network-tool/
├── fabric-tool.sh              # 主入口
├── lib/
│   ├── generate-network.sh     # 網路生成核心邏輯
│   └── deploy.sh               # 多機部署核心邏輯
├── example/                    # 原始範例腳本 (參考用)
├── network-config.yaml.example # 部署配置範例
├── .gitignore
└── README.md
```
