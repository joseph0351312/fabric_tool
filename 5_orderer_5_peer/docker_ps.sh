#!/bin/bash
	docker ps -a | grep orderer
	printf "\n"
        docker ps -a | grep peer
	printf "\n"
        docker ps -a | grep couch
	printf "\n"
        docker ps -a | grep cli

