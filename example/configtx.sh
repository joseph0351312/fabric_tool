printf "Genesischannel\n"
configtxgen -profile OrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block   -channelID fabric-channel

printf  "產生個通道配置文件\n"
configtxgen -profile channel  -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID channel


printf  "產生channel錨節點文件\n"
configtxgen -profile channel  -outputAnchorPeersUpdate ./channel-artifacts/Org0MSPanchors.tx -channelID channel -asOrg Org0MSP

configtxgen -profile channel  -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID channel -asOrg Org1MSP

configtxgen -profile channel  -outputAnchorPeersUpdate ./channel-artifacts/Org2MSPanchors.tx -channelID channel -asOrg Org2MSP

configtxgen -profile channel  -outputAnchorPeersUpdate ./channel-artifacts/Org3MSPanchors.tx -channelID channel -asOrg Org3MSP

configtxgen -profile channel  -outputAnchorPeersUpdate ./channel-artifacts/Org4MSPanchors.tx -channelID channel -asOrg Org4MSP
