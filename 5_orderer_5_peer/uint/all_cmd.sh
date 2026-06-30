#!/bin/bash

printf "\n==============\n"

printf "clc1\n\n"
ssh -t clc1@192.168.0.11 "$@"
printf "\n==============\n"

printf "clc2\n\n"
ssh -t clc2@192.168.0.12 "$@"
printf "\n==============\n"

printf "clc3\n\n"
ssh -t clc3@192.168.0.13 "$@"
printf "\n==============\n"

printf "clc4\n\n"
ssh -t clc4@192.168.0.14 "$@"
printf "\n==============\n"
