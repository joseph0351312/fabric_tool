channel_name=$1
chaincode_name=$2
chaincode_version=$3
chaincode_sequence=$4
org0_addr=peer0.org0.com:7051
org1_addr=peer0.org1.com:8051
org2_addr=peer0.org2.com:9051
org3_addr=peer0.org3.com:10051
org4_addr=peer0.org4.com:11051

org0_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org0.com/peers/peer0.org0.com/tls/ca.crt
org1_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.com/peers/peer0.org1.com/tls/ca.crt
org2_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.com/peers/peer0.org2.com/tls/ca.crt
org3_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.com/peers/peer0.org3.com/tls/ca.crt
org4_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org4.com/peers/peer0.org4.com/tls/ca.crt




docker exec -it cli0 peer lifecycle chaincode commit -o orderer0.com:7050 --channelID ${channel_name} --name ${chaincode_name} --version ${chaincode_version} --sequence ${chaincode_sequence} --init-required --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem --peerAddresses ${org0_addr}  --tlsRootCertFiles ${org0_tls}   --peerAddresses ${org1_addr}  --tlsRootCertFiles ${org1_tls} --peerAddresses ${org2_addr}  --tlsRootCertFiles ${org2_tls} --peerAddresses ${org3_addr}  --tlsRootCertFiles ${org3_tls} --peerAddresses ${org4_addr}  --tlsRootCertFiles ${org4_tls}

docker exec -it cli0 peer lifecycle chaincode querycommitted --channelID ${channel_name} --name ${chaincode_name}  -o orderer0.com:7050 --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem 





docker exec -it cli0 peer chaincode invoke -o orderer0.com:7050 --ordererTLSHostnameOverride orderer0.com  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer0.com/msp/tlscacerts/tlsca.com-cert.pem --isInit  --channelID ${channel_name} --name ${chaincode_name}  --peerAddresses ${org0_addr}  --tlsRootCertFiles ${org0_tls}   --peerAddresses ${org1_addr}  --tlsRootCertFiles ${org1_tls} --peerAddresses ${org2_addr}  --tlsRootCertFiles ${org2_tls} --peerAddresses ${org3_addr}  --tlsRootCertFiles ${org3_tls} --peerAddresses ${org4_addr}  --tlsRootCertFiles ${org4_tls}  -c '{"function":"InitLedger","Args":[]}'
