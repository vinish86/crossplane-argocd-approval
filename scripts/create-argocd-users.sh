#!/bin/bash

# Script to create and configure ArgoCD approver and reader users
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "${YELLOW}Creating ArgoCD Users (approver & reader)${NC}"
echo "=========================================="
echo ""

# Check if argocd CLI is installed
if ! command -v argocd &> /dev/null; then
  echo "${RED}Error: argocd CLI not found. Please install it:${NC}"
  echo ""
  echo "macOS: brew install argocd"
  echo "Linux: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
  echo "       chmod +x argocd && sudo mv argocd /usr/local/bin/"
  echo ""
  exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Apply the configuration
echo "${YELLOW}Applying ArgoCD users configuration...${NC}"
kubectl apply -f "$PROJECT_DIR/manifests/01-argocd/argocd-users.yaml"

echo ""
echo "${YELLOW}Restarting ArgoCD server to pick up new accounts...${NC}"
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=2m

echo ""
echo "${YELLOW}Waiting for accounts to be available...${NC}"
sleep 10

# Port-forward management
echo "${YELLOW}Checking port-forward...${NC}"
PF_STARTED=false

# Check if port-forward is actually working (not just port in use)
if curl -k https://localhost:8080 &>/dev/null || curl -k https://localhost:8080/healthz &>/dev/null; then
  echo "${GREEN}✅ Port-forward already running and responding${NC}"
else
  echo "${YELLOW}Starting port-forward...${NC}"
  # Kill any stale process on port 8080
  lsof -ti :8080 | xargs kill -9 2>/dev/null || true
  sleep 1
  
  # Start new port-forward
  kubectl port-forward svc/argocd-server -n argocd 8080:443 > /tmp/argocd-port-forward.log 2>&1 &
  PF_PID=$!
  PF_STARTED=true
  
  # Wait and verify it's responding
  sleep 5
  if ! curl -k https://localhost:8080 &>/dev/null; then
    echo "${RED}Error: Port-forward not responding${NC}"
    echo "Try running manually: ./scripts/port-forward.sh"
    exit 1
  fi
  echo "${GREEN}✅ Port-forward started and responding${NC}"
fi

# Get admin password
echo ""
echo "${YELLOW}Admin Password Required${NC}"
echo "======================="
echo ""

# Try to get initial password first
INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -n "$INITIAL_PASSWORD" ]; then
  echo "Found initial admin password. Try using it first."
  echo ""
  read -p "Use initial password? (Y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    ADMIN_PASSWORD="$INITIAL_PASSWORD"
  else
    echo ""
    echo "Enter your current admin password:"
    read -s ADMIN_PASSWORD
    echo ""
  fi
else
  echo "Initial password not found (might have been changed)."
  echo ""
  echo "Enter your current admin password:"
  read -s ADMIN_PASSWORD
  echo ""
fi

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "${RED}No password provided!${NC}"
  exit 1
fi

# Login as admin
echo "${YELLOW}Logging in as admin...${NC}"
argocd login localhost:8080 --username admin --password "$ADMIN_PASSWORD" --insecure

# Use admin password for both users (same password as admin)
USER_PASSWORD="$ADMIN_PASSWORD"

echo ""
echo "${YELLOW}Setting password for 'approver' user...${NC}"
argocd account update-password \
  --account approver \
  --current-password "$ADMIN_PASSWORD" \
  --new-password "$USER_PASSWORD" || {
    echo "${RED}Failed to set approver password. Account may not be ready yet.${NC}"
    exit 1
  }

echo ""
echo "${YELLOW}Setting password for 'reader' user...${NC}"
argocd account update-password \
  --account reader \
  --current-password "$ADMIN_PASSWORD" \
  --new-password "$USER_PASSWORD" || {
    echo "${RED}Failed to set reader password. Account may not be ready yet.${NC}"
    exit 1
  }

echo ""
echo "${GREEN}✅ Users created successfully!${NC}"
echo ""
echo "User Credentials (all use the same password as admin):"
echo "=========================================================="
echo ""
echo "Admin User:"
echo "  URL: https://localhost:8080"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "Approver User (can view & approve changes):"
echo "  URL: https://localhost:8080"
echo "  Username: approver"
echo "  Password: $USER_PASSWORD"
echo ""
echo "Reader User (can only view, no approve):"
echo "  URL: https://localhost:8080"
echo "  Username: reader"
echo "  Password: $USER_PASSWORD"
echo ""
echo "${YELLOW}User Permissions:${NC}"
echo "  - admin: Full access to everything"
echo "  - approver: Can view applications and approve changes"
echo "  - reader: Can only view applications (no approvals)"
echo ""

# Cleanup: Kill port-forward if we started it
if [ "$PF_STARTED" = true ]; then
  echo ""
  echo "${YELLOW}Cleaning up port-forward...${NC}"
  if [ -n "$PF_PID" ] && ps -p $PF_PID > /dev/null 2>&1; then
    kill $PF_PID 2>/dev/null || true
    echo "${GREEN}✅ Port-forward stopped${NC}"
  else
    echo "${YELLOW}Port-forward already stopped${NC}"
  fi
  echo ""
  echo "${YELLOW}💡 To access ArgoCD UI, run: ./scripts/port-forward.sh${NC}"
  echo ""
fi

