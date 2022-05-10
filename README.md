# sample-api-accelerator

Example accelerator for creating a spring boot based REST api

# Local Development 

This sample includes a docker-compose file for running PostgreSQL 12 in `db/local` folder. You can 
start a local PostgreSQL easily for local development. It will run port 15432 and pgAdmin ui will run 
on port 15433.

# Deploying to Kubernetes

Deployment to Kubernetes is handled via the Tanzu Application Platform (TAP) 
running on GKE. You need access to the GKE cluster in-order to execute 
the commands below. 

## Provision GCP Cloud SQL Postgres 

The app requires a GCP Postgres Cloud SQL so we need a way create a Postgres Cloud SQL
instance. The cloud sql instance will be created using cross plane. Once the database
is ready we will configure a TAP resource claim against the cloud sql instance so that 
Kubernetes Service Binding is generated that allows spring boot to automatically connect to
the application. You can read about the service binding spec at 
[https://servicebinding.io/](https://servicebinding.io/)

1. Review the cross plane `PostgreSQLInstance` config located in `db/gcp/cloudsql-postgres.yaml` 
2. Apply cross plane config`kubectl apply -f db/gcp/cloudsql-postgres.yaml --namespace TARGET-NS` 
3. Go to the GCP console and watch the DB being created 
4. monitor the creation of the postgres `kubectl get postgresqlinstance sample-api-db -n TARGET-NS` 
   after a few minutes you will see output indicating that the db is ready as shown below. It can
   take several minutes for GCP to spin up the database so you will need to wait a few minutes.
```text
NAME            READY   CONNECTION-SECRET    AGE
sample-api-db   True    sample-api-db-conn   3m55s
```
5. Cross plane creates a secret with connection details, validate that the secret is ava by running
   ` kubectl describe secret sample-api-db-conn -n TARGET-NS` example output 
```text
Name:         sample-api-db-conn
Namespace:    asaikali
Labels:       <none>
Annotations:  <none>

Type:  connection.crossplane.io/v1alpha1

Data
====
endpoint:  13 bytes
password:  27 bytes
port:      4 bytes
username:  8 bytes
```

6. Notice that the secret created by cross plane has 4 data elements with connectivity info to connect to
   the newly created database. The endpoint field contains the ip address of the database.

## Create a Service Binding Compatible Secret

The fields of the secret created by cross plane are not compatible with the fields that the 
[service binding spec](https://servicebinding.io/) expect, so we need to make a new 
secret that meets the requirements of the service binding spec. The repo provides a shell
script to create the service bindings spec compatible secret. 

1. Inspect the code for the script `bin/get-db-connection-secret.sh`
2. execute the script `bin/get-db-connection-secret.sh CROSS-PLANE-SECRET-NAME NAMESPACE`. You need 
   to provide the script with the name of the sceret created by cross plane in the steps above, and  
   the namespace that the secret is written into. Example command `get-db-connection-secret.sh sample-api-db-conn asaikali` 
   produces redacted output shown below 
```text
---
apiVersion: v1
kind: Secret
metadata:
  name: "sample-api-db-conn-service-binding-compatible"
  namespace: asaikali
type: Opaque
stringData:
  type: postgresql
  provider: gcp
  host: "35.225.25.133"
  port: "5432"
  database: "postgres"
  username: "postgres"
  password: "redacted"
```
3. Inspect the output and make sure that it looks correct i.e. there are actual values in the hostname, port,
   database, username, and password fields. We will need to apply this output to cluster is the developer namespace
   where the TAP workload will be deployed. Apply the service binding compatible secret to the cluster using command
   `bin/get-db-connection-secret.sh CROSS-PLANE-SECRET-NAME NAMESPACE | kubectl apply -f -` for example 
   `get-db-connection-secret.sh sample-api-db-conn asaikali | kubectl apply -f -` should result in output like 
```text
secret/sample-api-db-conn-service-binding-compatible created
```
4. Inspect that newly created service binding compatible value secret has the correct values for example 
   `kubectl get secret sample-api-db-conn-service-binding-compatible -n asaikali -o YAML` produces the redacted
   output below
```text
apiVersion: v1
data:
  database: cG9zdGdyZXM=
  host: MzUuMjI1LjI1LjExNg==
  password: redacted
  port: NTQzMg==
  provider: Z2Nw
  type: cG9zdGdyZXNxbA==
  username: cG9zdGdyZXM=
kind: Secret
metadata:
  name: sample-api-db-conn-service-binding-compatible
  namespace: asaikali
type: Opaque
```
## Create a Service Claim Against the Service Binding Compatible Secret 

1. The services' toolkit component in Tanzu Application Platform can be used define a service claim 
   against the secret we created in the last step. The command template show below you will need to 
```text
  tanzu service claim create cloudsql-postgres-claim \
  --resource-name  SECRET-NAME-FROM-LAST-STEP \
  --resource-kind Secret \
  --resource-api-version v1 \
  --namespace TAP-DEV-NAMESPACE
```
2. For example command based on the previous step is 
```text
  tanzu service claim create cloudsql-postgres-claim \
  --resource-name  sample-api-db-conn-service-binding-compatible \
  --resource-kind Secret \
  --resource-api-version v1 \
  --namespace asaikali
```
   produces the output 
```text
  Warning: This is an ALPHA command and may change without notice.

Creating claim 'cloudsql-postgres-claim' in namespace 'asaikali'.
Please run `tanzu services claims get cloudsql-postgres-claim --namespace asaikali` to see the progress of create.
```
3. List all the claims that exist in the namespace `tanzu services claims list -n asaikali` should produce output 
   showing that the claim we just created is ready to be used
```text
 Warning: This is an ALPHA command and may change without notice.

  NAME                     READY  REASON  
  cloudsql-postgres-claim  True           
```
4. Inspect that the claim status using suggested command output from previous step 
   `tanzu services claims get cloudsql-postgres-claim --namespace asaikali` produces the k8s YAML that the command 
    in the last step generated 
```text
Name: cloudsql-postgres-claim
Status: 
  Ready: True
Namespace: asaikali
Claim Reference: services.apps.tanzu.vmware.com/v1alpha1:ResourceClaim:cloudsql-postgres-claim
Resource to Claim: 
  Name: sample-api-db-conn-service-binding-compatible
  Namespace: asaikali
  Group: 
  Version: v1
  Kind: Secret
```