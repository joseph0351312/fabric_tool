channel_name=$3
chaincode_name=$4
chaincode_version=$5
chaincode_sequence=$6
docker exec -it $1 peer lifecycle chaincode approveformyorg -o orderer0.com:7050 --ordererTLSHostnameOverride orderer0.com --init-required   --channelID ${channel_name}  --name ${chaincode_name}  --version ${chaincode_version}    --package-id $2  --sequence  ${chaincode_sequence} --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/msp/tlscacerts/tlsca.com-cert.pem


docker exec -it $1 peer lifecycle chaincode checkcommitreadiness -o orderer0.com:7050 --ordererTLSHostnameOverride orderer0.com --init-required  --channelID ${channel_name} --name ${chaincode_name}  --version ${chaincode_version}   --sequence  ${chaincode_sequence} --tls true --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/com/msp/tlscacerts/tlsca.com-cert.pem  --output json


