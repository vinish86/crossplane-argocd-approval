# ArgoCD Setup Scripts - Default Values

## Simple ArgoCD Setup Script

The `simple-argocd-setup.sh` script uses smart defaults for quick setup, referencing the structure from [install-all.sh](https://github.com/vinish86/crossplane-argocd-approval/blob/main/scripts/install-all.sh).

### Default Values

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| **Repository URL** | `https://github.com/vinish86/crossplane-argocd-approval.git` | Git repository URL |
| **Repository Name** | `crossplane-argocd-approval` | Name for the ArgoCD repository secret |
| **Sync Directory** | `gitops-repo/pausables` | Path in repository to sync from |
| **Application Name** | `crossplane-argocd-approval-app` | Name of the ArgoCD application |
| **Target Namespace** | `default` | Kubernetes namespace to deploy to |

### Required Inputs

You only need to provide:

1. **Git Username** - Your Git username
2. **Git Password/Token** - Your Git password or access token

### Usage

```bash
# Run the simple setup script
./scripts/simple-argocd-setup.sh

# Choose option 1: Configure Private Git Repository with Token + Create ArgoCD Application
# Press Enter to use default repository URL: https://github.com/vinish86/crossplane-argocd-approval.git
# Press Enter to use default repository name: crossplane-argocd-approval
# Enter your Git username
# Enter your Git password/token
# Press Enter to use default application name: crossplane-argocd-approval-app
# Press Enter to use default sync path: gitops-repo/pausables
# Press Enter to use default namespace: default
# Choose sync policy (1-4)
```

### Example Workflow

1. **Repository Setup**: Creates ArgoCD repository secret with your credentials
2. **Application Creation**: Creates ArgoCD application pointing to your repository
3. **Sync Configuration**: Configures sync policy and target namespace
4. **Ready to Use**: Your ArgoCD application is ready to sync from your Git repository

### Override Defaults

You can override any default value by providing your own input when prompted:

- **Repository Name**: Enter custom name instead of pressing Enter
- **Application Name**: Enter custom name instead of pressing Enter  
- **Sync Path**: Enter custom path instead of pressing Enter
- **Target Namespace**: Enter custom namespace instead of pressing Enter

### Next Steps

After setup completion:

1. Port-forward ArgoCD: `./scripts/port-forward.sh`
2. Access ArgoCD UI: `https://localhost:8080`
3. View your application in ArgoCD UI
4. Push your manifests to the `gitops-repo/pausables` directory in your repository

### Related Scripts

- `configure-argocd.sh` - Full interactive configuration with all options
- `quick-argocd-setup.sh` - Quick setup with 4 options
- `create-argocd-app.sh` - Command-line tool for automation
- `example-argocd-setup.sh` - Examples and tutorials
