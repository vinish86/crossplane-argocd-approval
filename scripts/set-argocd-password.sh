#!/bin/bash

# Script to set custom ArgoCD admin password

set -e

# Colors
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "🔑 Set Custom ArgoCD Admin Password"
echo "===================================="
echo ""

# Check if password is provided
if [ -z "$1" ]; then
  echo "${YELLOW}Usage: $0 <new-password>${NC}"
  echo ""
  echo "Example: $0 MySecurePassword123!"
  echo ""
  echo "Or set via environment variable:"
  echo "  ARGOCD_PASSWORD=MySecurePassword123! $0"
  exit 1
fi

NEW_PASSWORD="${1:-$ARGOCD_PASSWORD}"

if [ -z "$NEW_PASSWORD" ]; then
  echo "${RED}Error: Password not provided${NC}"
  exit 1
fi

echo "${YELLOW}Checking ArgoCD installation...${NC}"

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &>/dev/null; then
  echo "${RED}Error: ArgoCD namespace not found. Please install ArgoCD first.${NC}"
  exit 1
fi

# Get current password
echo "${YELLOW}Getting current ArgoCD password...${NC}"
CURRENT_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -z "$CURRENT_PASSWORD" ]; then
  echo "${YELLOW}Initial password secret not found. Trying to use argocd CLI to update...${NC}"
  
  # Check if argocd CLI is installed
  if ! command -v argocd &> /dev/null; then
    echo "${RED}Error: argocd CLI not found. Please install it:${NC}"
    echo "  brew install argocd"
    echo "  or visit: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
    exit 1
  fi
  
  # Prompt for current password
  echo ""
  echo "Please enter your current ArgoCD admin password:"
  read -s CURRENT_PASSWORD
  echo ""
fi

echo "${YELLOW}Updating password via argocd CLI...${NC}"

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
  echo "${YELLOW}Installing argocd CLI...${NC}"
  echo ""
  echo "${RED}argocd CLI not found. Please install it first:${NC}"
  echo ""
  echo "macOS:"
  echo "  brew install argocd"
  echo ""
  echo "Linux:"
  echo "  curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
  echo "  chmod +x argocd"
  echo "  sudo mv argocd /usr/local/bin/"
  echo ""
  echo "Or visit: https://argo-cd.readthedocs.io/en/stable/cli_installation/"
  echo ""
  echo "${YELLOW}Alternative: Use kubectl to set password hash${NC}"
  echo ""
  echo "If you have htpasswd installed:"
  echo "  HASH=\$(htpasswd -nbBC 10 \"\" \"$NEW_PASSWORD\" | tr -d ':\\n' | sed 's/\$2y/\$2a/')"
  echo "  kubectl -n argocd patch secret argocd-secret -p '{\"stringData\": {\"admin.password\": \"'\$HASH'\", \"admin.passwordMtime\": \"'$(date +%FT%T%Z)'\"}}'"
  exit 1
fi

# Port-forward if not already running
if ! lsof -i :8080 &>/dev/null; then
  echo "${YELLOW}Starting port-forward...${NC}"
  kubectl port-forward svc/argocd-server -n argocd 8080:443 > /tmp/argocd-port-forward.log 2>&1 &
  sleep 3
fi

# Login and update password
echo "${YELLOW}Logging in to ArgoCD...${NC}"
argocd login localhost:8080 --username admin --password "$CURRENT_PASSWORD" --insecure

echo "${YELLOW}Updating password...${NC}"
argocd account update-password --current-password "$CURRENT_PASSWORD" --new-password "$NEW_PASSWORD"

echo ""
echo "${GREEN}✅ Password updated successfully!${NC}"
echo ""
echo "New ArgoCD credentials:"
echo "  URL: https://localhost:8080"
echo "  Username: admin"
echo "  Password: $NEW_PASSWORD"
echo ""
echo "${YELLOW}Note: The password is now stored in argocd-secret ConfigMap${NC}"
echo "      Initial password secret is no longer used."

