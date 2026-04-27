---
description: "Reference for writing test/app.bicep files that validate resource types and recipes. Covers extension wiring, application scaffolding, connection patterns, auth variants, and deploy commands."
---

# Skill: Test App Builder

How to write `test/app.bicep` files that validate a resource type end-to-end. Every example is from a real file in this repo.

## Purpose

Every resource type must include a `test/app.bicep` that:
1. Creates an application
2. Creates the resource under test
3. Optionally connects a container to verify connection injection
4. Can be deployed with `rad deploy`

## Extension Wiring

Extensions must match the resource type's camelCase name exactly:

```bicep
extension radius                    // always required
extension redisCaches               // matches Radius.Data/redisCaches
extension mongoDatabases            // matches Radius.Data/mongoDatabases
extension containers                // if using Radius.Compute/containers
extension secrets                   // if using Radius.Security/secrets
```

**Common mistake**: using singular (`redisCache`) instead of plural (`redisCaches`). The extension name must match the type name in the YAML schema.

## Minimal Test App (no auth, no container)

Source: `Data/mongoDatabases/test/app.bicep`

```bicep
extension radius
extension mongoDatabases

param environment string

resource myapp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'mongo-test-app'
  properties: {
    environment: environment
  }
}

resource database 'Radius.Data/mongoDatabases@2025-08-01-preview' = {
  name: 'testdb'
  properties: {
    application: myapp.id
    environment: environment
  }
}
```

Use this pattern when:
- Auth is auto-generated (MongoDB pattern)
- You only need to verify the resource deploys successfully

## Full Test App (with auth + container)

Source: `Data/redisCaches/test/app.bicep`

```bicep
extension radius
extension containers
extension redisCaches
extension secrets

@description('The Radius environment ID')
param environment string

@secure()
param password string

resource myapp 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'myapp'
  properties: {
    environment: environment
  }
}

resource mycontainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'mycontainer'
  properties: {
    environment: environment
    application: myapp.id
    containers: {
      redistest: {
        image: 'ghcr.io/radius-project/samples/demo:latest'
        ports: {
          web: { containerPort: 3000 }
        }
      }
    }
    connections: {
      redis: { source: redis.id }
    }
  }
}

resource redis 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: myapp.id
    size: 'S'
    secretName: redisSecret.name
  }
}

resource redisSecret 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'redissecret'
  properties: {
    environment: environment
    application: myapp.id
    data: {
      PASSWORD: { value: password }
    }
  }
}
```

Use this pattern when:
- You want to verify connection env var injection (`CONNECTION_REDIS_HOST`, etc.)
- Auth uses the secretName pattern (external secret)

## Application Resource Versions

Two versions exist in the repo. Match whichever the closest existing test uses:

| Version | Usage |
|---------|-------|
| `Applications.Core/applications@2023-10-01-preview` | Older tests (redisCaches, postgreSqlDatabases) |
| `Radius.Core/applications@2025-08-01-preview` | Newer tests (mongoDatabases, neo4jDatabases) |

## Decision Tree: Which Pattern to Use

```
Does the technology require auth?
├── No auth needed
│   └── Use minimal pattern (resource only, no container)
├── Auth is auto-generated (MongoDB pattern: username/password in outputs)
│   └── Use minimal pattern (credentials come from recipe)
├── Auth is optional via secretName (Redis, PostgreSQL pattern)
│   └── Use full pattern with secret + container
│       Include: @secure() param password, Radius.Security/secrets resource
└── Auth is always required
    └── Use full pattern with secret + container
```

## Deploy Commands

```bash
# Without auth
rad deploy test/app.bicep

# With auth (password param)
rad deploy test/app.bicep -p password=$(openssl rand -hex 16)

# With specific workspace
rad deploy test/app.bicep -w my-workspace
```

## Validation Checks

After deploying, verify:

```bash
# Check the resource was created
rad resource list <Namespace>/<resourceType>

# Check pods are running (K8s recipes)
kubectl get pods -n default-myapp

# Check connection env vars are injected (if container is present)
kubectl exec -it <pod> -n default-myapp -- env | grep CONNECTION_
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong extension name (`redisCache` not `redisCaches`) | Use exact camelCase plural from YAML |
| Missing `extension secrets` when using secrets | Add it to the extension list |
| Missing `extension containers` when using containers | Add it to the extension list |
| Using `@2025-08-01-preview` for Applications.Core | Check which version the closest test uses |
| Forgetting `@secure()` on password param | Always mark password params as secure |
