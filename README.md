# sample-api-accelerator

This example application has a starter Spring REST api. The steps below show you how 
deploy and manage the app on Tanzu Application Platform.

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

## Deploy the app to Tanzu Application Platform 

Now that the database is created and we have a service claim configured
we will deploy the app workload to the TAP developer namespace.

1. Inspect the work load definition file at `runtime/tap/workload.yaml`
2. Check that the workload is pointing at your git repo of the sample api
3. Check that the service claim matches the service claim created earlier
4. You can apply the workload yaml using `kubectl` or the tanzu cli. Let's
   use the tanzu cli `tanzu app workload create -f runtime/tap/workload.yaml -n DEV-NAME-SPACE`
   for example my dev workspace is called `asaikali' so I use the command
   `tanzu app workload create -f runtime/tap/workload.yaml -n asaikali` which produces output
```text
Create workload:
      1 + |---
      2 + |apiVersion: carto.run/v1alpha1
      3 + |kind: Workload
      4 + |metadata:
      5 + |  labels:
      6 + |    app.kubernetes.io/part-of: sample-api
      7 + |    apps.tanzu.vmware.com/workload-type: web
      8 + |  name: sample-api
      9 + |  namespace: asaikali
     10 + |spec:
     11 + |  params:
     12 + |  - name: annotations
     13 + |    value:
     14 + |      autoscaling.knative.dev/minScale: "1"
     15 + |  serviceClaims:
     16 + |  - name: cloudsql-postgres
     17 + |    ref:
     18 + |      apiVersion: services.apps.tanzu.vmware.com/v1alpha1
     19 + |      kind: ResourceClaim
     20 + |      name: cloudsql-postgres-claim
     21 + |  source:
     22 + |    git:
     23 + |      ref:
     24 + |        branch: main
     25 + |      url: https://github.com/asaikali/sample-api-accelerator.git

? Do you want to create this workload? (y/N) 
```
5. Review the output for the workload creation and accept it. 
6. Check on the status of the newly submitted workload with the command 
   `tanzu app workload get sample-api -n asaikali` it will produce output similar to 
```text
# sample-api: Unknown
---
lastTransitionTime: "2022-05-10T05:13:52Z"
message: waiting to read value [.status.latestImage] from resource [image.kpack.io/sample-api]
  in namespace [asaikali]
reason: MissingValueAtPath
status: Unknown
type: Ready

Services
CLAIM               NAME                      KIND            API VERSION
cloudsql-postgres   cloudsql-postgres-claim   ResourceClaim   services.apps.tanzu.vmware.com/v1alpha1

Pods
NAME                           STATUS    RESTARTS   AGE
sample-api-build-1-build-pod   Pending   0          18s
```
7. It can take a few minutes for the workload to make its way through the TAP supply chain, you can 
   keep an eye on the workload using the command `tanzu app workload tail sample-api -n asaikali --since 1h`
   which will produce a very length log all the output from the steps in the supply chain.

8. Using the TAP GUI you can get a visualization of the progress of the workload through the supply chain, example
   output show below
   ![Supply chain](/docs/supply-chain.png?raw=true "Example Supply Chain")

9. Once you see that the supply chain has finished running you can get the URI of the of the app by running the 
   command  `tanzu app workload get sample-api -n asaikali` it will print out the url at the bottom of the output,
   as shown below 
```text
# sample-api: Ready
---
lastTransitionTime: "2022-05-10T05:15:35Z"
message: ""
reason: Ready
status: "True"
type: Ready

Services
CLAIM               NAME                      KIND            API VERSION
cloudsql-postgres   cloudsql-postgres-claim   ResourceClaim   services.apps.tanzu.vmware.com/v1alpha1

Pods
NAME                                           STATUS      RESTARTS   AGE
sample-api-00005-deployment-5997b4c6c6-f9pzf   Running     0          82s
sample-api-build-1-build-pod                   Succeeded   0          15m
sample-api-build-2-build-pod                   Succeeded   0          6m28s
sample-api-build-3-build-pod                   Succeeded   0          4m27s
sample-api-build-4-build-pod                   Succeeded   0          3m14s
sample-api-config-writer-8bld9-pod             Succeeded   0          114s
sample-api-config-writer-lr8vt-pod             Succeeded   0          13m
sample-api-config-writer-m9sxf-pod             Succeeded   0          5m32s
sample-api-config-writer-zskh4-pod             Succeeded   0          3m3s

Knative Services
NAME         READY   URL
sample-api   Ready   http://sample-api-asaikali.cnr.iterate.gcp.tanzu.ca
```
10. Visit the application at the printed url you will see rotating motivational quote similar to the screenshot below
    ![Supply chain](/docs/quote-app.png?raw=true "Example Supply Chain")

11. If you want you can connect to the postgres db from the gcp shell using the command
    `gcloud sql connect myinstance --user=postgres`  to get into the psql cli and inspect the database. Example output
```text
gcloud sql connect sample-api-db-hqvhc-2bv5p --user=postgres                                                                                                                                                                                                                                    
                                                                                                                                                                                                                                                                                      Allowlisting your IP for incoming connection for 5 minutes...done.Connecting to database with SQL user [postgres].Password:psql (14.2 (Debian 14.2-1.pgdg110+1), server 12.10)SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=> \dt
                 List of relations
 Schema |         Name          | Type  |  Owner
--------+-----------------------+-------+----------
 public | flyway_schema_history | table | postgres
 public | quotes                | table | postgres
(2 rows)

postgres=> select * from quotes;
 id |                 quote                 |        author
----+---------------------------------------+-----------------------
  1 | Never, never, never give up           | Winston Churchill
  2 | While there's life, there's hope      | Marcus Tullius Cicero
  3 | Failure is success in progress        | Anonymous
  4 | Success demands singleness of purpose | Vincent Lombardi
  5 | The shortest answer is doing          | Lord Herbert
(5 rows)

postgres=>
```

# View App in TAP GUI Software Catalog 

TAP user portal is built on top of the [backstage](https://backstage.io/) which is centered on the idea of a [software
catalog](https://backstage.io/docs/features/software-catalog/software-catalog-overview) that contains 
a model of the organizational structure and software domains, systems, components, resources, apis's you can read more 
about it at on the backstage docs at [System Model](https://backstage.io/docs/features/software-catalog/system-model)
Diagram belows shows the backstage structure
[![Software Model](docs/software-model-entities.drawio.svg)]

## Register the app in the backstage catalog

1. Inspect the catalog definition file at `runtime/tap/catalog-info.yaml` it contains the metadata about the application
   that should be stored in the software catalog.
```text
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: sample-api
  description: Example API using Spring Boot
  tags:
    - java
    - spring
    - api
    - tanzu
  annotations:
    'backstage.io/kubernetes-label-selector': 'app.kubernetes.io/part-of=sample-api'
spec:
  type: service
  lifecycle: experimental
  owner: default-team
```
2. Login to the TAP gui and register the catalog by clicking the register button and setting the url to the 
   `catalog-info.yaml` file such as `https://github.com/asaikali/sample-api-accelerator/blob/main/runtime/tap/catalog-info.yaml`
3. Once the App is registered can see it on the software catalog user interface 
4. Click on the componet explore the UI 
5. make sure to navigate to the runtime tab and see the knative service and app live view
   ![Runtime View](/docs/runtimeview.png?raw=true "Runtime view")