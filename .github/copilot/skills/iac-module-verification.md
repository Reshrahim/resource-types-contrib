---
description: "Reference for finding, verifying, and pinning Infrastructure-as-Code modules. Covers AVM (Azure), Terraform Registry (AWS), version pinning rules, and the verified-vs-community decision flow."
---

# Skill: IaC Module Verification

How to find, verify, and pin Infrastructure-as-Code modules for Radius recipes.

## What counts as "verified"

| Badge | Published by | Use in recipe? |
|-------|-------------|---------------|
| **Official** | Cloud provider (HashiCorp, Microsoft, AWS) | Yes |
| **Partner** | Technology vendor with registry partnership | Yes |
| **Community** | Individual or unverified org | **No** |

Community modules do NOT qualify regardless of stars or downloads.

## Azure — Azure Verified Modules (AVM)

### Where to look

- **Bicep** (preferred): `br/public:avm/res/<provider>/<type>:<version>`
  - Catalog: https://azure.github.io/Azure-Verified-Modules/indexes/bicep/bicep-resource-modules/
- **Terraform**: `Azure/avm-res-<provider>-<type>/azurerm`
  - Catalog: https://azure.github.io/Azure-Verified-Modules/indexes/terraform/tf-resource-modules/
  - Also on https://registry.terraform.io (search `avm-res-`)

### How to find the right module

1. Identify the Azure service: e.g., Azure Cache for Redis → `Microsoft.Cache/redis`
2. Map the ARM provider to AVM path: `Microsoft.Cache/redis` → `avm/res/cache/redis`
3. Check the catalog for the latest version
4. Pin it: `br/public:avm/res/cache/redis:0.7.1`

### Known AVM modules for technologies in this repo

| Technology | Azure Service | Bicep Module | Version |
|-----------|---------------|-------------|---------|
| MongoDB | Cosmos DB for MongoDB vCore | `avm/res/document-db/mongo-cluster` | `0.2.0` |
| PostgreSQL | Azure DB for PostgreSQL Flex | `avm/res/db-for-postgre-sql/flexible-server` | check catalog |
| MySQL | Azure DB for MySQL Flex | `avm/res/db-for-my-sql/flexible-server` | check catalog |
| Redis | Azure Cache for Redis | `avm/res/cache/redis` | check catalog |
| Neo4j | — | No managed service | — |
| RabbitMQ | — | No managed service | — |
| Kafka | Event Hubs (Kafka protocol) | `avm/res/event-hub/namespace` | check catalog |
| Elasticsearch | — | No managed service | — |

### Real example: Azure Bicep with AVM

From `Data/mongoDatabases/recipes/azure/bicep/azure-mongo.bicep`:

```bicep
module mongoCluster 'br/public:avm/res/document-db/mongo-cluster:0.2.0' = {
  name: '${uniqueName}-deployment'
  params: {
    name: uniqueName
    location: location
    administratorLogin: username
    administratorLoginPassword: password
    nodeCount: 1
    sku: 'M30'
    storage: 32
    createMode: 'Default'
    highAvailabilityMode: 'Disabled'
  }
}
```

## AWS — Terraform Registry

### Where to look

- https://registry.terraform.io/browse/modules
- Search: technology name + "aws"
- Filter badge: **Official** or **Partner** only

### Known AWS modules

| Technology | AWS Service | Verified Module | Source |
|-----------|-------------|----------------|--------|
| MySQL | RDS | Yes (Official) | `terraform-aws-modules/rds/aws` ~> 6.0 |
| MongoDB | DocumentDB | **No** | Use raw `aws_docdb_*` resources + TODO block |
| PostgreSQL | RDS | Check registry | `terraform-aws-modules/rds/aws` ~> 6.0 (same module, engine=postgres) |
| Redis | ElastiCache | Check registry | — |
| RabbitMQ | Amazon MQ | Check registry | — |
| Kafka | Amazon MSK | Check registry | — |

### Real example: AWS Terraform with verified module

From `Data/mySqlDatabases/recipes/aws/terraform/main.tf`:

```hcl
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier           = local.sanitized_identifier
  engine               = "mysql"
  engine_version       = local.version
  instance_class       = var.instanceClass
  db_name              = local.sanitized_database
  username             = try(data.kubernetes_secret.db_credentials.data["USERNAME"], "")
  password             = try(data.kubernetes_secret.db_credentials.data["PASSWORD"], "")
  port                 = local.port
  allocated_storage    = var.allocatedStorage
  storage_type         = "gp3"
  create_db_subnet_group = true
  subnet_ids             = jsondecode(var.subnetIds)
  vpc_security_group_ids = [module.rds_security_group.security_group_id]
  skip_final_snapshot    = true
  tags                   = local.tags
}
```

### Real example: AWS Terraform WITHOUT verified module

From `Data/mongoDatabases/recipes/aws/terraform/main.tf`:

```hcl
# TODO: No verified (official/partner) Terraform module exists for AWS DocumentDB.
# This recipe uses raw aws provider resources (aws_docdb_cluster, aws_docdb_cluster_instance).
# Replace with a verified module if one becomes available on registry.terraform.io.

resource "aws_docdb_cluster" "mongo" {
  cluster_identifier     = local.cluster_id
  engine                 = "docdb"
  master_username        = local.username
  master_password        = random_password.master.result
  port                   = local.port
  db_subnet_group_name   = aws_docdb_subnet_group.mongo.name
  vpc_security_group_ids = local.vpc_security_group_ids
  skip_final_snapshot    = true
  deletion_protection    = false
  tags                   = local.tags
}
```

The TODO block is mandatory when no verified module is used.

## Kubernetes

K8s almost never has verified Terraform modules for specific technologies.

- **Bicep**: Always `extension kubernetes` with raw `apps/Deployment` + `core/Service`
- **Terraform**: Always `hashicorp/kubernetes` provider `>= 2.37.1` with raw resources

## Version Pinning Rules

| Context | Format | Example |
|---------|--------|---------|
| Bicep AVM module | Exact version in ref | `br/public:avm/res/cache/redis:0.7.1` |
| Terraform module | Pessimistic constraint | `version = "~> 6.0"` |
| Terraform provider | Minimum version | `version = ">= 2.37.1"` |
| Container image | Pinned tag, never `latest` | `redis:7-alpine`, `postgres:16-alpine`, `mongo:8.0` |
| Terraform core | Minimum version | `required_version = ">= 1.5"` |

## Decision flow for a new recipe

```
Is there an AVM / verified TF module?
├── Yes → Use it. Pin version. Reference in recipe.
└── No  → Use raw provider resources.
          Add TODO block at top of file.
          Comment which resources are used.
```
