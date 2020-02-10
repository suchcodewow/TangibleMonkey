#!/bin/bash

echo "Creating Namespaces"
kubectl create -f yml/k8s-namespaces.yml

echo "Create SSD Storage for kubernetes cluster"
kubectl create -f yml/k8s-storage.yml

echo "Creating DB for SockShop"
kubectl create -f yml/carts-db.yaml

echo "Creating interface for SockShop"
kubectl create -f yml/carts.yml


