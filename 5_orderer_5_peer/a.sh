


channel_name=trustchainchannel
chaincode_name=register
chaincode_name_1=configurate

org1_addr=peer0.org1.com:8051
org2_addr=peer0.org2.com:9051
org3_addr=peer0.org3.com:10051
org4_addr=peer0.org4.com:11051

org1_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.com/peers/peer0.org1.com/tls/ca.crt
org2_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.com/peers/peer0.org2.com/tls/ca.crt
org3_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.com/peers/peer0.org3.com/tls/ca.crt
org4_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org4.com/peers/peer0.org4.com/tls/ca.crt



docker exec -it cli1 peer chaincode invoke -o orderer.com:7050 --ordererTLSHostnameOverride orderer.com  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer.com/msp/tlscacerts/tlsca.com-cert.pem  --channelID ${channel_name} --name ${chaincode_name_1}  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/orderers/orderer.com/msp/tlscacerts/tlsca.com-cert.pem --peerAddresses ${org1_addr}  --tlsRootCertFiles ${org1_tls} --peerAddresses ${org2_addr}  --tlsRootCertFiles ${org2_tls} --peerAddresses ${org3_addr}  --tlsRootCertFiles ${org3_tls} --peerAddresses ${org4_addr}  --tlsRootCertFiles ${org4_tls}  -c '{"function":"Configuration","Args":["System","0xB136eE3352847dB02bf747B52840955ADDf33EF8","Module","0x75Fc0087e9890528D95b34a2BDA0e60D777BB21D"]}'

sleep 2


echo
echo "ReadSystem data id 0xB136eE3352847dB02bf747B52840955ADDf33EF8"
echo
docker exec -it cli1 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["ReadSystem","0xB136eE3352847dB02bf747B52840955ADDf33EF8"]}'
sleep 2

#===========================================================







