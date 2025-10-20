#!/bin/bash

set -e

echo "🚀 Fresh ArgoCD Installation with Crossplane Resource Tracking"
echo "============================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Set RBAC level to cluster admin for full permissions
echo ""
echo "${YELLOW}RBAC Permission Level${NC}"
echo "======================"
echo ""
echo "ArgoCD will be configured with Cluster Admin permissions for full cluster access."
echo "This provides maximum compatibility and tracks ALL resources including Crossplane."
RBAC_LEVEL="cluster-admin"
RBAC_FILE="argocd-rbac-cluster-admin.yaml"
echo "${GREEN}✅ Using: Cluster Admin permissions${NC}"

# Set default password for all users
echo ""
echo "${YELLOW}ArgoCD Password Configuration${NC}"
echo "=============================="
echo ""
ARGOCD_CUSTOM_PASSWORD="password"
echo "${GREEN}✅ Using default password: 'password' for all users${NC}"
echo "${YELLOW}Note: This password will be used for admin, approver, and reader users${NC}"

echo ""
echo "${YELLOW}Step 1/8: Creating ArgoCD Namespace${NC}"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
echo "${GREEN}✅ ArgoCD namespace created${NC}"

echo ""
echo "${YELLOW}Step 2/8: Installing ArgoCD Core${NC}"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.14.17/manifests/install.yaml
echo "${GREEN}✅ ArgoCD core components installed${NC}"

echo ""
echo "${YELLOW}Step 3/8: Waiting for ArgoCD to be Ready${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
echo "${GREEN}✅ ArgoCD server is ready${NC}"

echo ""
echo "${YELLOW}Step 4/8: Applying Full RBAC Permissions${NC}"
echo "Using kubectl patch to avoid ArgoCD crashes..."
kubectl apply -f "$PROJECT_DIR/manifests/01-argocd/$RBAC_FILE"
echo "${GREEN}✅ RBAC permissions applied ($RBAC_LEVEL)${NC}"

echo ""
echo "${YELLOW}Step 5/8: Configuring Crossplane Resource Tracking${NC}"
echo "Applying Crossplane tracking configuration using kubectl patch..."
echo "Note: Using kubectl patch instead of kubectl apply to avoid ArgoCD crashes"

# Apply basic resource tracking first
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "resource.inclusions": "- apiGroups:\n  - \"*\"\n  kinds:\n  - \"*\"\n  clusters:\n  - \"*\"",
    "resource.exclusions": "",
    "resource.compareoptions": "ignoreAggregatedRoles: false",
    "application.resourceTrackingMethod": "annotation+label"
  }
}'

echo "${GREEN}✅ Basic resource tracking configured${NC}"

# Wait a moment for the configuration to be processed
sleep 5

# Apply Crossplane health checks
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "resource.customizations.health": "hs = {}\nif obj.status ~= nil and obj.status.conditions ~= nil then\n  for i, condition in ipairs(obj.status.conditions) do\n    if condition.type == \"Ready\" then\n      if condition.status == \"True\" then\n        hs.status = \"Healthy\"\n        hs.message = \"Resource is ready\"\n        return hs\n      elseif condition.status == \"False\" then\n        hs.status = \"Degraded\"\n        hs.message = condition.message or \"Not ready\"\n        return hs\n      end\n    end\n  end\nend\nhs.status = \"Progressing\"\nhs.message = \"Waiting for resource\"\nreturn hs"
  }
}'

echo "${GREEN}✅ Crossplane health checks configured${NC}"

# Apply resource relationships
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "resource.customizations.knownTypeFields": "- field: spec.resourceRef\n  type: core/v1/ObjectReference\n- field: spec.claimRef\n  type: core/v1/ObjectReference"
  }
}'

echo "${GREEN}✅ Crossplane resource relationships configured${NC}"

echo ""
echo "${YELLOW}Step 6/8: Restarting ArgoCD Components${NC}"
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout restart statefulset argocd-application-controller -n argocd

echo "Waiting for rollouts to complete..."
kubectl rollout status deployment argocd-server -n argocd
kubectl rollout status deployment argocd-repo-server -n argocd
kubectl rollout status statefulset argocd-application-controller -n argocd
echo "${GREEN}✅ ArgoCD components restarted and ready${NC}"

echo ""
echo "${YELLOW}Step 7/9: Configuring Custom Actions for Approval Button${NC}"
echo "Applying custom action configuration for approval workflow..."
kubectl patch configmap argocd-cm -n argocd --type merge --patch-file "$PROJECT_DIR/manifests/01-argocd/custom-action.yaml"
echo "${GREEN}✅ Custom actions configured for approval button enablement${NC}"

echo ""
echo "${YELLOW}Step 8/9: Setting Custom Password (if provided)${NC}"
if [ -n "$ARGOCD_CUSTOM_PASSWORD" ]; then
  echo "Setting custom password using working script..."
  "$SCRIPT_DIR/set-argocd-password.sh" "$ARGOCD_CUSTOM_PASSWORD"
  echo "${GREEN}✅ Custom password set successfully!${NC}"
else
  echo "${GREEN}✅ Using default random password${NC}"
fi

echo ""
echo "${YELLOW}Step 9/9: User Management Setup${NC}"
echo "Creating additional users (approver, reader) for the approval workflow..."
echo "All users will use the same password: 'password'"
echo ""
echo "Running user creation script..."
"$SCRIPT_DIR/create-argocd-users.sh" "$ARGOCD_CUSTOM_PASSWORD"
echo "${GREEN}✅ User management setup complete${NC}"

echo ""
echo "${GREEN}✅ Fresh ArgoCD Installation Complete!${NC}"
echo ""

echo "Installation Summary:"
echo "  ✅ ArgoCD Core (v2.14.17)"
echo "  ✅ Cluster Admin RBAC Permissions (Full Cluster Access)"
echo "  ✅ Advanced Crossplane Resource Tracking"
echo "  ✅ Health Checks for Crossplane Resources"
echo "  ✅ Resource Relationship Discovery"
echo "  ✅ Custom Actions for Approval Button"
echo "  ✅ Full Cluster Visibility"

echo ""
echo "ArgoCD Credentials:"
if [ -n "$ARGOCD_CUSTOM_PASSWORD" ]; then
  echo "  URL: https://localhost:8080"
  echo "  Username: admin"
  echo "  Password: $ARGOCD_CUSTOM_PASSWORD"
else
  echo "  Run: ./scripts/get-argocd-password.sh"
  echo "  Or set custom password: ./scripts/set-argocd-password.sh"
fi

echo ""
echo "Next steps:"
echo "1. Port-forward ArgoCD: ./scripts/port-forward.sh"
echo "2. Access ArgoCD UI: https://localhost:8080"
echo "3. Configure repositories and applications: ./scripts/configure-argocd.sh"
echo "4. Create additional users (if needed): ./scripts/create-argocd-users.sh"
echo "5. Create Crossplane resources to test tracking"
echo ""
echo "📖 Documentation:"
echo "   - README.md - Overview and architecture"
echo "   - manifests/01-argocd/ - ArgoCD configuration files"
echo "   - manifests/01-argocd/argocd-users.yaml - User account configuration"
echo "   - manifests/01-argocd/argocd-rbac-cm.yaml - RBAC policy configuration"
echo ""
echo "ArgoCD Features Enabled:"
echo "  ✅ Tracks ALL Kubernetes resources (including Crossplane)"
echo "  ✅ Cluster Admin permissions for full cluster access"
echo "  ✅ Advanced Crossplane resource health checks"
echo "  ✅ Resource relationship tracking (resourceRef, claimRef)"
echo "  ✅ Custom actions for Crossplane resource discovery"
echo "  ✅ Approval button enablement for workflow control"
echo "  ✅ Full cluster visibility and resource tracking"
echo ""
echo "To test the system:"
echo "1. Create Crossplane resources (XRDs, Compositions, Claims)"
echo "2. View them in ArgoCD UI with health status and relationships"
echo "3. Test resource discovery and tracking features"

echo ""
echo "${YELLOW}Step 10/10: Setting up Git Repository and Application${NC}"
echo "====================================================="
echo ""
echo "Now setting up Git repository and ArgoCD application with default settings..."
echo "This will create a repository connection and application for GitOps workflow."
echo ""

# Check if environment variables are set for Git credentials
if [ -z "$GIT_USERNAME" ] || [ -z "$GIT_TOKEN" ]; then
  echo "${YELLOW}⚠️  Git credentials not found in environment variables.${NC}"
  echo ""
  echo "To complete the setup, please set your Git credentials:"
  echo "  export GIT_USERNAME='your-git-username'"
  echo "  export GIT_TOKEN='your-git-token'"
  echo ""
  echo "Then run: ./scripts/simple-argocd-setup.sh"
  echo ""
  echo "${GREEN}✅ ArgoCD installation complete!${NC}"
  echo "You can set up the Git repository and application later."
else
  echo "${GREEN}✅ Git credentials found in environment variables${NC}"
  echo "Running simple ArgoCD setup..."
  echo ""
  
  # Run the simple setup script
  "$SCRIPT_DIR/simple-argocd-setup.sh"

  kubectl patch configmap argocd-cm -n argocd --type merge --patch-file "$PROJECT_DIR/manifests/01-argocd/custom-action.yaml"  
  echo ""
  echo "${GREEN}✅ Complete ArgoCD setup finished!${NC}"
  echo ""
  echo "🎉 Everything is ready:"
  echo "  ✅ ArgoCD installed and configured"
  echo "  ✅ Users created (admin, approver, reader)"
  echo "  ✅ Git repository connected"
  echo "  ✅ ArgoCD application created"
  echo "  ✅ Automatic sync enabled"
fi
