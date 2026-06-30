	user=$1
	ip=$2
	org=$3
	docker_set1=$4
	docker_set2=$5
	workdir=5_orderer_5_peer

	ssh ${user}@${ip}  docker network create fabric-center
	ssh ${user}@${ip} "docker compose -f ~/${workdir}/docker/docker-compose-order.yaml -f  ~/${workdir}/docker/docker-compose-${org}.yaml  ${docker_set1} ${docker_set2} "
	ssh ${user}@${ip} "docker ps -a | grep orderer"
	ssh ${user}@${ip} "docker ps -a | grep peer"
	ssh ${user}@${ip} "docker ps -a | grep couch"
	ssh ${user}@${ip} "docker ps -a | grep cli"
