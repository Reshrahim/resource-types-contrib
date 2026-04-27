---
description: "Reference for writing Terraform recipes for Kubernetes and AWS platforms. Includes annotated examples from real recipes, try() patterns, dynamic blocks, verified module usage, and AWS provider patterns."
---

# Skill: Terraform Recipe Authoring

Annotated reference for writing Terraform recipes. Every code block is from a real recipe in this repo.

## Kubernetes Terraform Recipe — Complete Annotated Example

Source: `Data/redisCaches/recipes/kubernetes/terraform/main.tf`

### 1. Provider block

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.37.1"
    }
  }
}
```

### 2. Context variable (every Terraform recipe starts with this)

```hcl
variable "context" {
  description = "This variable contains Radius Recipe context."
  type        = any
}
```

### 3. Radius preamble (copy verbatim into every K8s Terraform recipe)

```hcl
locals {
  resource_name      = var.context.resource.name
  application_name   = var.context.application != null ? var.context.application.name : ""
  environment_name   = var.context.environment != null ? var.context.environment.name : ""
  resource_group     = element(split("/", var.context.resource.id), 5)
  namespace          = var.context.runtime.kubernetes.namespace
}
```

### 4. Labels (all 5 required)

```hcl
locals {
  labels = {
    "radapp.io/resource"       = local.resource_name
    "radapp.io/application"    = local.application_name
    "radapp.io/environment"    = local.environment_name
    "radapp.io/resource-type"  = replace(var.context.resource.type, "/", "-")
    "radapp.io/resource-group" = local.resource_group
  }
}
```

### 5. Reading optional properties with `try()`

```hcl
locals {
  secret_name = try(var.context.resource.properties.secretName, "")
  has_secret  = local.secret_name != ""
  size_value  = try(var.context.resource.properties.size, "S")
}
```

**Why `try()` not `lookup()`?** The `context` variable is `type = any` — nested property access would fail with an error if the key doesn't exist. `try()` catches this and returns the fallback.

### 6. Size-to-memory variable (matches Bicep exactly)

```hcl
variable "memory" {
  description = "Memory limits for the Redis container"
  type = map(object({
    memoryRequest = string
  }))
  default = {
    S = { memoryRequest = "128Mi" },
    M = { memoryRequest = "256Mi" },
    L = { memoryRequest = "512Mi" }
  }
}
```

### 7. Deployment resource

```hcl
resource "kubernetes_deployment" "redis" {
  metadata {
    name      = local.resource_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    selector {
      match_labels = {
        "radapp.io/resource" = local.resource_name
      }
    }

    template {
      metadata {
        labels = local.labels          # all 5 labels
      }

      spec {
        container {
          name  = "redis"
          image = "redis:${local.tag}"   # pinned, never 'latest'

          port {
            container_port = local.port
          }

          resources {
            requests = {
              memory = var.memory[local.size_value].memoryRequest
            }
          }

          args = local.has_secret ? ["redis-server", "--requirepass", "$(REDIS_PASSWORD)"] : ["redis-server"]

          # Conditional env block using dynamic
          dynamic "env" {
            for_each = local.has_secret ? [1] : []
            content {
              name = "REDIS_PASSWORD"
              value_from {
                secret_key_ref {
                  name = local.secret_name
                  key  = "PASSWORD"
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Key patterns:
- `match_labels` uses SINGLE label (`radapp.io/resource`)
- Template `labels` gets all 5
- `dynamic "env"` with `for_each = condition ? [1] : []` for conditional blocks
- Image tag is a local, not hardcoded

### 8. Service resource

```hcl
resource "kubernetes_service" "redis" {
  metadata {
    name      = local.resource_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "radapp.io/resource" = local.resource_name
    }

    port {
      port = local.port
    }
  }
}
```

### 9. Result output

```hcl
output "result" {
  value = {
    resources = [
      "/planes/kubernetes/local/namespaces/${local.namespace}/providers/core/Service/${local.resource_name}",
      "/planes/kubernetes/local/namespaces/${local.namespace}/providers/apps/Deployment/${local.resource_name}"
    ]
    values = {
      host = "${kubernetes_service.redis.metadata[0].name}.${kubernetes_service.redis.metadata[0].namespace}.svc.cluster.local"
      port = local.port
    }
  }
}
```

Note: Terraform uses `metadata[0].name` (list index) vs Bicep's `metadata.name`.

---

## AWS Terraform Recipe — Complete Annotated Example

Source: `Data/mongoDatabases/recipes/aws/terraform/main.tf`

### TODO header (required when no verified module exists)

```hcl
# TODO: No verified (official/partner) Terraform module exists for AWS DocumentDB.
# This recipe uses raw aws provider resources (aws_docdb_cluster, aws_docdb_cluster_instance).
# Replace with a verified module if one becomes available on registry.terraform.io.
```

### Provider block (AWS + random)

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
```

### AWS preamble

```hcl
locals {
  resource_name    = var.context.resource.name
  application_name = var.context.application != null ? var.context.application.name : ""
  environment_name = var.context.environment != null ? var.context.environment.name : ""
  resource_group   = element(split("/", var.context.resource.id), 5)

  database = try(var.context.resource.properties.database, local.application_name)
  username = try(var.context.resource.properties.username, "admin")
  port     = 27017

  unique_suffix = substr(sha256(var.context.resource.id), 0, 8)
  cluster_id    = "mongo-${local.unique_suffix}"

  # Networking from environment provider context
  subnet_ids             = var.context.environment.providers.aws.subnet_ids
  vpc_security_group_ids = var.context.environment.providers.aws.security_group_ids

  tags = {
    "radapp.io/resource"       = local.resource_name
    "radapp.io/application"    = local.application_name
    "radapp.io/environment"    = local.environment_name
    "radapp.io/resource-type"  = replace(var.context.resource.type, "/", "-")
    "radapp.io/resource-group" = local.resource_group
  }
}
```

Key differences from K8s:
- AWS networking comes from `var.context.environment.providers.aws`
- Uses `tags` (same keys) instead of `labels`
- Unique naming via `sha256()` + `substr()`

### Password generation

```hcl
resource "random_password" "master" {
  length  = 24
  special = false
}
```

### AWS result with secrets

```hcl
output "result" {
  value = {
    resources = []                              # empty for non-K8s managed resources
    values = {
      host     = aws_docdb_cluster.mongo.endpoint
      port     = local.port
      database = local.database
      username = local.username
    }
    secrets = {
      password         = random_password.master.result
      connectionString = "mongodb://${local.username}:${random_password.master.result}@${aws_docdb_cluster.mongo.endpoint}:${local.port}/${local.database}?tls=true&retryWrites=false"
    }
  }
  sensitive = true                              # required when output contains secrets
}
```

### AWS recipe with verified module (MySQL pattern)

Source: `Data/mySqlDatabases/recipes/aws/terraform/main.tf`

```hcl
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = local.sanitized_identifier
  engine               = "mysql"
  engine_version       = local.version
  family               = "mysql${local.version}"
  major_engine_version = local.version
  instance_class       = var.instanceClass
  db_name              = local.sanitized_database
  username             = try(data.kubernetes_secret.db_credentials.data["USERNAME"], "")
  password             = try(data.kubernetes_secret.db_credentials.data["PASSWORD"], "")
  port                 = local.port
  allocated_storage    = var.allocatedStorage
  storage_type         = "gp3"
  // ...
}
```

When a verified module exists, use it with `version = "~> X.0"` pinning.

---

## Bicep vs Terraform Equivalence Table

These must produce identical outputs for the same platform:

| Concept | Bicep | Terraform |
|---------|-------|-----------|
| Optional property | `context.resource.properties.?size ?? 'S'` | `try(var.context.resource.properties.size, "S")` |
| Conditional block | `hasSecret ? [...] : [...]` | `dynamic "env" { for_each = local.has_secret ? [1] : [] }` |
| Unique name | `uniqueString(context.resource.id)` | `substr(sha256(var.context.resource.id), 0, 8)` |
| Service DNS | `'${svc.metadata.name}.${svc.metadata.namespace}.svc.cluster.local'` | `"${kubernetes_service.x.metadata[0].name}.${kubernetes_service.x.metadata[0].namespace}.svc.cluster.local"` |
| Labels | K8s: `labels` object. Azure: `tags` with `-` not `/` | K8s: `labels` map. AWS: `tags` map |
| Random password | `uniqueString(id, guid(name, user))` | `random_password` resource |
| Resource ID path | string interpolation | string interpolation (same format) |
| Secrets in output | `secrets: { #disable-next-line ... }` | `sensitive = true` on output |
