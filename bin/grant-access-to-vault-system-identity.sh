#!/bin/bash -ex

ID=$(az spring app identity show \
                             --service demo-asa \
                             --resource-group demo \
                             --name quotes \
                             --out tsv \
                             --query principalId)
echo $ID
az keyvault set-policy  \
 --name asaikali-vault \
 --object-id ${ID} \
 --secret-permissions get list
