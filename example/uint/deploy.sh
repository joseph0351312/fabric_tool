
chaincode_file=$2
chaincode_name=$1
labe_name=$3

docker exec -it cli0 peer lifecycle chaincode package $chaincode_name.tar.gz  --path  /opt/gopath/src/github.com/hyperledger/fabric-cluster/chaincode/go/$chaincode_file --lang golang  --label $labe_name


docker cp cli0:/opt/gopath/src/github.com/hyperledger/fabric/peer/$chaincode_name.tar.gz ./
docker cp ./$chaincode_name.tar.gz cli1:/opt/gopath/src/github.com/hyperledger/fabric/peer/
docker cp ./$chaincode_name.tar.gz cli2:/opt/gopath/src/github.com/hyperledger/fabric/peer/
docker cp ./$chaincode_name.tar.gz cli3:/opt/gopath/src/github.com/hyperledger/fabric/peer/
docker cp ./$chaincode_name.tar.gz cli4:/opt/gopath/src/github.com/hyperledger/fabric/peer/

docker exec -it cli0 peer lifecycle chaincode install $chaincode_name.tar.gz
docker exec -it cli1 peer lifecycle chaincode install $chaincode_name.tar.gz
docker exec -it cli2 peer lifecycle chaincode install $chaincode_name.tar.gz
docker exec -it cli3 peer lifecycle chaincode install $chaincode_name.tar.gz
docker exec -it cli4 peer lifecycle chaincode install $chaincode_name.tar.gz
