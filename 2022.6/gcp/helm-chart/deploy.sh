#!/usr/bin/env bash

set -xv
set -euo pipefail

cat << EOF
This script is unsupported; it is provided only as a reference.
There are many ways to deploy Coverity; this merely demonstrates one possible method.
This helm deploy script is specific to infra deployed through this project.  It will not work with different infra.
If deploying to different infra, you will have to modify this script.
Users of this script must be familiar with the details of their infra in order to modify this script correctly.
Any modifications to this script will also not be supported.
EOF


# Required variables:
# COVERITY_CLUSTER_NAME
# COVERITY_CLUSTER_REGION
# COVERITY_GCS_BUCKET_NAME
# COVERITY_PGHOST
# COVERITY_PGPASSWORD
# COVERITY_PGUSER
# GCP_PROJECT_ID
# COVERITY_GCS_SERVICE_ACCOUNT_FILE
# COVERITY_CACHE_BUCKET_NAME
# COVERITY_REDIS_HOST
# COVERITY_REDIS_PORT
# COVERITY_REDIS_CA_CERT_FILE
#
# COVERITY_NS
#
# COVERITY_CHART
# COVERITY_CHART_VERSION
#
# COVERITY_LICENSE_PATH


COVERITY_GCS_SA_SECRET_NAME="coverity-gcs-credentials"
COVERITY_GCS_SA_SECRET_KEY="key.json"
COVERITY_INGRESS_SECRET_NAME="coverity-ingress"
COVERITY_LICENSE_SECRET_NAME="coverity-license"
COVERITY_REDIS_CA_CERT_SECRET_NAME="coverity-redis-cert"
COVERITY_REDIS_PASSWORD_SECRET_NAME="coverity-redis-password"
COVERITY_REDIS_PASSWORD=""


## Make sure your kubectl is pointing at the gcp cluster
gcloud container clusters get-credentials "${COVERITY_CLUSTER_NAME}" --region "${COVERITY_CLUSTER_REGION}" --project "${GCP_PROJECT_ID}"
kubectl config set-context $(kubectl config get-contexts | grep "^\*" | awk '{print $2}') --namespace "${COVERITY_NS}"
kubectl config get-contexts


kubectl create ns "${COVERITY_NS}" || true

kubectl create secret tls "$COVERITY_INGRESS_SECRET_NAME" \
  --namespace "$COVERITY_NS" \
  --cert=../../kubernetes/tls.crt \
  --key=../../kubernetes/tls.key \
  -o yaml --dry-run=client | kubectl apply -f -


kubectl create secret generic "${COVERITY_LICENSE_SECRET_NAME}" \
  --from-file=license.dat="${COVERITY_LICENSE_PATH}" --namespace "${COVERITY_NS}" \
  --dry-run -o yaml | kubectl apply -f -

kubectl create secret generic "${COVERITY_GCS_SA_SECRET_NAME}" \
  --from-file=${COVERITY_GCS_SA_SECRET_KEY}="${COVERITY_GCS_SERVICE_ACCOUNT_FILE}" --namespace "${COVERITY_NS}" \
  --dry-run -o yaml | kubectl apply -f -

kubectl create secret generic "${COVERITY_REDIS_CA_CERT_SECRET_NAME}" \
  --from-file=ca.crt="${COVERITY_REDIS_CA_CERT_FILE}" --namespace "${COVERITY_NS}" \
  --dry-run -o yaml | kubectl apply -f -

kubectl create secret generic "${COVERITY_REDIS_PASSWORD_SECRET_NAME}" \
  --from-literal=password="${COVERITY_REDIS_PASSWORD}" --namespace "${COVERITY_NS}" \
  --dry-run -o yaml | kubectl apply -f -

echo -e "\n===> Successfully created prerequisites for Coverity Helm Chart.\n"

echo -e "\n===> Deploying Coverity Helm Chart...\n"

helm upgrade "${COVERITY_NS}" "${COVERITY_CHART}" \
  --install \
  --version "${COVERITY_CHART_VERSION}" \
  --debug \
  --wait \
  --timeout 15m0s \
  --namespace "${COVERITY_NS}" \
  --set licenseSecretName="${COVERITY_LICENSE_SECRET_NAME}" \
  --set postgres.user="${COVERITY_PGUSER}" \
  --set postgres.password="${COVERITY_PGPASSWORD}" \
  --set postgres.host="${COVERITY_PGHOST}" \
  --set cnc-storage-service.gcs.bucket="${COVERITY_GCS_BUCKET_NAME}" \
  --set cnc-storage-service.gcs.secret.name="${COVERITY_GCS_SA_SECRET_NAME}" \
  --set cnc-storage-service.gcs.secret.key="${COVERITY_GCS_SA_SECRET_KEY}" \
  --set cnc-cache-service.bucketName="${COVERITY_CACHE_BUCKET_NAME}" \
  --set cnc-cache-service.gcp.project="${GCP_PROJECT_ID}" \
  --set cnc-cache-service.gcp.secret="${COVERITY_GCS_SA_SECRET_NAME}" \
  --set cnc-cache-service.redis.host="${COVERITY_REDIS_HOST}" \
  --set cnc-cache-service.redis.port="${COVERITY_REDIS_PORT}" \
  --set cnc-cache-service.redis.cacertSecret="${COVERITY_REDIS_CA_CERT_SECRET_NAME}" \
  --set cnc-cache-service.redis.passwordSecret="${COVERITY_REDIS_PASSWORD_SECRET_NAME}" \
  -f values.yaml \
  "$@"

echo -e "\n===> Successfully deployed Coverity Helm Chart.\n"
