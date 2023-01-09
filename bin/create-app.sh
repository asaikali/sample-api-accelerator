#!/bin/bash -e

az spring app create \
 --service demo-asa \
 --resource-group demo \
 --assign-endpoint true \
 --system-assigned \
 --name quotes \
 --jvm-options='-Dspring.profiles.active=azure'
