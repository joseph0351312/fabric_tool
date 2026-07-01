# Hyperledger Fabric Network Tool

🚀 一鍵生成、部署、管理 Hyperledger Fabric 區塊鏈網路的命令列工具。

自動化生成所有配置文件、Docker Compose 編排、操作腳本，支援單機快速部署和分佈式多機 SSH 部署。

---

## ✨ 核心特性

- ✅ **一鍵生成** — 自動生成完整 Fabric 網路配置（可自定義 Orderer 和 Peer 組織數量）
- ✅ **靈活部署** — 支援單機部署和多機 SSH 遠端部署
- ✅ **自動化腳本** — 生成所有必需的啟動、停止、配置腳本
- ✅ **易於管理** — 內建 Chaincode 部署、升級、查詢工具
- ✅ **快速驗證** — 支援區塊鏈瀏覽器 (Fabric Explorer) 配置
- ✅ **標準化端口** — 遵循統一的端口分配規則，便於多機協調

---

## 📋 前置需求

### 本機環境
- **Docker & Docker Compose** — 容器化部署
- **Hyperledger Fabric 工具**
  - `cryptogen` — 生成加密材料
  - `configtxgen` — 生成通道和組織配置
  - [📖 Fabric 安裝指南](https://hyperledger-fabric.readthedocs.io/en/latest/install.html)

### 多機部署
- 遠端主機間 **SSH 無密碼登入** — 運行 `ssh-copy-id user@host` 配置
- 遠端主機已安裝 Docker 和 Fabric 工具

---

## 🎯 快速開始

### 最快開始（3 步）

```bash
# 1. 生成網路配置 (3 個 Orderer + 4 個 Peer 組織)
./fabric-tool.sh generate -o 3 -p 4 -c mychannel

# 2. 進入生成目錄
cd generated-network

# 3. 啟動網路 + 建立 channel
./start.sh set_channel
```

✅ 完成！網路已啟動，可開始部署 Chaincode

---

## 📖 命令參考

### generate — 生成網路配置

自動生成完整的 Fabric 網路目錄結構和所有配置文件。

```bash
./fabric-tool.sh generate [選項]
```

**選項：**

| 選項 | 說明 | 預設值 |
|------|------|-------|
| `-o <數量>` | Orderer 節點數量（建議奇數） | 5 |
| `-p <數量>` | Peer 組織數量 | 5 |
| `-c <名稱>` | Channel 名稱 | mychannel |
| `-d <目錄>` | 輸出目錄 | generated-network |
| `-b <路徑>` | Fabric 工具路徑（cryptogen/configtxgen 所在目錄） | 自動檢測 |

**範例：**

```bash
# 最小網路（測試用）
./fabric-tool.sh generate -o 1 -p 1 -c testchannel

# 一般網路
./fabric-tool.sh generate -o 3 -p 4 -c mychannel

# 生產級網路，指定工具路徑
./fabric-tool.sh generate -o 5 -p 5 -c prodchannel -b /opt/fabric/bin

# 自定義輸出目錄
./fabric-tool.sh generate -o 3 -p 4 -d ./my-network
```

---

### deploy — 多機部署

將生成的網路配置分佈式部署到多台遠端主機。

```bash
./fabric-tool.sh deploy [選項]
```

**選項：**

| 選項 | 說明 |
|------|------|
| `-f <檔案>` | 部署配置文件（預設：network-config.yaml） |
| `-b <路徑>` | Fabric 工具路徑 |
| `-t` | 測試 SSH 連線（不執行部署） |
| `-g` | 僅生成配置，不部署 |
| `-d` | 僅部署，跳過生成 |
| `-s` | 部署後自動啟動網路 |
| `-c` | 清理所有遠端節點 |

**典型工作流：**

```bash
# 1. 從範例建立配置
cp network-config.yaml.example network-config.yaml
vim network-config.yaml  # 編輯主機列表

# 2. 測試 SSH 連線
./fabric-tool.sh deploy -f network-config.yaml -t

# 3. 部署 + 自動啟動
./fabric-tool.sh deploy -f network-config.yaml -s

# （可選）清理所有遠端節點
./fabric-tool.sh deploy -f network-config.yaml -c
```

---

## 🗂️ 生成的目錄結構

執行 `generate` 後會產生以下目錄：

```
generated-network/
├── 🚀 start.sh                    # 啟動網路腳本（支援多個子命令）
├── ⛔ stop.sh                     # 停止容器
├── 🔄 restart.sh                  # 重啟容器
├── 📊 docker_ps.sh                # 查看容器運行狀態
├── ⚙️ configtx.sh                 # 生成通道配置
├── 📄 configtx.yaml               # Fabric 通道配置文件
│
├── 🐳 docker/                     # Docker Compose 編排文件
│   ├── docker-compose-order.yaml  # Orderer 容器配置
│   ├── docker-compose-org0.yaml   # Org0 (Peer + CA + CouchDB)
│   ├── docker-compose-org1.yaml   # Org1 (Peer + CA + CouchDB)
│   └── docker-compose-cli.yaml    # CLI 測試容器
│
├── 🛠️ uint/                       # Chaincode 部署工具
│   ├── deploy.sh                  # 打包 + 安裝 chaincode
│   ├── set_chaincode.sh           # 審批 chaincode（Lifecycle）
│   ├── chaincode_seting_all.sh    # commit + init chaincode
│   ├── all_cmd.sh                 # 遠端批次執行命令
│   └── ssh_docker.sh              # 遠端 Docker 操作
│
├── 🔐 organizations/              # 組織和認證配置
│   ├── crypto-config.yaml         # 加密材料生成配置
│   ├── ccp-generate.sh            # 生成連線設定檔 (CCP)
│   ├── ccp-template.json          # JSON 格式連線設定模板
│   └── ccp-template.yaml          # YAML 格式連線設定模板
│
├── 📦 channel-artifacts/          # 通道配置產物（自動生成）
│   ├── mychannel.tx               # 通道交易
│   └── Org*.json                  # 組織定義
│
├── 💻 chaincode/go/               # Chaincode 源代碼目錄
│   └── (放置你的 Go Chaincode)
│
└── 🔍 fabric-explorer/            # Blockchain Explorer 配置（可選）
    └── docker-compose.yaml
```

---

## ▶️ start.sh 子命令

生成的 `start.sh` 支援以下操作：

```bash
# 啟動容器（不建立 channel）
./start.sh up

# 重啟所有容器
./start.sh restart

# 啟動 + 建立 channel（最常用）
./start.sh set_channel

# 啟動 + channel + 部署默認 chaincode
./start.sh set_chaincode

# 部署指定 chaincode（一鍵）
./start.sh deploy <cc_name> <cc_file> <cc_label> <version> <sequence>

# 範例
./start.sh deploy mycc ./chaincode/go/contract mycc_label 1.0 1
./start.sh deploy mycc ./chaincode/go/contract mycc_label 2.0 2  # 升級

# 部署時指定 package_id（高級）
./start.sh deploy <cc_name> <cc_file> <cc_label> <ver> <seq> <package_id>
```

---

## 🔧 部署配置格式

多機部署時，編輯 `network-config.yaml` 指定遠端主機：

```yaml
# network-config.yaml 示例
channel: mychannel

# Orderer 節點：編號:user@host:遠端目錄
orderer:0:ubuntu@192.168.1.10:/opt/fabric-network
orderer:1:ubuntu@192.168.1.11:/opt/fabric-network
orderer:2:ubuntu@192.168.1.12:/opt/fabric-network

# Peer 節點：編號:user@host:遠端目錄
peer:0:ubuntu@192.168.1.20:/opt/fabric-network
peer:1:ubuntu@192.168.1.21:/opt/fabric-network
peer:2:ubuntu@192.168.1.22:/opt/fabric-network
```

**說明：**
- `編號` — 節點的唯一編號（決定端口號）
- `user@host` — SSH 登入用戶和主機名/IP
- `/opt/fabric-network` — 遠端主機上的工作目錄

---

## 🌐 端口分配規則

節點端口按編號自動分配。為 N 號節點：

| 服務 | 端口規則 | N=0 | N=1 | N=2 |
|------|---------|-----|-----|-----|
| **Orderer** 主要 | 7050 + N×1000 | 7050 | 8050 | 9050 |
| **Orderer** Admin | 7053 + N×1000 | 7053 | 8053 | 9053 |
| **Orderer** Metrics | 7440 + N×1000 | 7440 | 8440 | 9440 |
| **Peer** | 7051 + N×1000 | 7051 | 8051 | 9051 |
| **Peer** Chaincode | 7052 + N×1000 | 7052 | 8052 | 9052 |
| **CA** | 7054 + N×1000 | 7054 | 8054 | 9054 |
| **CouchDB** | 5984 + N×1000 | 5984 | 6984 | 7984 |

---

## 📚 操作流程示例

### 單機部署

完整的單機網路部署和 Chaincode 部署流程：

```bash
# 1️⃣ 生成網路配置
./fabric-tool.sh generate -o 3 -p 2

# 2️⃣ 進入生成目錄
cd generated-network

# 3️⃣ 啟動網路 + 建立 channel
./start.sh set_channel

# 4️⃣ 部署 chaincode（一鍵）
./start.sh deploy mycc ./chaincode/go/contract mycc_label 1.0 1

# ✅ 完成！網路已可用
```

**驗證網路：**
```bash
# 查看所有容器
./docker_ps.sh

# 檢查 channel 信息
docker exec cli0 peer channel list

# 查看已安裝的 chaincode
docker exec cli0 peer lifecycle chaincode queryinstalled
```

### 多機部署

跨多台服務器部署 Fabric 網路：

```bash
# 1️⃣ 準備部署配置
cp network-config.yaml.example network-config.yaml
vim network-config.yaml

# 配置示例：
# orderer:0:user@10.0.0.10:/opt/fabric
# orderer:1:user@10.0.0.11:/opt/fabric
# peer:0:user@10.0.0.20:/opt/fabric
# peer:1:user@10.0.0.21:/opt/fabric

# 2️⃣ 測試 SSH 連線
./fabric-tool.sh deploy -f network-config.yaml -t

# 3️⃣ 執行完整部署 + 自動啟動
./fabric-tool.sh deploy -f network-config.yaml -s

# 4️⃣ 驗證部署
# 在任一遠端主機上檢查容器狀態
ssh user@10.0.0.10 'cd /opt/fabric && ./docker_ps.sh'
```

### Chaincode 分步部署（詳細說明）

如需分步控制部署過程：

```bash
cd generated-network

# 1️⃣ 打包 chaincode
bash uint/deploy.sh mycc ./chaincode/go/contract mycc_1

# 2️⃣ 查詢生成的 package ID
docker exec cli0 peer lifecycle chaincode queryinstalled
# 輸出: mycc_1:a1b2c3d4... (複製此 ID)

# 3️⃣ 每個 org 都需審批此 chaincode
# Org0 審批
bash uint/set_chaincode.sh cli0 a1b2c3d4... mychannel mycc 1.0 1

# Org1 審批
bash uint/set_chaincode.sh cli1 a1b2c3d4... mychannel mycc 1.0 1

# 4️⃣ 全網 commit + 初始化
bash uint/chaincode_seting_all.sh mychannel mycc 1.0 1

# ✅ Chaincode 已激活
```

---

## 📋 專案結構

本工具的核心源代碼：

```
fabric_tool/
├── 🎯 fabric-tool.sh              # 主入口腳本（負責 generate 和 deploy）
├── 📚 lib/
│   ├── generate-network.sh        # 🔧 生成網路配置的核心邏輯
│   └── deploy.sh                  # 🔧 多機部署的核心邏輯
├── 📖 example/                    # 原始參考腳本
├── 📝 network-config.yaml.example # 多機部署配置範例
├── 📦 5_orderer_5_peer/           # 預生成的示例網路（可參考）
└── README.md
```

---

## 🐛 常見問題與排除

### 問題：`cryptogen: command not found`

**解決方案：**
- 確認 Fabric 工具已安裝：`which cryptogen`
- 指定工具路徑：
  ```bash
  ./fabric-tool.sh generate -b /opt/fabric/bin -o 3 -p 4
  ```

### 問題：Docker Compose 啟動失敗

**檢查步驟：**
```bash
# 查看容器日誌
docker-compose -f docker/docker-compose-order.yaml logs

# 確認 Docker 守護進程運行
docker ps
```

### 問題：多機部署 SSH 連線失敗

**排除步驟：**
```bash
# 1. 測試 SSH 連線
ssh user@remote-host 'echo OK'

# 2. 配置無密碼登入
ssh-copy-id user@remote-host

# 3. 再次測試部署連線
./fabric-tool.sh deploy -f network-config.yaml -t
```

### 問題：Chaincode 部署失敗

**檢查清單：**
- ✅ Channel 已建立：`./start.sh set_channel`
- ✅ 所有 Org 已審批 chaincode
- ✅ 使用正確的 package_id
- ✅ Chaincode 源代碼放在 `chaincode/go/` 目錄

---

## 📖 更多資源

- [Hyperledger Fabric 官方文檔](https://hyperledger-fabric.readthedocs.io/)
- [Fabric Chaincode 開發指南](https://hyperledger-fabric.readthedocs.io/en/latest/chaincode.html)
- [Fabric 網路部署最佳實踐](https://hyperledger-fabric.readthedocs.io/en/latest/best_practices.html)

---

## 📝 授權

MIT License

---

**需要幫助？** 檢查 `./start.sh --help` 或查看 `example/` 目錄中的參考腳本。
