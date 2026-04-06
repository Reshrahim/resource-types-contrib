# Skill: Radius Resource Type and Recipe Creator

Autonomously research a technology, design its resource type, recipes and generate all files. Minimize user interaction by making informed decisions based on repo patterns and best practices.

## Phases

### Phase 1: Research the technology

Given a technology name, build a knowledge base by researching:

1. **Understand the technology**: what it does, how it works, common usage patterns, deployment models (self-hosted vs managed)
2. **How apps consume it**: what does an application need to connect? (e.g., host, port, credentials, connection string, API key). Think from the app developer's perspective — what do they pass to the SDK/driver?
3. **Deployment landscape**: what are the managed equivalents across platforms (Azure, AWS, K8s)? What deployment-specific details vary vs what stays the same?
4. **Check duplicates**: scan existing repo folders (`Compute/`, `Data/`, `Security/`, etc.)

From this research, derive the schema properties (Phase 2). Recipe-specific details (container images, ports, sizing) are resolved during generation, not here.

### Phase 2: DESIGN

Build this profile **in memory** (not a file):

```yaml
technology:     # name, 1-sentence summary
resourceType:   # camelCase plural
category:       # Data | Compute | Security | Messaging | Network | Observability
namespace:      # Radius.<Category>
requiresAuth:   # true/false (derived from research)
inputs:         # user-configurable props (size, secretName, database, etc.)
outputs:        # read-only props set by recipe (host, port, etc.)
# Recipe-specific (resolved per platform during generation):
#   container image, port, sizing, verified modules
```

**Property design rule**: if a property means the same thing on K8s, Azure, AND AWS → schema. Otherwise → recipe only.

Standard properties (always include):
- `environment` (string, required)
- `application` (string, optional)

If auth needed: add `secretName` referencing a `Radius.Security/secrets` resource.

### Phase 3: CONFIRM

One confirmation. Format:

> "<Technology> is <summary>. I'll create `Radius.<Category>/<type>` with:
> - Inputs: <props>
> - Outputs: <props> (injected as CONNECTION_<NAME>_<PROP>)
> - K8s recipe: <verified module or raw resources with TODO>
> Shall I proceed?"

### Phase 4: GENERATE

**Before writing, read these repo files to match style exactly:**
- `Data/postgreSqlDatabases/postgreSqlDatabases.yaml`
- `Data/postgreSqlDatabases/recipes/kubernetes/bicep/kubernetes-postgresql.bicep`
- `Data/postgreSqlDatabases/recipes/kubernetes/terraform/main.tf`
- `Data/postgreSqlDatabases/README.md`
- `Data/postgreSqlDatabases/test/app.bicep`
- `Security/secrets/secrets.yaml`

---

## Recipe Sourcing

**Verified** = official or partner-badged on Terraform Registry or AVM. Community modules do NOT qualify.

| Platform | Source | Registry |
|---|---|---|
| Azure | AVM modules | azure.github.io/Azure-Verified-Modules/ |
| AWS | Official/Partner TF modules | registry.terraform.io |
| K8s | Official/Partner TF modules (rare) | registry.terraform.io |

- **Verified module exists** → wrap in `module` block, pin version
- **No verified module** → raw TF provider resources + TODO block showing ideal `module` pattern. Flag in Phase 3.
- **Bicep K8s** → always `extension kubernetes` with Deployment/Service (no module registry)

---

## Files to Generate

### 1. `<Category>/<resourceType>/<resourceType>.yaml`

Match format of `Data/postgreSqlDatabases/postgreSqlDatabases.yaml`.

```yaml
namespace: Radius.<Category>
types:
  <resourceType>:
    description: |
      # Must include:
      # 1. What it does (1-2 sentences)
      # 2. Bicep example: create the resource (+ secrets if auth needed)
      # 3. Bicep example: connect a container via connections
      # 4. CONNECTION_<NAME>_<PROP> env var list
    apiVersions:
      '2025-08-01-preview':
        schema:
          type: object
          properties:
            environment:
              type: string
              description: "(Required) Radius Environment ID."
            application:
              type: string
              description: "(Optional) Radius Application ID."
            # input props here
            # output props here with readOnly: true
          required: [environment]
```

Conventions: `(Required)`/`(Optional)` prefixes, `readOnly: true`, `x-radius-sensitive: true`, `enum: [...]`.

### 2. `<Category>/<resourceType>/README.md`

Match format of `Data/postgreSqlDatabases/README.md`. Sections: Overview, Recipes table, Input Properties, Output Properties.

### 3. `<Category>/<resourceType>/recipes/kubernetes/bicep/kubernetes-<resource>.bicep`

Match structure of `Data/postgreSqlDatabases/recipes/kubernetes/bicep/kubernetes-postgresql.bicep`.

```
1. extension kubernetes block
2. param context + common vars (resourceName, applicationName, etc.)
3. Resource-specific vars from context.resource.properties.?prop ?? 'default'
4. Sizing map: var memory = { S: {...} M: {...} L: {...} }
5. Labels: 5 radapp.io/* keys
6. Deployment + Service resources
7. output result = { resources: [...], values: { host, port, ... } }
```

### 4. `<Category>/<resourceType>/recipes/kubernetes/terraform/main.tf`

**If verified module exists:**
```hcl
module "<tech>" {
  source  = "<registry-path>"
  version = "<pinned>"
  # map context → module inputs
}
output "result" { ... }
```

**If no verified module (common for K8s):**
```hcl
# TODO: Replace with verified module when available.
# Expected: module "<tech>" { source = "..." version = "..." }

# Raw resources follow — match existing repo patterns
# variable "context", locals block, kubernetes_deployment, kubernetes_service
# output "result" with resources + values
```

Use `try()` for optional props. Pin image tags. Include all 5 `radapp.io/*` labels.

**Azure**: AVM via `module` — `"Azure/avm-res-<service>/azurerm"`
**AWS**: Official/partner via `module` — `"terraform-aws-modules/<service>/aws"`

### 5. `<Category>/<resourceType>/test/app.bicep`

Match structure of `Data/postgreSqlDatabases/test/app.bicep`.

```bicep
extension radius
extension <resourceType>
// + extension secrets/containers if needed

param environment string
// + @secure() param password string if auth needed

resource myapp 'Radius.Core/applications@2025-08-01-preview' = { ... }
// + secrets resource if auth needed
// + resource type instance with required props
// + container with connections if output props exist
```

---

## After Generation

1. List files created
2. Show build/test commands:
```bash
make build-resource-type TYPE_FOLDER=<Category>/<resourceType>
make build-bicep-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/bicep
make build-terraform-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/terraform
make test-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/bicep
```
3. Ask: "Adjust properties, add platform, or create another type?"

---

## Self-Check

- [ ] camelCase plural name, no duplicate in repo
- [ ] YAML description has Bicep examples + CONNECTION_* env vars
- [ ] Properties: `(Required)`/`(Optional)` prefixes, `readOnly: true`, `required: [...]`
- [ ] Bicep: `??` for optionals. Terraform: `try()` for optionals
- [ ] Recipe outputs match YAML readOnly properties
- [ ] All 5 `radapp.io/*` labels in recipes
- [ ] `result.resources` paths correct
- [ ] Image tags pinned, module versions pinned
- [ ] Verified module used if available; TODO block if not
- [ ] Test app uses correct extension names

## Principles

1. **Autonomous** — research the technology yourself
2. **Opinionated** — make decisions, don't ask
3. **Minimal interaction** — one confirmation, then generate
4. **Match repo patterns** — read existing files first
5. **App-oriented** — properties = what devs need to connect
6. **Platform-portable** — schema works on K8s, Azure, AWS
7. **Verified modules** — official/partner only; TODO block when none exists
8. **Start simple** — K8s Alpha first, iterate later
