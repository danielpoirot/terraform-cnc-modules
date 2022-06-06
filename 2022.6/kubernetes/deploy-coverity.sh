#!/usr/bin/env bash

set -xv
set -euo pipefail


COVERITY_APP_NAME=${COVERITY_APP_NAME:-"coverity-example"}
COVERITY_CHART_LOCATION=${COVERITY_CHART_LOCATION:-sig-repo/cnc}

COVERITY_ANALYSIS_NODE_NAME=${COVERITY_ANALYSIS_NODE_NAME:-""}
COVERITY_ANALYSIS_NODE_LABEL=${COVERITY_ANALYSIS_NODE_LABEL:-"coverity-custom-node-pool-label"}

COVERITY_NS=${COVERITY_NS:-"coverity"}
COVERITY_LICENSE_SECRET_NAME="${COVERITY_APP_NAME}-license"
COVERITY_HOST=${COVERITY_HOST:-"coverity.example"}
COVERITY_TLS_SECRET_NAME="coverity-tls"
COVERITY_S3_SECRET_NAME="coverity-s3"

MINIO_COVERITY_BUCKET_NAME="${COVERITY_NS}-uploads-bucket"
MINIO_ROOT_USER=${MINIO_ROOT_USER:-"admin"}
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-"synopsys"}


kubectl create ns "$COVERITY_NS" || true


helm upgrade --install "cim-pg" postgresql \
  --repo https://charts.bitnami.com/bitnami \
  --namespace "$COVERITY_NS" \
  --version "10.16.2" \
  --set metrics.enabled=true \
  --set postgresqlDatabase=cim \
  -f postgres-values.yaml

# need to wait a few seconds, otherwise you might see an "error: no matching resources found" failure
sleep 5

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=postgresql \
  --namespace "$COVERITY_NS" \
  --timeout=10m


# label node for job farm
if [[ $COVERITY_ANALYSIS_NODE_NAME == "" ]]; then
  # get first node
  COVERITY_ANALYSIS_NODE_NAME=$(kubectl get nodes -o=jsonpath='{.items[0].metadata.name}')
fi

pool_type=$(kubectl get nodes "$COVERITY_ANALYSIS_NODE_NAME" -o=jsonpath='{.metadata.labels.pool-type}')
if [ "${pool_type}" != "${COVERITY_ANALYSIS_NODE_LABEL}" ]; then
  kubectl label nodes --overwrite "$COVERITY_ANALYSIS_NODE_NAME" pool-type="${COVERITY_ANALYSIS_NODE_LABEL}"
  echo "verifying job farm kube node label -- $(kubectl get nodes "$COVERITY_ANALYSIS_NODE_NAME" -o=jsonpath='{.metadata.labels.pool-type}')"
fi


helm upgrade --install "coverity-minio" minio \
  --repo https://charts.bitnami.com/bitnami \
  --version 10.1.4 \
  --debug \
  --namespace "$COVERITY_NS" \
  --set defaultBuckets="${MINIO_COVERITY_BUCKET_NAME}" \
  --set auth.rootUser="${MINIO_ROOT_USER}" \
  --set auth.rootPassword="${MINIO_ROOT_PASSWORD}" \
  -f minio-values.yaml


kubectl create secret generic "${COVERITY_S3_SECRET_NAME}" \
  --from-literal=aws_access_key="${MINIO_ROOT_USER}" \
  --from-literal=aws_secret_key="${MINIO_ROOT_PASSWORD}" \
  --namespace "${COVERITY_NS}" \
  -o yaml --dry-run=client | kubectl apply -f -

kubectl create secret generic "$COVERITY_LICENSE_SECRET_NAME" \
  --namespace "$COVERITY_NS" \
  --from-file=license.dat \
  -o yaml --dry-run=client | kubectl apply -f -

kubectl create secret tls "$COVERITY_TLS_SECRET_NAME" \
  --namespace "$COVERITY_NS" \
  --cert=tls.crt \
  --key=tls.key \
  -o yaml --dry-run=client | kubectl apply -f -


helm install "$COVERITY_APP_NAME" "${COVERITY_CHART_LOCATION}" \
  --wait \
  --timeout 60m0s \
  --debug \
  --namespace "$COVERITY_NS" \
  --set cnc-storage-service.s3.bucket="${COVERITY_NS}-uploads-bucket" \
  --set "licenseSecretName=${COVERITY_LICENSE_SECRET_NAME}" \
  --set "cnc-storage-service.s3.secret.name=$COVERITY_S3_SECRET_NAME" \
  --set "cim.cimweb.webUrl=https://${COVERITY_HOST}:443" \
  --set "cnc-processor-loader.environment.CUSTOMNODEPOOL_LABEL=${COVERITY_ANALYSIS_NODE_LABEL}" \
  --set "cnc-processor-loader.environment.COVANALYSIS_DEFAULTPOOLTYPE=${COVERITY_ANALYSIS_NODE_LABEL}" \
  --set "licenseSecretName=${COVERITY_LICENSE_SECRET_NAME}" \
  -f coverity-values.yaml \
  "$@"
