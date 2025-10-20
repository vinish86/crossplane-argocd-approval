#!/bin/bash

set -e

echo "🗑️  Uninstalling Crossplane with Pause-on-Change System"
echo "====================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Function to check if Crossplane is installed
check_crossplane_installed() {
  if ! kubectl get namespace crossplane-system &>/dev/null; then
    echo "${YELLOW}⚠️  Crossplane namespace not found. Crossplane may not be installed.${NC}"
    return 1
  fi
  return 0
}

# Function to wait for resources to be deleted
wait_for_deletion() {
  local resource_type="$1"
  local namespace="$2"
  local timeout="${3:-60}"
  
  echo "Waiting for $resource_type to be deleted..."
  local count=0
  while kubectl get "$resource_type" -n "$namespace" &>/dev/null && [ $count -lt $timeout ]; do
    sleep 2
    count=$((count + 2))
    echo -n "."
  done
  echo ""
  
  if kubectl get "$resource_type" -n "$namespace" &>/dev/null; then
    echo "${YELLOW}⚠️  Some $resource_type resources may still exist${NC}"
    return 1
  else
    echo "${GREEN}✅ All $resource_type resources deleted${NC}"
    return 0
  fi
}

# Check if Crossplane is installed
if ! check_crossplane_installed; then
  echo "${YELLOW}Crossplane appears to not be installed. Nothing to uninstall.${NC}"
  exit 0
fi

echo "${GREEN}✅ Crossplane installation found${NC}"

# Confirmation prompt
echo ""
echo "${YELLOW}⚠️  WARNING: This will completely remove Crossplane and all its resources!${NC}"
echo ""
echo "This includes:"
echo "  • All Crossplane Claims and Composites"
echo "  • All Crossplane Managed Resources"
echo "  • All Crossplane Compositions and XRDs"
echo "  • All Crossplane Functions and Providers"
echo "  • The entire Crossplane system"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "${YELLOW}Uninstall cancelled.${NC}"
  exit 0
fi

echo ""
echo "${YELLOW}Step 0/8: Removing GitOps Source Files${NC}"
echo "====================================="
echo ""

# First, remove the gitops-repo files that are creating the claims
echo "Removing Pausable claim files from gitops-repo to prevent recreation..."
if [ -d "gitops-repo/pausables" ]; then
  echo "Found gitops-repo/pausables directory. Removing claim files..."
  rm -f gitops-repo/pausables/*.yaml
  echo "${GREEN}✅ Removed claim files from gitops-repo/pausables${NC}"
else
  echo "No gitops-repo/pausables directory found."
fi

if [ -d "gitops-repo/slack-notifications" ]; then
  echo "Removing SlackNotification files from gitops-repo..."
  rm -f gitops-repo/slack-notifications/*.yaml
  echo "${GREEN}✅ Removed SlackNotification files from gitops-repo/slack-notifications${NC}"
else
  echo "No gitops-repo/slack-notifications directory found."
fi

echo ""
echo "${YELLOW}Step 1/8: Deleting Claims${NC}"
echo "=========================="
echo ""

# Delete all claims first
echo "Deleting all Crossplane claims..."
echo "Checking for existing claims..."

# List all claims across all namespaces
CLAIMS=$(kubectl get claim --all-namespaces --no-headers 2>/dev/null | wc -l)
if [ "$CLAIMS" -gt 0 ]; then
  echo "Found $CLAIMS claim(s) to delete:"
  kubectl get claim --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,KIND:.kind" --no-headers 2>/dev/null | while read line; do
    if [ -n "$line" ]; then
      echo "  📋 $line"
    fi
  done
  
  echo ""
  echo "Deleting all claims..."
  
  # Delete each claim individually using the correct syntax
  for claim in $(kubectl get claim --all-namespaces --no-headers 2>/dev/null | awk '{print $2}'); do
    if [ -n "$claim" ]; then
      # Extract namespace and name
      namespace=$(kubectl get claim --all-namespaces --no-headers 2>/dev/null | grep "$claim" | awk '{print $1}')
      name=$(echo "$claim" | sed 's|pausable.example.io/||')
      echo "  Deleting pausable.example.io/$name in namespace $namespace"
      kubectl delete pausable.example.io/"$name" -n "$namespace" --ignore-not-found=true || true
    fi
  done
  
  # Wait for claims to be deleted
  echo "Waiting for claims to be deleted..."
  count=0
  while [ $count -lt 60 ]; do
    REMAINING_CLAIMS=$(kubectl get claim --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING_CLAIMS" -eq 0 ]; then
      break
    fi
    sleep 2
    count=$((count + 2))
    echo -n "."
  done
  echo ""
  
  if [ "$REMAINING_CLAIMS" -eq 0 ]; then
    echo "${GREEN}✅ All claims deleted${NC}"
  else
    echo "${YELLOW}⚠️  Some claims may still exist${NC}"
  fi
else
  echo "No claims found to delete."
  echo "${GREEN}✅ No claims to delete${NC}"
fi

echo ""
echo "${YELLOW}Step 2/8: Deleting Composites${NC}"
echo "============================="
echo ""

# Delete all composites
echo "Deleting all Crossplane composites..."
echo "Checking for existing composites..."

# List all composites
COMPOSITES=$(kubectl get composite --no-headers 2>/dev/null | wc -l)
if [ "$COMPOSITES" -gt 0 ]; then
  echo "Found $COMPOSITES composite(s) to delete:"
  kubectl get composite -o custom-columns="NAME:.metadata.name,KIND:.kind,READY:.status.conditions[?(@.type=='Ready')].status" --no-headers 2>/dev/null | while read line; do
    if [ -n "$line" ]; then
      echo "  🧩 $line"
    fi
  done
  
  echo ""
  echo "Deleting all composites..."
  
  # Delete each composite individually using the correct syntax
  kubectl get composite --no-headers 2>/dev/null | while read line; do
    if [ -n "$line" ]; then
      # Extract the full resource name (first field)
      resource_name=$(echo "$line" | awk '{print $1}')
      if [ -n "$resource_name" ]; then
        echo "  Deleting $resource_name"
        kubectl delete "$resource_name" --ignore-not-found=true || true
      fi
    fi
  done
  
  # Wait for composites to be deleted
  echo "Waiting for composites to be deleted..."
  count=0
  while [ $count -lt 60 ]; do
    REMAINING_COMPOSITES=$(kubectl get composite --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING_COMPOSITES" -eq 0 ]; then
      break
    fi
    sleep 2
    count=$((count + 2))
    echo -n "."
  done
  echo ""
  
  if [ "$REMAINING_COMPOSITES" -eq 0 ]; then
    echo "${GREEN}✅ All composites deleted${NC}"
  else
    echo "${YELLOW}⚠️  Some composites may still exist${NC}"
  fi
else
  echo "No composites found to delete."
  echo "${GREEN}✅ No composites to delete${NC}"
fi

echo ""
echo "${YELLOW}Step 3/8: Deleting Managed Resources${NC}"
echo "====================================="
echo ""

# Delete all managed resources
echo "Deleting all Crossplane managed resources..."
echo "Checking for existing managed resources..."

MANAGED_RESOURCES=$(kubectl get managed --no-headers 2>/dev/null | wc -l)
if [ "$MANAGED_RESOURCES" -gt 0 ]; then
  echo "Found $MANAGED_RESOURCES managed resource(s) to delete:"
  kubectl get managed -o custom-columns="NAME:.metadata.name,KIND:.kind,READY:.status.conditions[?(@.type=='Ready')].status" --no-headers 2>/dev/null | while read line; do
    if [ -n "$line" ]; then
      echo "  🔧 $line"
    fi
  done
  
  echo ""
  echo "Removing finalizers from all managed resources to delete them..."
  
  # Directly patch all managed resources to remove finalizers (no need to delete first)
  kubectl get managed --no-headers 2>/dev/null | while read line; do
    if [ -n "$line" ]; then
      resource_name=$(echo "$line" | awk '{print $1}')
      if [ -n "$resource_name" ]; then
        echo "  Removing finalizers from: $resource_name"
        kubectl patch "$resource_name" --type merge --patch '{"metadata":{"finalizers":null}}' 2>/dev/null || true
      fi
    fi
  done
  
  # Wait briefly for resources to be deleted after finalizer removal
  echo "Waiting for managed resources to be deleted after finalizer removal..."
  count=0
  while [ $count -lt 30 ]; do  # Short wait of 30 seconds
    REMAINING_MANAGED=$(kubectl get managed --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING_MANAGED" -eq 0 ]; then
      break
    fi
    sleep 2
    count=$((count + 2))
    echo -n "."
  done
  echo ""
  
  # Check final status
  REMAINING_MANAGED=$(kubectl get managed --no-headers 2>/dev/null | wc -l)
  if [ "$REMAINING_MANAGED" -eq 0 ]; then
    echo "${GREEN}✅ All managed resources deleted successfully${NC}"
  else
    echo "${YELLOW}⚠️  Some managed resources may still exist${NC}"
    echo "These resources may need to be manually cleaned up:"
    echo "  • External cloud resources"
    echo "  • Kubernetes resources in other namespaces"
    echo "  • Custom resources created by Crossplane"
    echo ""
    echo "You can check them with:"
    echo "  kubectl get managed"
    echo "  kubectl get all --all-namespaces | grep crossplane"
    echo ""
    echo "To manually remove finalizers:"
    echo "  kubectl patch <resource-name> --type merge --patch '{\"metadata\":{\"finalizers\":null}}'"
  fi
else
  echo "No managed resources found to delete."
  echo "${GREEN}✅ No managed resources to delete${NC}"
fi

echo ""
echo "${YELLOW}Step 4/8: Deleting Compositions${NC}"
echo "=============================================="
echo ""

# Delete compositions
echo "Deleting compositions..."
kubectl delete -f "$PROJECT_DIR/manifests/04-compositions/slack-notification-composition.yaml" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_DIR/manifests/04-compositions/child-pausable-composition.yaml" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_DIR/manifests/04-compositions/pausable-composition.yaml" --ignore-not-found=true || true

echo "${GREEN}✅ Compositions deleted${NC}"

echo ""
echo "${YELLOW}Step 5/8: Deleting XRDs (Custom Resource Definitions)${NC}"
echo "========================================================"
echo ""

# Delete XRDs
echo "Deleting XRDs..."
kubectl delete -f "$PROJECT_DIR/manifests/03-crds/slack-notification-xrd.yaml" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_DIR/manifests/03-crds/child-pausable-xrd.yaml" --ignore-not-found=true || true
kubectl delete -f "$PROJECT_DIR/manifests/03-crds/pausable-xrd.yaml" --ignore-not-found=true || true

echo "${GREEN}✅ XRDs deleted${NC}"

echo ""
echo "${YELLOW}Step 6/8: Deleting ProviderConfigs${NC}"
echo "====================================="
echo ""

# Delete cluster-scoped ProviderConfigs (they won't be deleted with namespace)
echo "Deleting cluster-scoped ProviderConfigs..."
echo "Checking for existing ProviderConfigs..."

# List all ProviderConfigs
PROVIDERCONFIGS=$(kubectl get providerconfigs --no-headers 2>/dev/null | wc -l)
if [ "$PROVIDERCONFIGS" -gt 0 ]; then
  echo "Found $PROVIDERCONFIGS ProviderConfig(s) to delete:"
  kubectl get providerconfigs -o custom-columns="NAME:.metadata.name,PROVIDER:.spec.provider" --no-headers 2>/dev/null | while read line; do
    if [ -n "$line" ]; then
      echo "  ⚙️  $line"
    fi
  done
  
  echo ""
  echo "Deleting all ProviderConfigs..."
  kubectl delete providerconfigs --all --ignore-not-found=true || true
  
  # Wait for ProviderConfigs to be deleted
  echo "Waiting for ProviderConfigs to be deleted..."
  count=0
  while [ $count -lt 60 ]; do
    REMAINING_PROVIDERCONFIGS=$(kubectl get providerconfigs --no-headers 2>/dev/null | wc -l)
    if [ "$REMAINING_PROVIDERCONFIGS" -eq 0 ]; then
      break
    fi
    sleep 2
    count=$((count + 2))
    echo -n "."
  done
  echo ""
  
  if [ "$REMAINING_PROVIDERCONFIGS" -eq 0 ]; then
    echo "${GREEN}✅ All ProviderConfigs deleted${NC}"
  else
    echo "${YELLOW}⚠️  Some ProviderConfigs may still exist${NC}"
  fi
else
  echo "No ProviderConfigs found to delete."
  echo "${GREEN}✅ No ProviderConfigs to delete${NC}"
fi

echo ""
echo "${YELLOW}Step 7/8: Deleting Crossplane System${NC}"
echo "====================================="
echo ""

# Delete the entire crossplane-system namespace (easiest and most effective way)
echo "Deleting crossplane-system namespace..."
echo "This will remove all Crossplane components at once:"
echo "  • Crossplane Core"
echo "  • All Providers"
echo "  • All Functions"
echo "  • All EnvironmentConfigs"
echo "  • All other Crossplane resources"
echo ""

kubectl delete namespace crossplane-system --ignore-not-found=true || true

# Wait for namespace to be deleted
echo "Waiting for crossplane-system namespace to be deleted..."
count=0
while kubectl get namespace crossplane-system &>/dev/null && [ $count -lt 120 ]; do
  sleep 2
  count=$((count + 2))
  echo -n "."
done
echo ""

if kubectl get namespace crossplane-system &>/dev/null; then
  echo "${YELLOW}⚠️  crossplane-system namespace may still exist${NC}"
  echo "You may need to manually delete it:"
  echo "  kubectl delete namespace crossplane-system --force --grace-period=0"
else
  echo "${GREEN}✅ crossplane-system namespace deleted${NC}"
fi

# Clean up Helm repository
echo ""
echo "Cleaning up Helm repository..."
helm repo remove crossplane-stable 2>/dev/null || true

echo ""
echo "${GREEN}✅ Crossplane Uninstallation Complete!${NC}"
echo ""

echo "Removed Components:"
echo "  ✅ Claims (all namespaces)"
echo "  ✅ Composites"
echo "  ✅ Managed Resources"
echo "  ✅ Crossplane Compositions"
echo "  ✅ XRDs (Custom Resource Definitions)"
echo "  ✅ ProviderConfigs (cluster-scoped)"
echo "  ✅ crossplane-system namespace (all Crossplane components)"
echo "  ✅ Helm repository"

echo ""
echo "${YELLOW}⚠️  Note: Any external resources created by Crossplane may still exist${NC}"
echo "   You may need to manually clean up:"
echo "   • External cloud resources (AWS, GCP, Azure, etc.)"
echo "   • Kubernetes resources in other namespaces"
echo "   • Custom resources that were created by Crossplane"
echo ""
echo "To check for remaining Crossplane-related resources:"
echo "  kubectl get all --all-namespaces | grep crossplane"
echo "  kubectl get crd | grep crossplane"
echo ""
echo "${GREEN}🎉 Crossplane has been completely uninstalled!${NC}"