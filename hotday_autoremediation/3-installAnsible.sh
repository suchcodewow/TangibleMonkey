#!/bin/bash

#This script installs Ansible Tower in the tower namespace. It also configures AT for the ACL.
#Note: there are some comments in here for echoing, these are for debugging purposes

YLW='\033[1;33m'
NC='\033[0m'
GRN='\033[0;32m'
RED='\033[0;31m'

export CART_URL=$(kubectl describe svc carts -n production | grep "LoadBalancer Ingress:" | sed 's/LoadBalancer Ingress:[ \t]*//')
if [ "$CART_URL" == "" ]; then
    echo "Service for carts in the production namespace could not be found. Please make sure the service has been deployed."
    exit 1
fi
echo -e "${YLW}Carts URL: http://$CART_URL/carts${NC}"

echo -e "\nCreating Ansible Tower Namespace..."
kubectl create -f manifests-ansible-tower/ns.yml
echo -e "Creating Ansible Tower Deployment..."
kubectl create -f manifests-ansible-tower/dep.yml
echo -e "Creating Ansible Tower Service..."
kubectl create -f manifests-ansible-tower/svc.yml

echo -e "${YLW}\nWaiting for the Ansible Tower deployment${NC}"
while [[ $(kubectl get pods -l app=ansible-tower -n tower -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for the ansible tower deployment to finalize..." && sleep 7; done

while [[ $(kubectl get svc -n tower -l app=ansible-tower -o 'jsonpath={..status.loadBalancer.ingress..ip}') == "" ]]; do echo "waiting for the tower load balancer service public IP address" && sleep 3; done 

export JENKINS_USER=$(cat creds.json | jq -r '.jenkinsUser')
export JENKINS_PASSWORD=$(cat creds.json | jq -r '.jenkinsPassword')
export DOCS_ORG=$(cat creds.json | jq -r '.docsOrg')
export DOCS_REPO=$(cat creds.json | jq -r '.docsRepo')
export DOCS_BRANCH=$(cat creds.json | jq -r '.docsBranch')
export GITHUB_PERSONAL_ACCESS_TOKEN=$(cat creds.json | jq -r '.githubPersonalAccessToken')
export GITHUB_USER_NAME=$(cat creds.json | jq -r '.githubUserName')
export GITHUB_USER_EMAIL=$(cat creds.json | jq -r '.githubUserEmail')
export DT_TENANT=$(cat creds.json | jq -r '.dynatraceTenant')
export DT_API_TOKEN=$(cat creds.json | jq -r '.dynatraceApiToken')
export GITHUB_ORGANIZATION=$(cat creds.json | jq -r '.githubOrg')

export TOWER_URL=$(kubectl describe svc ansible-tower -n tower | grep "LoadBalancer Ingress:" | sed 's/LoadBalancer Ingress:[ \t]*//')

echo -e "${YLW}\nTower URL:  https://$TOWER_URL${NC}"

echo -e "Creating Dynatrace API Credential Type..."
export DTAPICREDTYPE=$(curl -s -k -X POST https://$TOWER_URL/api/v2/credential_types/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "dt-api",
  "kind": "cloud",
  "description" :"Dynatrace API Authentication Token",
  "inputs": { "fields": [ { "secret": true, "type": "string", "id": "dt_api_token", "label": "Dynatrace API Token" } ], "required": ["dt_api_token"]}, "injectors": { "extra_vars": { "DYNATRACE_API_TOKEN": "{{dt_api_token}}" } }
}' | jq -r '.id')
#echo "DTAPICREDTYPE: " $DTAPICREDTYPE

echo -e "Creating Dynatrace API Credential for '$DT_TENANT'..."
export DTCRED=$(curl -s -k -X POST https://$TOWER_URL/api/v2/credentials/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "'$DT_TENANT' API token",
  "credential_type": '$DTAPICREDTYPE',
  "organization": 1,
  "inputs": { "dt_api_token": "'$DT_API_TOKEN'" }
}' | jq -r '.id')
#echo "DTCRED: " $DTCRED

echo -e "Creating Git Credential for '$GITHUB_USER_NAME'..."
export GITCRED=$(curl -s -k -X POST https://$TOWER_URL/api/v1/credentials/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "'$GITHUB_USER_NAME' git credential",
  "kind": "scm",
  "user": 1,
  "username": "'$GITHUB_USER_NAME'",
  "password": "'$GITHUB_PERSONAL_ACCESS_TOKEN'"
}' | jq -r '.id')
#echo "GITCRED: " $GITCRED

echo -e "Creating Project..."
export PROJECT_ID=$(curl -s -k -X POST https://$TOWER_URL/api/v1/projects/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "self-healing",
  "scm_type": "git",
  "scm_url": "https://github.com/'$DOCS_ORG'/'$DOCS_REPO'",
  "scm_branch": "'$DOCS_BRANCH'",
  "credential": '$GITCRED',
  "scm_clean": "true"
}' | jq -r '.id')
echo "PROJECT_ID: " $PROJECT_ID

echo -e "${YLW}\nWaiting for project to initialize${NC}"

while [[ $(curl --max-time 5 -s -k -L -X GET https://$TOWER_URL/api/v1/projects/$PROJECT_ID --user admin:dynatrace | jq .status -r) != "successful" ]]; do echo "waiting for project..." && sleep 7; done

echo -e "${YLW}\nProject URL: https://$TOWER_URL/api/v1/projects/$PROJECT_ID${NC}"

echo -e "\nCreating Inventory for common variables..."
export INVENTORY_ID=$(curl -s -k -X POST https://$TOWER_URL/api/v1/inventories/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "inventory",
  "type": "inventory",
  "organization": 1,
  "variables": "---\ntenant: \"'$DT_TENANT'\"\ncarts_promotion_url: \"http://'$CART_URL'/carts/1/items/promotion\"\ncommentuser: \"Ansible Playbook\"\ntower_user: \"admin\"\ntower_password: \"dynatrace\"\ndtcommentapiurl: \"https://{{tenant}}/api/v1/problem/details/{{pid}}/comments?Api-Token={{DYNATRACE_API_TOKEN}}\"\ndteventapiurl: \"https://{{tenant}}/api/v1/events/?Api-Token={{DYNATRACE_API_TOKEN}}\""
}' | jq -r '.id')
echo "INVENTORY_ID: " $INVENTORY_ID

echo -e "Creating Job Template for remediation action..."
export REMEDIATION_TEMPLATE_ID=$(curl -s -k -X POST https://$TOWER_URL/api/v1/job_templates/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "remediation",
  "job_type": "run",
  "inventory": '$INVENTORY_ID',
  "project": '$PROJECT_ID',
  "playbook": "remediation.yaml",
  "ask_variables_on_launch": true
}' | jq -r '.id')
echo "REMEDIATION_TEMPLATE_ID: " $REMEDIATION_TEMPLATE_ID

echo -e "Creating Job Template for stopping the campaign..."
export STOP_CAMPAIGN_ID=$(($REMEDIATION_TEMPLATE_ID + 1))
export STOP_CAMPAIGN_ID=$(curl -s -k -X POST https://$TOWER_URL/api/v1/job_templates/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "stop-campaign",
  "job_type": "run",
  "inventory": '$INVENTORY_ID',
  "project": '$PROJECT_ID',
  "playbook": "campaign.yaml",
  "extra_vars": "---\npromotion_rate: \"0\"\nremediation_action: \"https://'$TOWER_URL'/api/v2/job_templates/'$STOP_CAMPAIGN_ID'/launch/\"\ndt_application: \"carts\"\ndt_environment: \"production\""
}' | jq -r '.id')
echo "STOP_CAMPAIGN_ID: " $STOP_CAMPAIGN_ID

echo -e "Creating Job Template for starting the campaign..."
export START_CAMPAIGN_ID=$(curl -s -k -X POST https://$TOWER_URL/api/v1/job_templates/ --user admin:dynatrace -H "Content-Type: application/json" \
--data '{
  "name": "start-campaign",
  "job_type": "run",
  "inventory": '$INVENTORY_ID',
  "project": '$PROJECT_ID',
  "playbook": "campaign.yaml",
  "extra_vars": "---\npromotion_rate: \"0\"\nremediation_action: \"https://'$TOWER_URL'/api/v2/job_templates/'$STOP_CAMPAIGN_ID'/launch/\"\ndt_application: \"carts\"\ndt_environment: \"production\"",
  "ask_variables_on_launch": true
}' | jq -r '.id')
#echo "START_CAMPAIGN_ID: " $START_CAMPAIGN_ID

#Assign DT API credential to all jobs
declare -a job_templates=($REMEDIATION_TEMPLATE_ID $STOP_CAMPAIGN_ID $START_CAMPAIGN_ID)

for template in "${job_templates[@]}"
do
  curl -k -X POST https://$TOWER_URL/api/v2/job_templates/$template/credentials/ --user admin:dynatrace -H "Content-Type: application/json" \
  --data '{
    "id": '$DTCRED'
  }'
done

if [ -z $REMEDIATION_TEMPLATE_ID ]
    then
    echo -e "${RED}Failed to deploy ansible tower${NC}"
    echo -e "${RED}Deleting ansible tower namespace${NC}"
    kubectl delete ns tower
    echo -e "${RED}Please ensure all required values are provided  ${NC}"    
    exit 1
else
    echo -e "${GRN}\n\nAnsible has been configured successfully! Copy the following URL to set it as an Ansible Job URL in the Dynatrace notification settings:${NC}"
    echo -e "${GRN}https://$TOWER_URL/#/templates/job_template/$REMEDIATION_TEMPLATE_ID${NC}\n"
    exit 0
fi
