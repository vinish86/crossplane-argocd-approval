# ArgoCD ConfigMap Management - kubectl patch Approach

## Why kubectl patch Instead of kubectl apply?

### The Problem
ArgoCD containers (especially `argocd-server` and `argocd-application-controller`) are very sensitive to ConfigMap changes. When using `kubectl apply -f` to replace entire ConfigMaps, especially those containing:

- Complex Lua scripts for health checks
- Large RBAC policy configurations
- Resource customization settings

ArgoCD containers often go into `CrashLoopBackOff` with errors like:
```
configmap "argocd-cm" not found
```

Even though the ConfigMap exists and is properly formatted.

### The Solution: kubectl patch

Using `kubectl patch` with `--type merge` allows us to:

1. **Incremental Updates**: Only update specific fields without replacing the entire ConfigMap
2. **Avoid Crashes**: ArgoCD can process changes gradually without losing its internal state
3. **Safer Operations**: Reduces the risk of configuration corruption
4. **Better Reliability**: Proven to work consistently across different ArgoCD versions

## Implementation in Scripts

### Install Script (`install-argocd-fresh.sh`)

```bash
# Apply basic resource tracking first
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "resource.inclusions": "- apiGroups:\n  - \"*\"\n  kinds:\n  - \"*\"\n  clusters:\n  - \"*\"",
    "resource.exclusions": "",
    "resource.compareoptions": "ignoreAggregatedRoles: false",
    "application.resourceTrackingMethod": "annotation+label"
  }
}'

# Wait for processing
sleep 5

# Apply Crossplane health checks
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "resource.customizations.health": "[lua-script]"
  }
}'

# Wait for processing
sleep 5

# Apply resource relationships
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "resource.customizations.knownTypeFields": "[field-mappings]"
  }
}'
```

### User Creation Script (`create-argocd-users.sh`)

```bash
# Check if ArgoCD CLI is available (required)
if ! command -v argocd &> /dev/null; then
  echo "ArgoCD CLI not found. Install with:"
  echo "  macOS: brew install argocd"
  echo "  Linux: curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
  exit 1
fi

# Get current admin password
echo "Please enter the current ArgoCD admin password:"
read -s ADMIN_PASSWORD

# Apply user accounts using kubectl patch (argocd-cm already exists)
kubectl patch configmap argocd-cm -n argocd --type merge -p '{
  "data": {
    "accounts.approver": "apiKey, login",
    "accounts.reader": "apiKey, login"
  }
}'

# Apply RBAC policies from YAML file (new ConfigMap, safe to use apply)
kubectl apply -f "$PROJECT_DIR/manifests/01-argocd/argocd-rbac-cm.yaml"

# Restart ArgoCD server to pick up new accounts
kubectl rollout restart deployment/argocd-server -n argocd
kubectl rollout status deployment/argocd-server -n argocd --timeout=2m
sleep 10

# Set passwords using ArgoCD CLI
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --username admin --password "$ADMIN_PASSWORD" --insecure

# Set passwords for users
argocd account update-password --account approver --current-password "$ADMIN_PASSWORD" --new-password "$ADMIN_PASSWORD"
argocd account update-password --account reader --current-password "$ADMIN_PASSWORD" --new-password "$ADMIN_PASSWORD"
```

## Best Practices

### 1. Incremental Updates
- Apply changes in small, logical groups
- Wait between patches to allow ArgoCD to process changes
- Use `sleep 5` between complex patches

### 2. Error Handling
- Always check if ArgoCD is ready before applying patches
- Monitor pod status after applying patches
- Have rollback procedures ready

### 3. Patch Structure
- Use `--type merge` for safe updates
- Keep JSON structure simple and readable
- Escape special characters properly in JSON

### 4. Testing
- Test patches in development environment first
- Verify ArgoCD functionality after each patch
- Monitor logs for any configuration errors

## Troubleshooting

### If ArgoCD Still Crashes
1. Check pod logs: `kubectl logs -n argocd deployment/argocd-server`
2. Verify ConfigMap content: `kubectl get configmap argocd-cm -n argocd -o yaml`
3. Restart ArgoCD components: `kubectl rollout restart deployment/argocd-server -n argocd`
4. Check for syntax errors in Lua scripts or YAML

### Recovery Steps
1. Delete problematic ConfigMap entries
2. Restart ArgoCD components
3. Reapply patches one by one
4. Monitor pod status throughout

## Alternative Approaches (Not Recommended)

### kubectl apply -f (Problematic)
```bash
# DON'T DO THIS - Causes crashes
kubectl apply -f argocd-cm.yaml
```

### Direct ConfigMap Replacement (Problematic)
```bash
# DON'T DO THIS - Causes crashes
kubectl replace -f argocd-cm.yaml
```

## Conclusion

The `kubectl patch` approach is the most reliable method for updating ArgoCD ConfigMaps without causing container crashes. It provides:

- ✅ **Stability**: No more CrashLoopBackOff issues
- ✅ **Reliability**: Consistent behavior across environments
- ✅ **Safety**: Incremental updates reduce risk
- ✅ **Maintainability**: Clear, readable patch operations

Always use `kubectl patch` for ArgoCD ConfigMap updates in production environments.
