# Radius Resource Types & Recipes

This repository contains Radius **Resource Type definitions** (YAML schemas) and **Recipes** (Bicep / Terraform templates) for deploying those resources on AWS, Azure, and Kubernetes.

**References**: [Contributing Guide](../docs/contributing/contributing-resource-types-recipes.md) · [Testing Guide](../docs/contributing/testing-resource-types-recipes.md) · [Radius Docs](https://docs.radapp.io) · [Recipes Overview](https://docs.radapp.io/guides/recipes/overview/) · [Context Schema](https://docs.radapp.io/reference/context-schema/)

## Agents

| Agent | What it does |
|-------|-------------|
| `@resource-type-creator` | End-to-end: research → generate all files → validate. Give it a technology name. |
| `@resource-type-researcher` | (subagent) Produces a technology profile with verified IaC sources |
| `@resource-type-validator` | (subagent) Runs pass/fail checklist against generated files |

## Skills

| Skill | Load when |
|-------|-----------|
| `bicep-recipes` | Writing or debugging a Bicep recipe (K8s or Azure). Includes gotchas. |
| `terraform-recipes` | Writing or debugging a Terraform recipe (K8s or AWS). |
| `schema-design` | Writing a resource type YAML, README, or description block. |
| `iac-module-verification` | Researching AVM / Terraform Registry modules for a technology. |
| `test-app-builder` | Writing a test/app.bicep file. Covers extensions, auth variants, deploy commands. |
| `testing-debugging` | Building, deploying, testing, or debugging a resource type. |

## Repository Layout

```
<Category>/                           # Data/, Security/, Compute/, Messaging/, etc.
└── <resourceTypeName>/               # camelCase, plural (e.g., redisCaches/)
    ├── <resourceTypeName>.yaml       # Resource type definition (schema + examples)
    ├── README.md                     # Platform engineer docs
    ├── recipes/
    │   └── <platform>/               # kubernetes/, azure/, aws/
    │       ├── bicep/*.bicep
    │       └── terraform/{main.tf, var.tf}
    └── test/app.bicep                # Test application
```

## Core Conventions

- **Namespace**: `Radius.<Category>` (e.g., `Radius.Data`)
- **Type names**: camelCase, plural (e.g., `redisCaches`, `postgreSqlDatabases`)
- **API Version**: `2025-08-01-preview`
- **Property prefixes**: `(Required)`, `(Optional)` in descriptions
- **Read-only outputs**: `readOnly: true` — set by recipes, not users
- **Sensitive values**: `x-radius-sensitive: true`
- **K8s labels** (all 5 required): `radapp.io/resource`, `radapp.io/application`, `radapp.io/environment`, `radapp.io/resource-type`, `radapp.io/resource-group`
- **Image tags**: always pinned (`redis:7-alpine`), never `latest`
- **Optional properties**: Bicep uses `.?` then `??`. Terraform uses `try()`.

## Contribution Checklist

- [ ] Folder structure and naming conventions
- [ ] `environment` in `required`; all descriptions prefixed `(Required)` / `(Optional)`
- [ ] YAML description has Bicep examples + `CONNECTION_*` env var list
- [ ] Read-only properties: `readOnly: true`; sensitive: `x-radius-sensitive: true`
- [ ] Recipe outputs match schema readOnly properties exactly
- [ ] All 5 `radapp.io/*` labels on K8s resources
- [ ] Image tags and module versions pinned
- [ ] `test/app.bicep` exists and deploys successfully
- [ ] `make test-recipe` passes locally

## Make Targets

| Target | Description | Parameters |
|--------|-------------|------------|
| `make help` | Show all available targets | — |
| `make install-radius-cli` | Install the Radius CLI | — |
| `make create-radius-cluster` | Create a local k3d cluster with Radius | — |
| `make build` | Build all resource types and recipes | — |
| `make build-resource-type` | Build a single resource type | `TYPE_FOLDER=Data/redisCaches` |
| `make build-bicep-recipe` | Build a Bicep recipe | `RECIPE_PATH=Data/redisCaches/recipes/kubernetes/bicep` |
| `make build-terraform-recipe` | Build a Terraform recipe | `RECIPE_PATH=Data/redisCaches/recipes/kubernetes/terraform` |
| `make test` | Run automated tests for all recipes | — |
| `make test-recipe` | Test a single recipe | `RECIPE_PATH=Data/redisCaches/recipes/kubernetes/bicep` |
| `make list-resource-types` | List resource type folders | — |
| `make list-recipes` | List all recipe folders | — |
| `make clean` | Delete k3d cluster, config, and build artifacts | — |
