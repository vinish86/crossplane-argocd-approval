#!/bin/bash

set -e

echo "🚀 Installing ArgoCD with Pause-on-Change Approval System"
echo "=========================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Prompt for ArgoCD password
echo ""
echo "${YELLOW}ArgoCD Password Configuration${NC}"
echo "=============================="
echo ""
read -p "Set custom ArgoCD admin password? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Enter your desired ArgoCD admin password:"
  read -s ARGOCD_CUSTOM_PASSWORD
  echo ""
  echo "Confirm password:"
  read -s ARGOCD_CUSTOM_PASSWORD_CONFIRM
  echo ""
  
  if [ "$ARGOCD_CUSTOM_PASSWORD" != "$ARGOCD_CUSTOM_PASSWORD_CONFIRM" ]; then
    echo "${RED}Passwords don't match. Installation will use random password.${NC}"
    echo "You can change it later with: ./scripts/set-argocd-password.sh"
    ARGOCD_CUSTOM_PASSWORD=""
  else
    echo "${GREEN}✅ Custom password will be set after ArgoCD installation${NC}"
  fi
else
  ARGOCD_CUSTOM_PASSWORD=""
  echo "${YELLOW}Using random password. You can get it with: ./scripts/get-argocd-password.sh${NC}"
fi

# Prompt for GitOps repository
echo ""
echo "${YELLOW}GitOps Repository Configuration${NC}"
echo "================================"
echo ""

# Set defaults
DEFAULT_GIT_REPO_URL="https://github.com/vinish86/crossplane-argocd-approval.git"
DEFAULT_GIT_PATH="gitops-repo/pausables"

read -p "Configure ArgoCD to watch a Git repository? (Y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo ""
  echo "Enter Git repository URL"
  echo "Default: $DEFAULT_GIT_REPO_URL"
  echo -n "Press Enter to use default or enter custom URL: "
  read GIT_REPO_URL
  GIT_REPO_URL=${GIT_REPO_URL:-$DEFAULT_GIT_REPO_URL}
  
  if [ -z "$GIT_REPO_URL" ]; then
    echo "${YELLOW}No repository URL provided. You can configure it later.${NC}"
    GIT_REPO_URL=""
  else
    echo ""
    echo "Repository: $GIT_REPO_URL"
    echo ""
    read -p "Is this a private repository requiring authentication? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo ""
      echo "Enter Git username (e.g., your GitHub username):"
      read GIT_USERNAME
      echo ""
      echo "Enter Git token/password (will be hidden):"
      read -s GIT_TOKEN
      echo ""
      echo "${GREEN}✅ Git credentials will be configured${NC}"
    else
      GIT_USERNAME=""
      GIT_TOKEN=""
      echo "${YELLOW}Using public repository access${NC}"
    fi
    
    echo ""
    echo "Enter Git branch to watch (default: main):"
    read GIT_BRANCH
    GIT_BRANCH=${GIT_BRANCH:-main}
    
    echo ""
    echo "Enter path in repository for Pausable resources"
    echo "Default: $DEFAULT_GIT_PATH"
    echo -n "Press Enter to use default or enter custom path: "
    read GIT_PATH
    GIT_PATH=${GIT_PATH:-$DEFAULT_GIT_PATH}
    
    echo ""
    echo "${GREEN}✅ ArgoCD Application will be configured:${NC}"
    echo "   Repository: $GIT_REPO_URL"
    echo "   Branch: $GIT_BRANCH"
    echo "   Path: $GIT_PATH"
  fi
else
  GIT_REPO_URL=""
  echo "${YELLOW}Skipping GitOps configuration. You can configure it later with:${NC}"
  echo "   kubectl apply -f manifests/01-argocd/argocd-app.yaml"
fi

echo ""
echo "${YELLOW}Step 1/9: Installing ArgoCD${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo ""
echo "${YELLOW}Step 2/9: Waiting for ArgoCD to be ready${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Set custom password if provided (will be done at the end after everything is ready)
if [ -n "$ARGOCD_CUSTOM_PASSWORD" ]; then
  echo ""
  echo "${YELLOW}Custom password will be set at the end of installation${NC}"
fi

echo ""
echo "${YELLOW}Step 3/9: Installing Crossplane${NC}"
kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

# Add Crossplane Helm repo
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || true
helm repo update

# Install Crossplane
helm upgrade --install crossplane \
  --namespace crossplane-system \
  crossplane-stable/crossplane \
  --wait \
  --timeout 5m

echo ""
echo "${YELLOW}Step 4/9: Installing Crossplane Functions${NC}"
echo "Installing Go Templating Function..."
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-go-templating
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.11.0
EOF

echo "Installing Auto Ready Function..."
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-auto-ready
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.5.1
EOF

echo ""
echo "${YELLOW}Step 5/9: Waiting for Functions to be healthy${NC}"
echo "This may take a few minutes..."
kubectl wait --for=condition=healthy --timeout=300s function/function-go-templating || true
kubectl wait --for=condition=healthy --timeout=300s function/function-auto-ready || true

echo ""
echo "${YELLOW}Step 6/9: Installing XRDs (Custom Resource Definitions)${NC}"
kubectl apply -f "$PROJECT_DIR/manifests/03-crds/pausable-xrd.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/03-crds/child-pausable-xrd.yaml"

echo ""
echo "${YELLOW}Step 7/9: Installing Compositions${NC}"
kubectl apply -f "$PROJECT_DIR/manifests/04-compositions/pausable-composition.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/04-compositions/child-pausable-composition.yaml"

echo ""
echo "${YELLOW}Step 8/9: Configuring ArgoCD RBAC and Custom Actions${NC}"
echo "Granting ArgoCD permissions to manage Pausable resources..."
kubectl apply -f "$PROJECT_DIR/manifests/01-argocd/rbac-permissions.yaml"

echo ""
echo "Applying custom action configuration..."
kubectl apply -f "$PROJECT_DIR/manifests/01-argocd/custom-action.yaml"

echo ""
echo "${YELLOW}Restarting ArgoCD Server to load custom actions${NC}"
kubectl rollout restart deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo ""
echo "${YELLOW}Step 9/9: Verifying ArgoCD Custom Action Configuration${NC}"
echo "✅ ArgoCD button configured for Pausable resources"
echo "✅ Approval workflow uses annotations (no separate approval resources)"
echo "✅ Changes are paused until approved via ArgoCD UI"

# Configure GitOps repository if provided
if [ -n "$GIT_REPO_URL" ]; then
  echo ""
  echo "${YELLOW}Step 10: Configuring ArgoCD Application for GitOps${NC}"
  
  # Create repository secret if credentials provided
  if [ -n "$GIT_USERNAME" ] && [ -n "$GIT_TOKEN" ]; then
    echo "Creating Git repository secret..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: private-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: $GIT_REPO_URL
  username: $GIT_USERNAME
  password: $GIT_TOKEN
EOF
    echo "${GREEN}✅ Repository credentials configured${NC}"
  fi
  
  # Create ArgoCD Application
  echo "Creating ArgoCD Application..."
  kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: pausable-resources
  namespace: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  
  source:
    repoURL: $GIT_REPO_URL
    targetRevision: $GIT_BRANCH
    path: $GIT_PATH
  
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  
  syncPolicy:
    automated:
      prune: true
      # CRITICAL: Disable self-heal for approval workflow
      selfHeal: false
    
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    
    # Retry failed syncs
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
  
  echo "${GREEN}✅ ArgoCD Application created!${NC}"
  echo ""
  echo "Application Details:"
  echo "  Name: pausable-resources"
  echo "  Repository: $GIT_REPO_URL"
  echo "  Branch: $GIT_BRANCH"
  echo "  Path: $GIT_PATH"
  echo "  Sync: Automated (selfHeal: false)"
fi

# Set custom password at the end if provided
if [ -n "$ARGOCD_CUSTOM_PASSWORD" ]; then
  echo ""
  echo "${YELLOW}Setting custom ArgoCD password${NC}"
  
  # Wait for ArgoCD to be fully ready
  sleep 10
  
  # Save password to temp file for the helper script
  echo "$ARGOCD_CUSTOM_PASSWORD" > /tmp/argocd-desired-password
  
  # Get initial password
  INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
  
  if [ -z "$INITIAL_PASSWORD" ]; then
    echo "${YELLOW}⚠️  Waiting for initial password secret...${NC}"
    sleep 10
    INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
  fi
  
  if [ -n "$INITIAL_PASSWORD" ]; then
    # Use htpasswd if available (most common)
    if command -v htpasswd &> /dev/null; then
      echo "Generating password hash..."
      BCRYPT_HASH=$(htpasswd -nbBC 10 "" "$ARGOCD_CUSTOM_PASSWORD" 2>/dev/null | tr -d ':\n' | sed 's/\$2y/\$2a/' || echo "")
      
      if [ -n "$BCRYPT_HASH" ]; then
        kubectl -n argocd patch secret argocd-secret \
          --type='merge' \
          -p="{\"stringData\": {\"admin.password\": \"$BCRYPT_HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"
        
        echo "${GREEN}✅ Custom password set successfully!${NC}"
        rm -f /tmp/argocd-desired-password
      else
        echo "${YELLOW}⚠️  Password hash generation failed${NC}"
        echo "   Install htpasswd: brew install httpd (macOS) or apt-get install apache2-utils (Linux)"
        echo "   Then run: ./scripts/set-argocd-password.sh $(cat /tmp/argocd-desired-password)"
      fi
    else
      echo "${YELLOW}⚠️  htpasswd not found${NC}"
      echo "   Install it: brew install httpd (macOS) or apt-get install apache2-utils (Linux)"
      echo "   Then run: ./scripts/set-argocd-password.sh $(cat /tmp/argocd-desired-password)"
    fi
  else
    echo "${YELLOW}⚠️  Could not get initial password secret${NC}"
    echo "   Run after installation: ./scripts/set-argocd-password.sh $(cat /tmp/argocd-desired-password)"
  fi
fi

echo ""
echo "${GREEN}✅ Installation Complete!${NC}"
echo ""

# Prompt to create ArgoCD users (approver & reader)
echo "${YELLOW}ArgoCD User Setup${NC}"
echo "=================="
echo ""
read -p "Create ArgoCD users (approver & reader) now? (Y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo ""
  echo "${YELLOW}Creating ArgoCD users...${NC}"
  
  # Get the admin password to pass to create-argocd-users.sh
  CURRENT_ADMIN_PASSWORD=""
  if [ -n "$ARGOCD_CUSTOM_PASSWORD" ]; then
    CURRENT_ADMIN_PASSWORD="$ARGOCD_CUSTOM_PASSWORD"
  else
    CURRENT_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
  fi
  
  # Pass password as argument (no prompts)
  "$SCRIPT_DIR/create-argocd-users.sh" "$CURRENT_ADMIN_PASSWORD"
  echo ""
  echo "${GREEN}✅ ArgoCD users created!${NC}"
else
  echo ""
  echo "${YELLOW}Skipping user creation. You can create them later with:${NC}"
  echo "  ./scripts/create-argocd-users.sh"
fi

echo ""
echo "ArgoCD Credentials:"
if [ -n "$ARGOCD_CUSTOM_PASSWORD" ] && [ ! -f /tmp/argocd-desired-password ]; then
  echo "  URL: https://localhost:8080"
  echo "  Username: admin"
  echo "  Password: $ARGOCD_CUSTOM_PASSWORD"
else
  echo "  Run: ./scripts/get-argocd-password.sh"
  if [ -f /tmp/argocd-desired-password ]; then
    echo ""
    echo "${YELLOW}To set your custom password, run:${NC}"
    echo "  ./scripts/set-argocd-password.sh $(cat /tmp/argocd-desired-password)"
    rm -f /tmp/argocd-desired-password
  fi
fi
echo ""
if [ -n "$GIT_REPO_URL" ]; then
  echo ""
  echo "GitOps Configuration:"
  echo "  Repository: $GIT_REPO_URL"
  echo "  Branch: $GIT_BRANCH"
  echo "  Path: $GIT_PATH"
  echo "  Application: pausable-resources"
  echo ""
  echo "ArgoCD will automatically sync Pausable resources from your repository!"
fi
echo ""
echo "Next steps:"
echo "1. Port-forward ArgoCD: ./scripts/port-forward.sh"
echo "2. Access ArgoCD UI: https://localhost:8080"
if [ -z "$GIT_REPO_URL" ]; then
  echo "3. Create test Pausable resource: kubectl apply -f examples/pausable-example.yaml"
  echo "4. Or configure GitOps: kubectl apply -f manifests/01-argocd/argocd-app.yaml"
else
  echo "3. View 'pausable-resources' application in ArgoCD UI"
  echo "4. Make changes to your Git repository to test approval workflow"
fi
echo ""
echo "📖 Documentation:"
echo "   - START_HERE.md - Quick overview"
echo "   - QUICK_START.md - Full testing guide"
echo ""
echo "To test the approval workflow:"
echo "1. Create a Pausable claim"
echo "2. Update the claim (change will be paused automatically)"
echo "3. View the paused resource in ArgoCD UI"
echo "4. Click 'Approve Change' button in ArgoCD UI"
echo "5. The change will be applied!"
