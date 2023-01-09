#!/bin/bash -ex

az spring app identity show \
 --service demo-asa \
 --resource-group demo \
 --name quotes \
 --out tsv \
 --query principalId
