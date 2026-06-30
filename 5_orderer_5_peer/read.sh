


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






echo
echo "ReadSystem data id 0xBB36eE3352847dB02bf747B52840955ADDf33EF8"
echo
docker exec -it cli1 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["ReadSystem","0xBB36eE3352847dB02bf747B52840955ADDf33EF8"]}'
#sleep 3




echo
echo "ReadSystem data id 0xBBB6eE3352847dB02bf747B52840955ADDf33EF8"
echo
docker exec -it cli1 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["ReadSystem","0xBBB6eE3352847dB02bf747B52840955ADDf33EF8"]}'
#sleep 3

echo
echo "ReadSystem data id 0xBBC6eE3352847dB02bf747B52840955ADDf33EF8"
echo
docker exec -it cli1 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["ReadSystem","0xBBC6eE3352847dB02bf747B52840955ADDf33EF8"]}'
#sleep 3

echo
echo "ReadSystem data id 0xBBD6eE3352847dB02bf747B52840955ADDf33EF8"
echo
docker exec -it cli1 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["ReadSystem","0xBBD6eE3352847dB02bf747B52840955ADDf33EF8"]}'
#sleep 3
echo
echo "ReadSystem data id 0xBBD6eE3352847dB02bf747B52840955ADDf33EF8"
echo
docker exec -it cli1 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["ReadSystem","0xBBE6eE3352847dB02bf747B52840955ADDf33EF8"]}'
#sleep 3


