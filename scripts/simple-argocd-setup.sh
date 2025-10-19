#!/bin/bash

set -e

echo "⚡ Simple ArgoCD Setup with Defaults"
echo "==================================="
echo ""
echo "This script uses smart defaults for quick setup:"
echo "  🔗 Repository URL: https://github.com/vinish86/crossplane-argocd-approval.git"
echo "  📁 Repository name: crossplane-argocd-approval"
echo "  📂 Sync directory: gitops-repo/pausables"
echo "  📱 Application name: crossplane-argocd-approval-app"
echo "  🔄 Sync policy: Automatic sync with self-heal and prune"
echo ""
echo "Git credentials will be taken from environment variables:"
echo "  👤 GIT_USERNAME"
echo "  🔐 GIT_TOKEN"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check if ArgoCD is installed
if ! kubectl get namespace argocd &>/dev/null; then
  echo "${RED}❌ ArgoCD not found! Please install ArgoCD first:${NC}"
  echo "   ./scripts/install-argocd-fresh.sh"
  exit 1
fi

echo "${GREEN}✅ ArgoCD is installed and ready${NC}"

echo ""
echo "${YELLOW}Automatic Setup${NC}"
echo "================"
echo ""
echo "Automatically configuring Git repository and creating ArgoCD application..."
echo ""

# Check for required environment variables
if [ -z "$GIT_USERNAME" ] || [ -z "$GIT_TOKEN" ]; then
  echo "${RED}❌ Required environment variables not set!${NC}"
  echo ""
  echo "Please set the following environment variables:"
  echo "  export GIT_USERNAME='your-git-username'"
  echo "  export GIT_TOKEN='your-git-token'"
  echo ""
  echo "Then run this script again."
  exit 1
fi

echo "${GREEN}✅ Environment variables found:${NC}"
echo "  GIT_USERNAME: $GIT_USERNAME"
echo "  GIT_TOKEN: [HIDDEN]"
echo ""

# Automatically proceed with option 1
echo ""
echo "${YELLOW}Configure Private Git Repository + Create Application${NC}"
echo "====================================================="
echo ""

# Repository Configuration with defaults
echo "📁 Repository Configuration:"
echo ""

# Default values
DEFAULT_REPO_NAME="crossplane-argocd-approval"
DEFAULT_REPO_PATH="gitops-repo/pausables"
DEFAULT_REPO_URL="https://github.com/vinish86/crossplane-argocd-approval.git"

# Use default values (no user input needed)
REPO_URL="$DEFAULT_REPO_URL"
REPO_NAME="$DEFAULT_REPO_NAME"

echo "Using default values:"
echo "  Repository URL: $REPO_URL"
echo "  Repository name: $REPO_NAME"
echo "  Git username: $GIT_USERNAME"
echo "  Git token: [HIDDEN]"
    
    echo ""
    echo "Creating ArgoCD repository secret with credentials..."
    kubectl create secret generic "$REPO_NAME-repo" \
      --from-literal=url="$REPO_URL" \
      --from-literal=type=git \
      --from-literal=password="$GIT_TOKEN" \
      --from-literal=username="$GIT_USERNAME" \
      -n argocd \
      --dry-run=client -o yaml | kubectl apply -f -
    
    echo "${GREEN}✅ Private repository configured: $REPO_NAME${NC}"
    
# Application Configuration with defaults
echo ""
echo "📱 Application Configuration:"
echo ""

# Use default values (no user input needed)
APP_NAME="$DEFAULT_REPO_NAME-app"
REPO_PATH="$DEFAULT_REPO_PATH"
TARGET_NAMESPACE="default"

echo "Using default values:"
echo "  Application name: $APP_NAME"
echo "  Repository path: $REPO_PATH"
echo "  Target namespace: $TARGET_NAMESPACE"

# Automatically choose option 4: Automatic sync with self-heal and prune
echo ""
echo "🔄 Sync Policy: Automatic sync with self-heal and prune (option 4)"
SYNC_OPTIONS='{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}'
SYNC_DESCRIPTION="Automatic sync with self-heal and prune"
    
    echo ""
    echo "Creating ArgoCD application..."
    
    # Create application YAML with proper sync policy
    if [ -n "$SYNC_OPTIONS" ]; then
      # Create YAML with automated sync policy
      cat > /tmp/argocd-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $REPO_URL
    targetRevision: HEAD
    path: $REPO_PATH
  destination:
    server: https://kubernetes.default.svc
    namespace: $TARGET_NAMESPACE
  syncPolicy:
    automated:
      prune: $(echo "$SYNC_OPTIONS" | jq -r '.syncPolicy.automated.prune // false')
      selfHeal: $(echo "$SYNC_OPTIONS" | jq -r '.syncPolicy.automated.selfHeal // false')
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
EOF
    else
      # Create YAML with manual sync policy
      cat > /tmp/argocd-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $APP_NAME
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $REPO_URL
    targetRevision: HEAD
    path: $REPO_PATH
  destination:
    server: https://kubernetes.default.svc
    namespace: $TARGET_NAMESPACE
  syncPolicy:
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
EOF
    fi
    
    kubectl apply -f /tmp/argocd-app.yaml
    rm -f /tmp/argocd-app.yaml
    
    echo ""
    echo "${GREEN}✅ Setup Complete!${NC}"
    echo ""
    echo "Configuration Summary:"
    echo "  📁 Repository: $REPO_NAME"
    echo "  🔗 Repository URL: $REPO_URL"
    echo "  👤 Git Username: $GIT_USERNAME"
echo "  📱 Application: $APP_NAME"
echo "  📂 Sync Path: $REPO_PATH"
echo "  🏷️  Target Namespace: $TARGET_NAMESPACE"
echo "  🔄 Sync Policy: $SYNC_DESCRIPTION"
echo ""
echo "Next steps:"
echo "  1. Port-forward ArgoCD: ./scripts/port-forward.sh"
echo "  2. Access ArgoCD UI: https://localhost:8080"
echo "  3. View your application in ArgoCD UI"
echo "  4. Push your manifests to the $REPO_PATH directory in your repository"

echo ""
echo "${GREEN}✅ Operation completed!${NC}"
echo ""
echo "Next steps:"
echo "1. Port-forward ArgoCD: ./scripts/port-forward.sh"
echo "2. Access ArgoCD UI: https://localhost:8080"
echo "3. View your repositories and applications in the UI"
