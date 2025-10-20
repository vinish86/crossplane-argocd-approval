#!/bin/bash

set -e

echo "🎯 Crossplane + ArgoCD Master Installation Script"
echo "================================================"
echo ""
echo "${YELLOW}⚠️  IMPORTANT: Set Environment Variables First!${NC}"
echo "=============================================="
echo ""
echo "Before running this script, please set the following environment variables:"
echo ""
echo "${GREEN}# Required Environment Variables:${NC}"
echo "export GIT_USERNAME=\"your-git-username\""
echo "export GIT_TOKEN=\"your-git-token\""
echo ""
echo "${GREEN}# Optional Environment Variable:${NC}"
echo "export SLACK_WEBHOOK_URL=\"https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX\""
echo ""
echo "${YELLOW}💡 Example:${NC}"
echo "export GIT_USERNAME=\"your-git-username\""
echo "export GIT_TOKEN=\"your-git-token\""
echo "export SLACK_WEBHOOK_URL=\"https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX\""
echo "./scripts/master-install.sh"
echo ""
echo "${BLUE}Press Enter to continue or Ctrl+C to exit and set environment variables...${NC}"
read -r
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Function to check if a component is installed
check_component_installed() {
  local component="$1"
  case "$component" in
    "crossplane")
      kubectl get namespace crossplane-system &>/dev/null
      ;;
    "argocd")
      kubectl get namespace argocd &>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# Function to show installation status
show_status() {
  echo ""
  echo "${BLUE}Current Installation Status:${NC}"
  echo "================================"
  
  if check_component_installed "crossplane"; then
    echo "  ✅ Crossplane: Installed"
  else
    echo "  ❌ Crossplane: Not installed"
  fi
  
  if check_component_installed "argocd"; then
    echo "  ✅ ArgoCD: Installed"
  else
    echo "  ❌ ArgoCD: Not installed"
  fi
  echo ""
}

# Function to check environment variables
check_environment() {
  echo ""
  echo "${BLUE}Environment Variables Check:${NC}"
  echo "================================"
  
  local missing_vars=()
  
  if [ -z "$GIT_USERNAME" ]; then
    missing_vars+=("GIT_USERNAME")
  else
    echo "  ✅ GIT_USERNAME: Set"
  fi
  
  if [ -z "$GIT_TOKEN" ]; then
    missing_vars+=("GIT_TOKEN")
  else
    echo "  ✅ GIT_TOKEN: Set"
  fi
  
  if [ -z "$SLACK_WEBHOOK_URL" ]; then
    missing_vars+=("SLACK_WEBHOOK_URL")
    echo "  ⚠️  SLACK_WEBHOOK_URL: Not set (optional)"
  else
    echo "  ✅ SLACK_WEBHOOK_URL: Set"
  fi
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    echo ""
    echo "${YELLOW}⚠️  Missing required environment variables:${NC}"
    for var in "${missing_vars[@]}"; do
      if [ "$var" != "SLACK_WEBHOOK_URL" ]; then
        echo "  • $var"
      fi
    done
    echo ""
    echo "To set them:"
    echo "  export GIT_USERNAME='your-git-username'"
    echo "  export GIT_TOKEN='your-git-token'"
    echo "  export SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...'  # Optional"
    echo ""
    return 1
  fi
  
  echo ""
  echo "${GREEN}✅ All required environment variables are set${NC}"
  return 0
}

# Function to install Crossplane
install_crossplane() {
  echo ""
  echo "${YELLOW}Installing Crossplane...${NC}"
  echo "=========================="
  
  if ! "$SCRIPT_DIR/install-crossplane.sh"; then
    echo "${RED}❌ Crossplane installation failed${NC}"
    return 1
  fi
  
  echo "${GREEN}✅ Crossplane installation completed${NC}"
  return 0
}

# Function to install ArgoCD
install_argocd() {
  echo ""
  echo "${YELLOW}Installing ArgoCD...${NC}"
  echo "======================="
  
  if ! "$SCRIPT_DIR/install-argocd-fresh.sh"; then
    echo "${RED}❌ ArgoCD installation failed${NC}"
    return 1
  fi
  
  echo "${GREEN}✅ ArgoCD installation completed${NC}"
  return 0
}

# Function to uninstall Crossplane
uninstall_crossplane() {
  echo ""
  echo "${YELLOW}Uninstalling Crossplane...${NC}"
  echo "============================"
  
  if ! "$SCRIPT_DIR/uninstall-crossplane.sh"; then
    echo "${RED}❌ Crossplane uninstallation failed${NC}"
    return 1
  fi
  
  echo "${GREEN}✅ Crossplane uninstallation completed${NC}"
  return 0
}

# Function to uninstall ArgoCD
uninstall_argocd() {
  echo ""
  echo "${YELLOW}Uninstalling ArgoCD...${NC}"
  echo "========================"
  
  if ! "$SCRIPT_DIR/uninstall-argocd.sh"; then
    echo "${RED}❌ ArgoCD uninstallation failed${NC}"
    return 1
  fi
  
  echo "${GREEN}✅ ArgoCD uninstallation completed${NC}"
  return 0
}

# Function for fresh installation
fresh_install() {
  echo ""
  echo "${GREEN}🚀 Starting Fresh Installation${NC}"
  echo "================================="
  
  # Check environment variables
  if ! check_environment; then
    echo "${RED}❌ Cannot proceed without required environment variables${NC}"
    return 1
  fi
  
  # Install Crossplane
  if ! install_crossplane; then
    return 1
  fi
  
  # Install ArgoCD
  if ! install_argocd; then
    return 1
  fi
  
  echo ""
  echo "${GREEN}🎉 Fresh Installation Complete!${NC}"
  echo "================================="
  echo ""
  echo "Both Crossplane and ArgoCD have been installed successfully."
  echo ""
  echo "Next steps:"
  echo "1. Access ArgoCD UI: ./scripts/port-forward.sh"
  echo "2. Test Crossplane: kubectl get providers,functions,compositions"
  echo "3. Check ArgoCD application: kubectl get applications -n argocd"
  echo ""
  echo "User credentials:"
  echo "  • Admin: admin / password"
  echo "  • Approver: approver / password"
  echo "  • Reader: reader / password"
}

# Function for reinstallation
reinstall() {
  echo ""
  echo "${YELLOW}🔄 Starting Reinstallation${NC}"
  echo "============================"
  
  # Check environment variables
  if ! check_environment; then
    echo "${RED}❌ Cannot proceed without required environment variables${NC}"
    return 1
  fi
  
  # Uninstall existing installations
  echo ""
  echo "${YELLOW}Step 1/4: Uninstalling existing components${NC}"
  
  if check_component_installed "argocd"; then
    echo "Uninstalling ArgoCD..."
    if ! uninstall_argocd; then
      echo "${RED}❌ Failed to uninstall ArgoCD${NC}"
      return 1
    fi
  else
    echo "ArgoCD not installed, skipping..."
  fi
  
  if check_component_installed "crossplane"; then
    echo "Uninstalling Crossplane..."
    if ! uninstall_crossplane; then
      echo "${RED}❌ Failed to uninstall Crossplane${NC}"
      return 1
    fi
  else
    echo "Crossplane not installed, skipping..."
  fi
  
  # Wait a moment for cleanup
  echo ""
  echo "Waiting for cleanup to complete..."
  sleep 5
  
  # Install fresh
  echo ""
  echo "${YELLOW}Step 2/4: Installing Crossplane${NC}"
  if ! install_crossplane; then
    return 1
  fi
  
  echo ""
  echo "${YELLOW}Step 3/4: Installing ArgoCD${NC}"
  if ! install_argocd; then
    return 1
  fi
  
  echo ""
  echo "${YELLOW}Step 4/4: Verification${NC}"
  show_status
  
  echo ""
  echo "${GREEN}🎉 Reinstallation Complete!${NC}"
  echo "============================="
  echo ""
  echo "Both Crossplane and ArgoCD have been reinstalled successfully."
  echo ""
  echo "Next steps:"
  echo "1. Access ArgoCD UI: ./scripts/port-forward.sh"
  echo "2. Test Crossplane: kubectl get providers,functions,compositions"
  echo "3. Check ArgoCD application: kubectl get applications -n argocd"
  echo ""
  echo "User credentials:"
  echo "  • Admin: admin / password"
  echo "  • Approver: approver / password"
  echo "  • Reader: reader / password"
}

# Main menu
show_menu() {
  echo ""
  echo "${BLUE}Installation Options:${NC}"
  echo "======================"
  echo ""
  echo "1) Fresh Install Crossplane + ArgoCD (default)"
  echo "2) Reinstall Crossplane + ArgoCD"
  echo "3) Exit"
  echo ""
}

# Main execution
main() {
  # Show current status
  show_status
  
  # Show menu
  show_menu
  
  # Get user choice
  echo -n "Please select an option (1-3) [default: 1]: "
  read -r choice
  
  # Default to option 1 if no input
  if [ -z "$choice" ]; then
    choice="1"
  fi
  
  case "$choice" in
    "1")
      fresh_install
      ;;
    "2")
      reinstall
      ;;
    "3")
      echo ""
      echo "${YELLOW}Exiting...${NC}"
      exit 0
      ;;
    *)
      echo ""
      echo "${RED}❌ Invalid option. Please select 1, 2, or 3.${NC}"
      echo ""
      main
      ;;
  esac
}

# Run main function
main
