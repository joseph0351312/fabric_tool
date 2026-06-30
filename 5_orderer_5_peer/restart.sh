#!/bin/bash


function restartUnwantedImages() {
  DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-peer.*/) {print $3}')
  if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
    infoln "No images available for deletion"
  else
    docker restart -f $DOCKER_IMAGE_IDS
  fi
}

docker-compose -f ./docker/docker-compose-order.yaml  -f ./docker/docker-compose-org1.yaml -f ./docker/docker-compose-org2.yaml  -f ./docker/docker-compose-org3.yaml -f ./docker/docker-compose-org4.yaml -f ./docker/docker-compose-org5.yaml restart

