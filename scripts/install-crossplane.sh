#!/bin/bash

set -e

echo "🚀 Installing Crossplane with Pause-on-Change System"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Get Slack webhook URL from environment variable
echo ""
echo "${YELLOW}Slack Notification Configuration${NC}"
echo "=================================="
echo ""

# Check if SLACK_WEBHOOK_URL is set in environment
if [ -n "$SLACK_WEBHOOK_URL" ]; then
  echo "${GREEN}✅ Slack webhook URL found in environment variable${NC}"
  echo "  SLACK_WEBHOOK_URL: [HIDDEN]"
  echo "${GREEN}✅ Slack notifications will be configured${NC}"
else
  echo "${YELLOW}⚠️  SLACK_WEBHOOK_URL environment variable not set${NC}"
  echo ""
  echo "To enable Slack notifications, set the environment variable:"
  echo "  export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX'"
  echo ""
  echo "Then run this script again."
  echo ""
  echo "${YELLOW}Skipping Slack configuration for now.${NC}"
  SLACK_WEBHOOK_URL=""
fi

echo ""
echo "${YELLOW}Step 1/6: Installing Crossplane${NC}"
kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -

# Add Crossplane Helm repo
helm repo add crossplane-stable https://charts.crossplane.io/stable 2>/dev/null || true
helm repo update

# Install Crossplane v1.17.6 with environment configs enabled
helm upgrade --install crossplane \
  --namespace crossplane-system \
  --version 1.17.6 \
  --set args='{--enable-environment-configs}' \
  crossplane-stable/crossplane \
  --wait \
  --timeout 5m

echo ""
echo "${YELLOW}Step 2/6: Installing Crossplane Functions${NC}"
kubectl apply -f "$PROJECT_DIR/manifests/05-functions/functions.yaml"

echo ""
echo "${YELLOW}Step 3/6: Waiting for Functions to be healthy${NC}"
echo "This may take a few minutes..."
kubectl wait --for=condition=healthy --timeout=300s function/function-go-templating || true
kubectl wait --for=condition=healthy --timeout=300s function/function-auto-ready || true
kubectl wait --for=condition=healthy --timeout=300s function/function-environment-configs || true

echo ""
echo "${YELLOW}Step 4/6: Installing Crossplane Providers${NC}"
echo "Installing HTTP Provider..."
kubectl apply -f "$PROJECT_DIR/manifests/02-providers/http-provider.yaml"

echo ""
echo "Waiting for HTTP Provider to be healthy..."
kubectl wait --for=condition=healthy --timeout=300s provider/provider-http || true

echo ""
echo "Installing HTTP Provider Config..."
kubectl apply -f "$PROJECT_DIR/manifests/02-providers/http-providerconfig.yaml"

echo ""
echo "Installing Slack Config (EnvironmentConfig)..."
if [ -n "$SLACK_WEBHOOK_URL" ]; then
  # Create EnvironmentConfig with user-provided webhook URL
  kubectl apply -f - <<EOF
apiVersion: apiextensions.crossplane.io/v1alpha1
kind: EnvironmentConfig
metadata:
  name: slack-config
data:
  webhookUrl: "$SLACK_WEBHOOK_URL"
EOF
  echo "${GREEN}✅ Slack EnvironmentConfig created${NC}"
else
  echo "${YELLOW}⚠️  Skipping Slack EnvironmentConfig (no webhook URL provided)${NC}"
  echo "   You can create it later with:"
  echo "   kubectl apply -f manifests/02-providers/slack-environment-config.yaml"
fi

echo ""
echo "${YELLOW}Step 5/6: Installing XRDs (Custom Resource Definitions)${NC}"
kubectl apply -f "$PROJECT_DIR/manifests/03-crds/pausable-xrd.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/03-crds/child-pausable-xrd.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/03-crds/slack-notification-xrd.yaml"

echo ""
echo "${YELLOW}Step 6/6: Installing Compositions${NC}"
kubectl apply -f "$PROJECT_DIR/manifests/04-compositions/pausable-composition.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/04-compositions/child-pausable-composition.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/04-compositions/slack-notification-composition.yaml"

echo ""
echo "${GREEN}✅ Crossplane Installation Complete!${NC}"
echo ""

echo "Crossplane Components Installed:"
echo "  ✅ Crossplane Core (v1.17.6)"
echo "  ✅ Functions (go-templating, auto-ready, environment-configs)"
echo "  ✅ HTTP Provider"
echo "  ✅ XRDs (Pausable, ChildPausable, SlackNotification)"
echo "  ✅ Compositions"
if [ -n "$SLACK_WEBHOOK_URL" ]; then
  echo "  ✅ Slack EnvironmentConfig"
fi

echo ""
echo "Next steps:"
echo "1. Test Crossplane: kubectl get providers,functions,compositions"
echo "2. Create test Pausable resource: kubectl apply -f gitops-repo/pausables/dev-pausable.yaml"
echo "3. Install ArgoCD: ./scripts/install-argocd.sh"
echo ""
echo "📖 Documentation:"
echo "   - README.md - Overview and architecture"
echo "   - manifests/ - All Crossplane resources"
echo ""
echo "To test the pause-on-change functionality:"
echo "1. Create a Pausable claim"
echo "2. Update the claim (change will be paused automatically)"
echo "3. Check the resource status: kubectl get pausable <name> -o yaml"
echo "4. Approve the change by removing the pause annotation"
