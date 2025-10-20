#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "👥 ArgoCD User Management"
echo "========================"

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

# Check if ArgoCD CLI is available
if ! command -v argocd &> /dev/null; then
  echo "${RED}❌ ArgoCD CLI not found.${NC}"
  echo ""
  echo "Please install ArgoCD CLI:"
  echo "  macOS: brew install argocd"
  echo "  Linux: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
  echo "         chmod +x argocd && sudo mv argocd /usr/local/bin/"
  echo ""
  exit 1
else
  echo "${GREEN}✅ ArgoCD CLI is available${NC}"
fi

echo "${GREEN}✅ ArgoCD is installed and ready${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Get admin password (can be passed as argument or prompted)
ADMIN_PASSWORD="$1"

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "Please enter the current ArgoCD admin password:"
  read -s ADMIN_PASSWORD
  echo ""
  
  if [ -z "$ADMIN_PASSWORD" ]; then
    echo "${RED}❌ Admin password is required to create users.${NC}"
    exit 1
  fi
else
  echo "${GREEN}✅ Using provided admin password${NC}"
fi

# Apply the user configuration using kubectl patch (argocd-cm already exists)
echo "Applying base user configuration using kubectl patch..."
echo "Note: Using kubectl patch because argocd-cm already exists from ArgoCD installation"
# kubectl patch configmap argocd-cm -n argocd --type merge -p '{
#   "data": {
#     "accounts.approver": "apiKey, login",
#     "accounts.reader": "apiKey, login"
#   }
# }'

kubectl patch configmap argocd-cm -n argocd --type merge --patch-file "$PROJECT_DIR/manifests/01-argocd/argocd-users.yaml"

# Apply RBAC policies using the YAML file
echo "Applying RBAC policies from YAML file..."
kubectl apply -f "$PROJECT_DIR/manifests/01-argocd/argocd-rbac-cm.yaml"

# Restart ArgoCD server to pick up new accounts
echo "Restarting ArgoCD server to pick up new accounts..."
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=2m

echo "Waiting for accounts to be available..."
sleep 10

# Port-forward ArgoCD server for CLI access
echo "Setting up port-forward for ArgoCD CLI..."

# Check if port 8080 is already in use and clean it up
ARGOCD_PORT=8080
if lsof -ti :8080 >/dev/null 2>&1; then
  echo "Port 8080 is already in use. Cleaning up existing port-forward..."
  lsof -ti :8080 | xargs kill -9 2>/dev/null || true
  sleep 2
  
  # Check if port is still in use after cleanup
  if lsof -ti :8080 >/dev/null 2>&1; then
    echo "Port 8080 still in use. Trying alternative port 8081..."
    ARGOCD_PORT=8081
    if lsof -ti :8081 >/dev/null 2>&1; then
      echo "Port 8081 also in use. Cleaning up..."
      lsof -ti :8081 | xargs kill -9 2>/dev/null || true
      sleep 2
    fi
  fi
fi

# Start port-forward
echo "Starting port-forward on port $ARGOCD_PORT..."
kubectl port-forward svc/argocd-server -n argocd $ARGOCD_PORT:443 &
PORT_FORWARD_PID=$!

# Wait for port-forward to be ready and verify it's working
sleep 5
if ! curl -k https://localhost:$ARGOCD_PORT/healthz >/dev/null 2>&1; then
  echo "Waiting for port-forward to be ready..."
  sleep 5
  if ! curl -k https://localhost:$ARGOCD_PORT/healthz >/dev/null 2>&1; then
    echo "${RED}❌ Port-forward failed to start properly${NC}"
    kill $PORT_FORWARD_PID 2>/dev/null || true
    exit 1
  fi
fi
echo "${GREEN}✅ Port-forward is ready on port $ARGOCD_PORT${NC}"

# Login as admin first
echo "Logging in as admin..."
if argocd login localhost:$ARGOCD_PORT --username admin --password "$ADMIN_PASSWORD" --insecure; then
  echo "${GREEN}✅ Successfully logged in as admin${NC}"
  
  # Set password for approver user
  echo "Setting password for approver user..."
  if argocd account update-password --account approver --current-password "$ADMIN_PASSWORD" --new-password "$ADMIN_PASSWORD"; then
    echo "${GREEN}✅ Approver password set successfully${NC}"
  else
    echo "${RED}❌ Failed to set approver password${NC}"
    kill $PORT_FORWARD_PID 2>/dev/null || true
    exit 1
  fi
  
  # Set password for reader user
  echo "Setting password for reader user..."
  if argocd account update-password --account reader --current-password "$ADMIN_PASSWORD" --new-password "$ADMIN_PASSWORD"; then
    echo "${GREEN}✅ Reader password set successfully${NC}"
  else
    echo "${RED}❌ Failed to set reader password${NC}"
    kill $PORT_FORWARD_PID 2>/dev/null || true
    exit 1
  fi
  
  echo "${GREEN}✅ Users configured successfully${NC}"
else
  echo "${RED}❌ Failed to login via ArgoCD CLI${NC}"
  kill $PORT_FORWARD_PID 2>/dev/null || true
  exit 1
fi

# Stop port-forward
echo "Cleaning up port-forward..."
if [ -n "$PORT_FORWARD_PID" ] && ps -p $PORT_FORWARD_PID > /dev/null 2>&1; then
  kill $PORT_FORWARD_PID 2>/dev/null || true
  echo "${GREEN}✅ Port-forward stopped${NC}"
else
  # Fallback: kill any process using port 8080
  lsof -ti :8080 | xargs kill -9 2>/dev/null || true
  echo "${YELLOW}Port-forward already stopped${NC}"
fi

# Restart ArgoCD server to pick up new users
echo "Restarting ArgoCD server..."
kubectl rollout restart deployment argocd-server -n argocd

echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment argocd-server -n argocd

echo ""
echo "${GREEN}✅ Users created successfully!${NC}"
echo ""
echo "User Credentials (all use the same password as admin):"
echo "=========================================================="
echo ""
echo "Admin User:"
echo "  URL: https://localhost:$ARGOCD_PORT"
echo "  Username: admin"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "Approver User (can view & approve changes):"
echo "  URL: https://localhost:$ARGOCD_PORT"
echo "  Username: approver"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "Reader User (can only view, no approve):"
echo "  URL: https://localhost:$ARGOCD_PORT"
echo "  Username: reader"
echo "  Password: $ADMIN_PASSWORD"
echo ""
echo "${YELLOW}User Permissions:${NC}"
echo "  - admin: Full access to everything"
echo "  - approver: Can view applications and approve changes"
echo "  - reader: Can only view applications (no approvals)"
echo ""
echo "${YELLOW}💡 To access ArgoCD UI, run: ./scripts/port-forward.sh${NC}"
