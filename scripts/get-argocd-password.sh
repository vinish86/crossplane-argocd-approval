#!/bin/bash

echo "ArgoCD Login Credentials"
echo "========================"
echo ""
echo "URL: https://localhost:8080"
echo "Username: admin"
echo -n "Password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d
echo ""
echo ""
echo "To access ArgoCD UI, make sure port-forwarding is running:"
echo "./scripts/port-forward.sh"
