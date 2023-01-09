#!/bin/bash -e

az spring app deploy \
 --service demo-asa \
 --resource-group demo \
 --name quotes \
 --artifact-path target/sample-api-accelerator-0.0.1-SNAPSHOT.jar
