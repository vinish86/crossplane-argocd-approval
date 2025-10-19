#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔐 ArgoCD Password Configuration"
echo "==============================="

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &> /dev/null; then
  echo "${RED}❌ ArgoCD namespace 'argocd' not found. Please install ArgoCD first.${NC}"
  exit 1
fi

# Check if ArgoCD server is ready
if ! kubectl wait --for=condition=available --timeout=10s deployment/argocd-server -n argocd &> /dev/null; then
  echo "${RED}❌ ArgoCD server is not ready. Please check your ArgoCD installation.${NC}"
  exit 1
fi

# Get password from argument or prompt
if [ $# -eq 1 ]; then
  NEW_PASSWORD="$1"
  echo "Setting password from command line argument..."
else
  echo ""
  echo "Enter your desired ArgoCD admin password:"
  read -s NEW_PASSWORD
  echo ""
  echo "Confirm password:"
  read -s CONFIRM_PASSWORD
  echo ""
  
  if [ "$NEW_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
    echo "${RED}❌ Passwords don't match. Exiting.${NC}"
    exit 1
  fi
fi

if [ -z "$NEW_PASSWORD" ]; then
  echo "${RED}❌ Password cannot be empty.${NC}"
  exit 1
fi

echo ""
echo "${YELLOW}Setting ArgoCD admin password...${NC}"

# Wait for ArgoCD to be fully ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=60s deployment/argocd-server -n argocd

# Get initial password
echo "Getting initial admin password..."
INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -z "$INITIAL_PASSWORD" ]; then
  echo "${YELLOW}⚠️  Waiting for initial password secret...${NC}"
  sleep 10
  INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
fi

if [ -z "$INITIAL_PASSWORD" ]; then
  echo "${RED}❌ Could not get initial password secret. Please check ArgoCD installation.${NC}"
  exit 1
fi

echo "Initial password retrieved successfully."

# Check if htpasswd is available
if ! command -v htpasswd &> /dev/null; then
  echo "${RED}❌ htpasswd command not found.${NC}"
  echo ""
  echo "Please install htpasswd:"
  echo "  macOS: brew install httpd"
  echo "  Ubuntu/Debian: sudo apt-get install apache2-utils"
  echo "  CentOS/RHEL: sudo yum install httpd-tools"
  echo ""
  echo "Then run this script again."
  exit 1
fi

# Generate bcrypt hash
echo "Generating password hash..."
BCRYPT_HASH=$(htpasswd -nbBC 10 "" "$NEW_PASSWORD" 2>/dev/null | tr -d ':\n' | sed 's/\$2y/\$2a/' || echo "")

if [ -z "$BCRYPT_HASH" ]; then
  echo "${RED}❌ Failed to generate password hash.${NC}"
  exit 1
fi

# Update ArgoCD secret
echo "Updating ArgoCD admin password..."
kubectl -n argocd patch secret argocd-secret \
  --type='merge' \
  -p="{\"stringData\": {\"admin.password\": \"$BCRYPT_HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"

# Restart ArgoCD server to pick up new password
echo "Restarting ArgoCD server..."
kubectl rollout restart deployment argocd-server -n argocd

echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment argocd-server -n argocd

echo ""
echo "${GREEN}✅ ArgoCD admin password updated successfully!${NC}"
echo ""
echo "ArgoCD Login Credentials:"
echo "  URL: https://localhost:8080"
echo "  Username: admin"
echo "  Password: $NEW_PASSWORD"
echo ""
echo "To access ArgoCD UI:"
echo "  1. Port-forward: ./scripts/port-forward.sh"
echo "  2. Open: https://localhost:8080"
echo "  3. Login with the credentials above"
