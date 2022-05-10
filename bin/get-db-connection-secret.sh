#!/bin/bash -e

# get the secret generated by cross plane
if [ -z "$1" ]; then
 echo "first arg must be the cross plane secret name"
 exit 1
fi
CROSSPLANE_SECRET=$1

# extract connection details from cross plane generated secret
POSTGRES_USER=$(kubectl get secret $CROSSPLANE_SECRET --output 'jsonpath={.data.username}' | base64 --decode)
POSTGRES_PASSWORD=$(kubectl get secret $CROSSPLANE_SECRET --output 'jsonpath={.data.password}' | base64 --decode)
POSTGRES_ENDPOINT=$(kubectl get secret $CROSSPLANE_SECRET --output 'jsonpath={.data.endpoint}' | base64 --decode)
POSTGRES_PORT=$(kubectl get secret $CROSSPLANE_SECRET --output 'jsonpath={.data.port}' | base64 --decode)

echo "
---
apiVersion: v1
kind: Secret
metadata:
  name: \"$CROSSPLANE_SECRET-service-binding-compatible\"
type: Opaque
stringData:
  type: postgresql
  provider: gcp
  host: \"$POSTGRES_ENDPOINT\"
  port: \"$POSTGRES_PORT\"
  database: \"postgres\"
  username: \"$POSTGRES_USER\"
  password: \"$POSTGRES_PASSWORD\"
"