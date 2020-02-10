#!/bin/bash

source utils.sh

export DT_TENANT=$(cat creds.json | jq -r '.dynatraceTenant')
export DT_API_TOKEN=$(cat creds.json | jq -r '.dynatraceApiToken')
export DT_PAAS_TOKEN=$(cat creds.json | jq -r '.dynatracePaasToken')
export DT_TENANT_URL="https://$DT_TENANT"

#kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)

# Deploy Dynatrace operator
DT_OPERATOR_LATEST_RELEASE=$(curl -s https://api.github.com/repos/dynatrace/dynatrace-oneagent-operator/releases/latest | grep tag_name | cut -d '"' -f 4)
print_info "Installing Dynatrace Operator $DT_OPERATOR_LATEST_RELEASE"

kubectl create namespace dynatrace
verify_kubectl $? "Creating namespace dynatrace for oneagent operator failed."

kubectl label namespace dynatrace istio-injection=disabled

kubectl apply -f https://raw.githubusercontent.com/Dynatrace/dynatrace-oneagent-operator/$DT_OPERATOR_LATEST_RELEASE/deploy/kubernetes.yaml
verify_kubectl $? "Applying Dynatrace operator failed."
wait_for_crds "oneagent"

# Create Dynatrace secret
kubectl -n dynatrace create secret generic oneagent --from-literal="apiToken=$DT_API_TOKEN" --from-literal="paasToken=$DT_PAAS_TOKEN"
verify_kubectl $? "Creating secret for Dynatrace OneAgent failed."

# Create Dynatrace OneAgent
rm -f manifests-dynatrace/gen/cr.yml
rm -f manifests-dynatrace/cr.yml

mkdir -p manifests-dynatrace/gen/

curl -o manifests-dynatrace/gen/cr.yml https://raw.githubusercontent.com/Dynatrace/dynatrace-oneagent-operator/$DT_OPERATOR_LATEST_RELEASE/deploy/cr.yaml
cat manifests-dynatrace/gen/cr.yml | sed 's~ENVIRONMENTID.live.dynatrace.com~'"$DT_TENANT"'~' >> manifests-dynatrace/gen/cr.yml

kubectl apply -f manifests-dynatrace/gen/cr.yml
verify_kubectl $? "Deploying Dynatrace OneAgent failed."
