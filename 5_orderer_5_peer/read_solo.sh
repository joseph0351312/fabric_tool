


channel_name=trustchainchannel
#chaincode_name=merkletree_register
chaincode_name=register
chaincode_name_1=configurate_old
#chaincode_name_1=merkletree_configurate
blockchain_address=$1
org1_addr=peer0.org1.com:8051
org2_addr=peer0.org2.com:9051
org3_addr=peer0.org3.com:10051
org4_addr=peer0.org4.com:11051

org1_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org1.com/peers/peer0.org1.com/tls/ca.crt
org2_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.com/peers/peer0.org2.com/tls/ca.crt
org3_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org3.com/peers/peer0.org3.com/tls/ca.crt
org4_tls=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org4.com/peers/peer0.org4.com/tls/ca.crt






echo
echo "Read data id ${blockchain_address}"
echo
docker exec -it $2 peer chaincode query -C ${channel_name} -n ${chaincode_name} -c '{"Args":["Read","'${blockchain_address}'"]}'
#sleep 3

echo
echo "Read data id ${blockchain_address}"
echo
docker exec -it $2 peer chaincode query -C ${channel_name} -n ${chaincode_name_1} -c '{"Args":["Read","'${blockchain_address}'"]}'



