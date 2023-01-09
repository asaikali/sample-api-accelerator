#!/bin/bash -e

az spring app logs \
 --service demo-asa \
 --resource-group demo \
 --name quotes \
 --follow
