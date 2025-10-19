#!/bin/bash

set -e

echo "🗑️  Uninstalling ArgoCD (Crossplane will remain intact)"
echo "====================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Confirmation prompt
echo ""
echo "${YELLOW}⚠️  WARNING: This will completely remove ArgoCD and all its resources${NC}"
echo "Crossplane and your Pausable resources will remain untouched."
echo ""
read -p "Are you sure you want to proceed? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "${YELLOW}Uninstall cancelled.${NC}"
  exit 0
fi

echo ""
echo "${YELLOW}Step 1/6: Removing ArgoCD Applications${NC}"
# Delete ArgoCD applications first
kubectl delete applications --all -n argocd --ignore-not-found=true || true
echo "✅ ArgoCD Applications removed"

echo ""
echo "${YELLOW}Step 2/6: Removing ArgoCD Repository Secrets${NC}"
# Delete repository secrets
kubectl delete secrets -l argocd.argoproj.io/secret-type=repository -n argocd --ignore-not-found=true || true
echo "✅ Repository secrets removed"

echo ""
echo "${YELLOW}Step 3/6: Removing ArgoCD Custom Configurations${NC}"
# Remove custom configurations
kubectl delete -f "$PROJECT_DIR/manifests/01-argocd/argocd-cm-cluster-resources.yaml" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_DIR/manifests/01-argocd/custom-action.yaml" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_DIR/manifests/01-argocd/rbac-permissions.yaml" --ignore-not-found=true || true
echo "✅ Custom configurations removed"

echo ""
echo "${YELLOW}Step 4/6: Removing ArgoCD Core Installation${NC}"
# Remove ArgoCD core installation
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.17/manifests/install.yaml --ignore-not-found=true || true
echo "✅ ArgoCD core installation removed"

echo ""
echo "${YELLOW}Step 5/6: Waiting for ArgoCD Resources to be Deleted${NC}"
# Wait for resources to be deleted
echo "Waiting for ArgoCD pods to terminate..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=60s || true
kubectl wait --for=delete pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=60s || true
kubectl wait --for=delete pod -l app.kubernetes.io/name=argocd-dex-server -n argocd --timeout=60s || true
kubectl wait --for=delete pod -l app.kubernetes.io/name=argocd-redis -n argocd --timeout=60s || true
kubectl wait --for=delete pod -l app.kubernetes.io/name=argocd-repo-server -n argocd --timeout=60s || true

echo ""
echo "${YELLOW}Step 6/6: Removing ArgoCD Namespace${NC}"
# Remove the argocd namespace
kubectl delete namespace argocd --ignore-not-found=true || true
echo "✅ ArgoCD namespace removed"

echo ""
echo "${GREEN}✅ ArgoCD Uninstall Complete!${NC}"
echo ""

echo "What was removed:"
echo "  ✅ ArgoCD Server and all components"
echo "  ✅ ArgoCD Applications and configurations"
echo "  ✅ Repository secrets and credentials"
echo "  ✅ Custom RBAC permissions"
echo "  ✅ Custom actions and configurations"
echo "  ✅ ArgoCD namespace"

echo ""
echo "What remains intact:"
echo "  ✅ Crossplane installation"
echo "  ✅ Pausable resources and compositions"
echo "  ✅ Your existing workloads"
echo "  ✅ All other Kubernetes resources"

echo ""
echo "Next steps:"
echo "1. Verify Crossplane is still running: kubectl get pods -n crossplane-system"
echo "2. Check your Pausable resources: kubectl get pausable -A"
echo "3. Reinstall ArgoCD when ready: ./scripts/install-argocd.sh"
echo ""
echo "📖 Documentation:"
echo "   - README.md - Overview and architecture"
echo "   - ./scripts/install-crossplane.sh - Reinstall Crossplane if needed"
echo "   - ./scripts/install-argocd.sh - Reinstall ArgoCD when ready"
