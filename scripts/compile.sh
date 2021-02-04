#!/bin/sh

set -e

NAME=SOLC_COMPILER

rm -rf build

docker run \
  --rm \
  --name $NAME \
  -v ${PWD}:/src \
  -w /src \
  ethereum/solc:0.8.1 \
  --optimize --optimize-runs=99999 \
  --abi --bin -o /src/build \
  contracts/Multisig.sol \
  --base-path /src --allow-paths /src/node_modules,/src/contracts
