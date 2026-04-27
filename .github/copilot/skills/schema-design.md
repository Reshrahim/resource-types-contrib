---
description: "Reference for writing resource type YAML schemas, READMEs, and test/app.bicep files. Includes annotated examples, property categories, authentication patterns, and description block rules."
---

# Skill: Schema Design

How to write resource type YAML schemas, READMEs, and test apps. Every example is from a real file in this repo.

## YAML Schema — Annotated Example

Source: `Data/redisCaches/redisCaches.yaml`

```yaml
namespace: Radius.Data
types:
  redisCaches:                            # camelCase, plural
    description: |
      The Radius.Data/redisCaches Resource Type deploys a Redis cache. Redis is an
      in-memory data structure store commonly used for caching, session storage, and
      message brokering. To deploy a Redis cache, add a redisCaches resource to your
      application definition Bicep file.
      ```
      resource redis 'Radius.Data/redisCaches@2025-08-01-preview' = {
          name: 'redis'
          properties: {
            environment: environment
            application: myApplication.id
            size: 'S'
          }
        }
      ```

      To enable authentication, add a secret resource and reference it...
      ```
        resource redis 'Radius.Data/redisCaches@2025-08-01-preview' = {
          name: 'redis'
          properties: {
            environment: environment
            application: myApplication.id
            size: 'S'
            secretName: redisCredentials.name
          }
        }

        resource redisCredentials 'Radius.Security/secrets@2025-08-01-preview' = {
          name: 'redis-creds'
          properties: {
            environment: environment
            application: myApplication.id
            data: {
              PASSWORD: {
                value: password
              }
            }
          }
        }
      ```

      To connect your container to the cache, create a connection...
      ```
      resource frontend 'Radius.Compute/containers@2025-08-01-preview' = {
        name: 'frontend'
        properties: {
          application: myApplication.id
          environment: environment
          containers: {
            frontend: {
              image: 'frontend:1.25'
              ports: {
                web: { containerPort: 8080 }
              }
            }
          }
          connections: {
            redis: { source: redis.id }
          }
        }
      }
      ```

      The connection automatically injects environment variables...
      - CONNECTION_REDIS_HOST
      - CONNECTION_REDIS_PORT

    apiVersions:
      '2025-08-01-preview':
        schema:
          type: object
          properties:
            environment:
              type: string
              description: "(Required) The Radius Environment ID. Typically set by the rad CLI. Typically value should be `environment`."
            application:
              type: string
              description: "(Optional) The Radius Application ID. `myApplication.id` for example."
            size:
              type: string
              enum: ['S', 'M', 'L']
              description: "(Optional) The size of the Redis cache. Defaults to `S` if not provided."
            secretName:
              type: string
              description: "(Optional) The name of the secret containing the Redis password. If not provided, Redis runs without authentication."
            host:
              type: string
              description: The host name used to connect to the cache.
              readOnly: true
            port:
              type: string
              description: The port number used to connect to the cache.
              readOnly: true
          required: [environment]
```

## Description Block Rules

The description is developer-facing documentation. It MUST include these 4 sections in order:

1. **What it does** — 1-2 sentences
2. **Bicep example: create the resource** — include auth variant if the technology supports it
3. **Bicep example: connect a container** — show `connections` block
4. **CONNECTION env var list** — one per readOnly property

The connection name in the env vars matches what the developer puts in `connections: { <name>: ... }`. Use the technology name (e.g., `redis`, `mongodb`, `postgresql`).

## Property Categories

### Always present (every resource type)

| Property | Type | Prefix | Notes |
|----------|------|--------|-------|
| `environment` | `string` | `(Required)` | Always in `required: [environment]` |
| `application` | `string` | `(Optional)` | Usually optional |

### Input properties (user-configurable)

Only include properties that apply across ALL platforms. If a property only makes sense on Azure or K8s, it belongs in the recipe, not the schema.

| Pattern | Example | When to use |
|---------|---------|-------------|
| Size enum | `enum: ['S', 'M', 'L']` | Resource has configurable scaling |
| Version enum | `enum: ['7.0', '8.0']` | Multiple major versions exist |
| `secretName` | `type: string` | Optional auth via external K8s secret |
| `username` / `password` | `type: string`, `x-radius-sensitive: true` on password | Direct credentials (MongoDB pattern) |
| `database` | `type: string` | Database name is user-configurable |

### Output properties (set by recipes, readOnly)

| Property | Type | Common for |
|----------|------|-----------|
| `host` | `string` | All network-accessible resources |
| `port` | `integer` or `string` | All network-accessible resources |
| `database` | `string` | Databases |
| `username` | `string` | Authenticated resources |
| `password` | `string` + `x-radius-sensitive: true` | Authenticated resources |
| `connectionString` | `string` + `x-radius-sensitive: true` | Databases with URI protocol |

Output descriptions do NOT get `(Required)` / `(Optional)` prefixes. They use plain text OR `(Read-only)`:
- redisCaches style: `The host name used to connect to the cache.` (plain)
- mongoDatabases style: `(Read-only) The host name used to connect to the database.`
- Either is acceptable; match whichever existing type is closest to your technology.

## Authentication Patterns

### Pattern A: Optional auth via secretName (Redis, PostgreSQL)

Schema:
```yaml
secretName:
  type: string
  description: "(Optional) The name of the secret containing the <tech> password. If not provided, <tech> runs without authentication."
```

How the recipe uses it:
- Reads K8s secret by name → `secretKeyRef` in container env
- Without `secretName`, runs without auth

Test app: include secret + `@secure() param password string`

### Pattern B: Auto-generated credentials (MongoDB)

Schema:
```yaml
username:
  type: string
  description: "(Optional) The admin username. Defaults to `admin` if not specified."
password:
  type: string
  x-radius-sensitive: true
  readOnly: true
  description: "(Read-only) The password for connecting to the database."
```

How the recipe uses it:
- Optionally reads `username` from properties
- Generates password via `uniqueString()` / `random_password`
- Returns both in result output

Test app: minimal, no secrets needed (auto-generated)

### Pattern C: No auth (simple resources)

No auth-related properties. Recipe deploys with defaults.

## README Pattern

Source: `Data/redisCaches/README.md`

```markdown
# Radius.Data/redisCaches

## Overview

The **Radius.Data/redisCaches** resource type represents a Redis cache. It allows
developers to create and easily connect to a Redis cache as part of their Radius
applications.

Developer documentation is embedded in the resource type definition YAML file, and
it is accessible via the `rad resource-type show Radius.Data/redisCaches` command.

## Recipes

|Platform| IaC Language| Recipe Name | Stage |
|---|---|---|---|
| Kubernetes | Bicep | kubernetes-redis.bicep | Alpha |
| Kubernetes | Terraform | main.tf | Alpha |

## Recipe Input Properties

Properties for the **Radius.Data/redisCaches** resource type are provided via the
[Recipe Context](https://docs.radapp.io/reference/context-schema/) object:

- `context.properties.size` (string, optional): The size of the Redis cache. Defaults to `S`.
- `context.properties.secretName` (string, optional): The name of the secret containing the Redis password.

## Recipe Output Properties

The **Radius.Data/redisCaches** resource type expects the following output properties:

- `context.properties.host` (string): The hostname used to connect to the cache.
- `context.properties.port` (integer): The port number used to connect to the cache.
```

## test/app.bicep Patterns

### With auth (Redis pattern — secretName + password param)

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

### Without auth (MongoDB pattern — auto-generated credentials)

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

### Key details about test apps

- `extension` names must match the resource type's camelCase name: `extension redisCaches`, `extension mongoDatabases`
- Add `extension containers` when using `Radius.Compute/containers`
- Add `extension secrets` when using `Radius.Security/secrets`
- Application resource: uses `Applications.Core/applications@2023-10-01-preview` (some tests) OR `Radius.Core/applications@2025-08-01-preview` (newer tests). Match whichever the closest existing test uses.
- Container resource: `Radius.Compute/containers@2025-08-01-preview`
- If auth is optional, test WITHOUT auth (simpler). If auth is required, include it.
- Deploy with: `rad deploy app.bicep -p password=$(openssl rand -hex 16)`
