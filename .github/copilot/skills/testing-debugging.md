---
description: "Reference for building, testing, and debugging Radius resource types and recipes. Includes make targets, common build/deploy failures, debugging workflows, and the pre-submission checklist."
---

# Skill: Testing & Debugging

How to build, test, and debug Radius resource types and recipes. Includes real commands, common failures, and debugging workflows.

## Build Commands

### First time setup

```bash
make install-radius-cli        # Install rad CLI
make create-radius-cluster     # Create local k3d cluster with Radius
```

### Build a resource type

```bash
# Check if already registered (skip build if it is)
rad resource-type list

# Build only if NOT listed
make build-resource-type TYPE_FOLDER=Data/redisCaches
```

### Build recipes

```bash
# Bicep recipe
make build-bicep-recipe RECIPE_PATH=Data/redisCaches/recipes/kubernetes/bicep

# Terraform recipe
make build-terraform-recipe RECIPE_PATH=Data/redisCaches/recipes/kubernetes/terraform
```

### Register recipes

```bash
# Register Bicep recipes
make register RECIPE_TYPE=bicep

# Register Terraform recipes (needs named environment)
make register RECIPE_TYPE=terraform ENVIRONMENT=my-terraform-env
```

### Test

```bash
# Test single recipe
make test-recipe RECIPE_PATH=Data/redisCaches/recipes/kubernetes/bicep

# Test all recipes
make test
```

### Cleanup

```bash
make clean                     # Delete k3d cluster, config, build artifacts
make delete-radius-cluster     # Delete cluster only
```

## Bicep Validation: Use `rad bicep publish`, NOT `az bicep build`

`rad bicep publish` uses the Bicep version bundled with Radius (`~/.rad/bin/bicep`), which is what actually runs at deploy time. `az bicep build` uses a different version and may accept code that fails at deploy.

```bash
rad bicep publish --file kubernetes-redis.bicep --target br:localhost:5000/recipes/redis:latest
rad deploy app.bicep -w my-workspace
```

## Common Build Failures

### BCP318 — Null safety

```
Error BCP318: The type at ".secretName" could not be applied to the target.
```

**Fix**: Use `.?` safe navigation:
```bicep
// Wrong
var name = context.resource.properties.secretName ?? ''
// Right
var name = context.resource.properties.?secretName ?? ''
```

### BCP120 — Deploy-time constant required

```
Error BCP120: This expression is being used in an assignment to the "location" property of the
"Microsoft.XYZ" type, which requires a value that can be calculated at the start of the deployment.
```

**Fix**: Use a parameter, not a runtime reference:
```bicep
// Wrong
location: existingResource.location
// Right
param location string = resourceGroup().location
```

### InvalidTemplate — Property path doesn't exist

```
{"code":"InvalidTemplate","message":"...property 'secretName' doesn't exist..."}
```

This happens at DEPLOY time even if Bicep compiled fine. The `.?` operator is required for optional paths.

### InvalidTagNameCharacters — Azure tags with `/`

```
{"code":"InvalidTagNameCharacters","message":"Tag name 'radapp.io/application' contains invalid characters."}
```

**Fix**: Use `-` instead of `/` in Azure tag names:
```bicep
tags: { 'radapp.io-application': appName }
```

### outputs-should-not-contain-secrets — Linting error

```
Warning outputs-should-not-contain-secrets: Outputs should not contain secrets.
```

**Fix**: Add `#disable-next-line` before each secret in the output:
```bicep
secrets: {
    #disable-next-line outputs-should-not-contain-secrets
    password: password
}
```

## Common Deploy Failures

### Pod CrashLoopBackOff

```bash
# Check pod status
kubectl get pods -n <namespace>

# Check logs for the Radius-created pod
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl describe pod <pod-name> -n <namespace>
```

Common causes:
- Container image doesn't exist or tag is wrong
- Environment variable references a secret that doesn't exist
- Port conflict or misconfiguration

### Recipe output mismatch

```
Error: recipe output property 'host' expected but not found
```

The recipe's `result.values` keys must EXACTLY match the YAML schema's `readOnly: true` properties.

Check:
1. YAML has `host: { readOnly: true }` → recipe output must have `values.host` or `secrets.host`
2. Property names are case-sensitive

### Resource type not found

```
Error: resource type 'Radius.Data/redisCaches' not found
```

```bash
rad resource-type list              # Check if registered
make build-resource-type TYPE_FOLDER=Data/redisCaches    # Build it
make register RECIPE_TYPE=bicep     # Register recipes
```

### Connection variables not injected

If a container's `CONNECTION_<NAME>_<PROP>` env vars are empty:

1. Check the container has a `connections` block pointing to the resource
2. Check the resource's recipe output has those properties in `values` or `secrets`
3. Check `disableDefaultEnvVars` is not set to `true` on the connection

## Debugging Workflow

### Iterating on a Bicep recipe

```bash
# 1. Edit the recipe
# 2. Publish to local registry
rad bicep publish --file kubernetes-redis.bicep --target br:localhost:5000/recipes/redis:dev

# 3. Deploy the test app
rad deploy test/app.bicep -p password=$(openssl rand -hex 16)

# 4. Check pod status
kubectl get pods -n default-myapp

# 5. If failing, check logs
kubectl logs -l radapp.io/resource=redis -n default-myapp

# 6. Delete and retry
rad app delete myapp
```

### Iterating on a Terraform recipe

```bash
# 1. Edit main.tf / var.tf
# 2. Validate syntax
terraform init && terraform validate

# 3. Build and register
make build-terraform-recipe RECIPE_PATH=Data/redisCaches/recipes/kubernetes/terraform
make register RECIPE_TYPE=terraform ENVIRONMENT=my-env

# 4. Deploy and test
rad deploy test/app.bicep
```

## Pre-submission Checklist

Run these before submitting a PR:

```bash
# Build everything for the resource type
make build-resource-type TYPE_FOLDER=<Category>/<resourceType>
make build-bicep-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/bicep
make build-terraform-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/terraform

# Register and test
make register RECIPE_TYPE=bicep
make test-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/bicep

# Full test suite
make test
```
