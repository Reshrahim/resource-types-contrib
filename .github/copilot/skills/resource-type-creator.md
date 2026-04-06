# Skill: Radius Resource Type and Recipe Creator

Autonomously research a technology, design its resource type, and generate all files. Each phase produces a concrete output.

## Principles

1. **Autonomous** — research the technology yourself
2. **Opinionated** — make decisions, don't ask
3. **Each phase produces output** — profile, files, validation results
4. **Match repo patterns** — read existing files first
5. **App-oriented** — properties = what devs need to connect
6. **Platform-portable** — schema works on K8s, Azure, AWS
7. **Verified IaC only** — official/partner modules; TODO block when none exists

## Phases

### Phase 1: RESEARCH → output: Technology Profile

Given a technology name, research and produce a technology profile:

1. **Understand the technology**: what it does, how it works, deployment models (self-hosted vs managed)
2. **How apps consume it**: what does an app need to connect? Think from the developer's perspective — what do they pass to the SDK/driver?
3. **Deployment landscape**: managed equivalents across platforms (Azure, AWS, K8s). What varies vs what stays the same?
4. **IaC sources**: for each platform, identify verified IaC modules. **Verified** = official or partner-badged on Terraform Registry or AVM. Community modules do NOT qualify.

   | Platform | Source | Registry |
   |---|---|---|
   | Azure | AVM modules | azure.github.io/Azure-Verified-Modules/ |
   | AWS | Official/Partner TF modules | registry.terraform.io |
   | K8s | Official/Partner TF modules (rare) | registry.terraform.io |

   - Verified module exists → use it, pin version
   - No verified module → raw provider resources + TODO block
   - Bicep K8s → always `extension kubernetes` with Deployment/Service

5. **Check duplicates**: scan existing repo folders (`Compute/`, `Data/`, `Security/`, etc.)

**Output** — present the technology profile to the user:

```yaml
technology:     # name, 1-sentence summary
resourceType:   # camelCase plural
category:       # Data | Compute | Security | Messaging | Network | Observability
namespace:      # Radius.<Category>
requiresAuth:   # true/false
inputs:         # user-configurable props (only props that apply across ALL platforms)
outputs:        # read-only props set by recipe (host, port, etc.)
iacSources:
  kubernetes:   # container image:tag, provider, or verified module
  azure:        # managed service + verified AVM module (or null)
  aws:          # managed service + verified TF module (or null)
```

Schema design rule: if a property only applies to one platform, it belongs in the recipe, not the schema.

### Phase 2: DESIGN → output: Generated files

**Before writing, read an existing resource type in the repo to match style exactly.** Pick the closest match to the technology being created (e.g., a Data type for a database, a Security type for credentials). Read its:
- `<type>.yaml`, `README.md`, `test/app.bicep`
- `recipes/kubernetes/bicep/*.bicep` and `recipes/kubernetes/terraform/main.tf`

If the technology needs auth, also read `Security/secrets/secrets.yaml`.

Generate these 5 files, matching the reference type's style:

#### `<Category>/<resourceType>/<resourceType>.yaml`

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
            # input props + output props (readOnly: true)
          required: [environment]
```

Conventions: `(Required)`/`(Optional)` prefixes, `readOnly: true`, `x-radius-sensitive: true`, `enum: [...]`.

#### `<Category>/<resourceType>/README.md`

Sections: Overview, Recipes table, Input Properties, Output Properties.

#### Recipes: `recipes/<platform>/<lang>/`

**All recipes must:**
- Read input from `context.resource.properties`
- Output `result` with `resources` (list of managed resource paths) and `values` (connection details)
- Bicep: use `??` for optional props. Terraform: use `try()`
- Pin all image tags and module versions

**Per platform:**

| Platform | Bicep | Terraform |
|----------|-------|-----------|
| K8s | `extension kubernetes` → Deployment + Service, 5 `radapp.io/*` labels, sizing map | `kubernetes` provider or verified module. No verified module → raw resources + TODO |
| Azure | AVM Bicep module (azure.github.io/Azure-Verified-Modules/) | AVM Terraform module (same registry) |
| AWS | Bicep extensibility for AWS resources | Official/partner module from registry.terraform.io |

#### `<Category>/<resourceType>/test/app.bicep`

```bicep
extension radius
extension <resourceType>
// + extension secrets/containers if needed
param environment string
// + @secure() param password string if auth REQUIRED
// If auth is optional, generate test WITHOUT auth (simpler default path)
resource myapp 'Radius.Core/applications@2025-08-01-preview' = { ... }
```

Present all generated files to the user for confirmation.

### Phase 3: VALIDATE → output: Self-check results

Run the self-check against all generated files. Report pass/fail for each:

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
- [ ] Bicep and Terraform recipes produce consistent outputs

Show build/test commands:
```bash
make build-resource-type TYPE_FOLDER=<Category>/<resourceType>
make build-bicep-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/bicep
make build-terraform-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/terraform
make test-recipe RECIPE_PATH=<Category>/<resourceType>/recipes/kubernetes/bicep
```

Ask: "Adjust properties, add platform, or create another type?"
