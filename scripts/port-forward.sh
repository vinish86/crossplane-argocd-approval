#!/bin/bash

echo "Starting port-forward to ArgoCD..."
echo "Access ArgoCD at: https://localhost:8080"
echo ""
echo "Press Ctrl+C to stop"
echo ""

kubectl port-forward svc/argocd-server -n argocd 8080:443
