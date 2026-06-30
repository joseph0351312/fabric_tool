#!/bin/bash
function removeUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    infoln "No images available for deletion"
  else
    docker rmi -f $DOCKER_IMAGE_IDS
  fi
}

function stopUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    infoln "No images available for deletion"
  else
    docker stop -f $DOCKER_IMAGE_IDS
  fi
}


ss=$1


docker compose -f ./docker/docker-compose-order.yaml  -f ./docker/docker-compose-org0.yaml -f ./docker/docker-compose-cli.yaml  down $1
./uint/all_cmd.sh "~/5_orderer_5_peer/stop.sh ${ss} " 
if [ "$ss" = "-v" ];then

    removeUnwantedImages
fi

