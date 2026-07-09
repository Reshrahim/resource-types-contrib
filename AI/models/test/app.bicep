// Developer-facing definition that deploys the REAL Radius.AI/models resource type
// (authored in this repo at AI/models/models.yaml). The platform engineer wired
// its recipe to a standard Azure Verified Module (see the recipe pack recipepack/azure/aks-recipepack.bicep), so this
// definition carries no module details — Radius provisions a real Azure OpenAI
// account with a chat deployment and maps the module's `endpoint` output onto
// `properties.endpoint` and its sensitive `primaryKey` output into the managed
// secret via `outputs.secrets` (surfaced on the resource as the readOnly `secrets`
// reference).
//
// This test deploys a real, third-party application — LiteLLM (the widely used LLM
// gateway/proxy) — that connects to the provisioned Azure OpenAI chat deployment and
// proves the end-to-end app -> model path with a real chat completion. LiteLLM is a
// small, self-hostable image (no bundled ML runtimes), so it is a lightweight stand-in
// for a real LLM consumer. Note: Azure OpenAI quota is region- and subscription-
// sensitive and may fail before connectivity is possible in constrained regions.

extension radius
extension models
extension containerImages
@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'llm-azure-app-test'
  properties: {
    environment: environment
  }
}

resource model 'Radius.AI/models@2025-08-01-preview' = {
  name: 'model'
  properties: {
    environment: environment
    application: app.id
    model: 'gpt-5-mini'
  }
}

// Radius.Compute/containerImages builds a container image from source inside the
// cluster (dynamic-rp's rootless BuildKit sidecar) and pushes it to the registry
// configured on the recipe. This is a DECOUPLED build check: the litellmctr
// container below keeps running the PUBLISHED `ghcr.io/berriai/litellm` image, so
// the app's data-path verification does not depend on the cluster being able to
// pull the freshly built image. Reaching a successful deploy proves the
// build-and-push path works; `imageReference` is populated with the pushed ref.
//
// Build target choice: litellm itself is a heavy Python build that in-cluster
// would push the already disk-sensitive llm runner into ENOSPC. Instead we build
// a LIGHTER upstream — mccutchen/go-httpbin, a tiny self-contained multi-stage Go
// build (distroless final image) — which exercises the exact same BuildKit
// clone -> build -> push path far more cheaply. Any small OSS repo that builds
// cleanly is acceptable for a decoupled check; the built image is not run here.
resource goHttpbinImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'go-httpbin-image'
  properties: {
    environment: environment
    application: app.id
    // Set an explicit tag. The recipe's tag-validation precondition interpolates
    // ${local.user_tag} into its error_message, which Terraform evaluates eagerly;
    // leaving tag unset makes that null and fails with "Cannot include a null value
    // in a string template" before the build even starts. A concrete tag avoids
    // that path (and pins the pushed image ref).
    tag: 'v2.23.1'
    build: {
      // Immutable ref so the recipe's content-addressable tag is stable.
      source: 'git::https://github.com/mccutchen/go-httpbin.git//?ref=v2.23.1'
      // Single-arch keeps the in-cluster build fast and avoids cross-compilation
      // failures; the runner and cluster are linux/amd64.
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

// LiteLLM (ghcr.io/berriai/litellm) is a standard, third-party OpenAI-compatible
// proxy — not a Radius sample. It has first-class Azure OpenAI support. We run the
// upstream published image directly and configure a single model, `chat`, that maps
// to the Azure OpenAI DEPLOYMENT named "chat" (created by the recipe — see
// the recipe pack). The container writes a static LiteLLM config file at startup that
// resolves the Azure connection details from environment variables via LiteLLM's
// documented `os.environ/<VAR>` indirection, so no secret is embedded in the config
// or expanded by the shell:
//   - AZURE_API_BASE is the resource's `endpoint` property (AVM `endpoint`).
//   - AZURE_API_KEY is the model's API key, a recipe SECRET OUTPUT. It is bound
//     WHOLE into the env var from the managed Radius.Security/secrets resource via
//     `secretKeyRef` (`model.properties.secrets.name`, key `apiKey`) — never read
//     from a resource property. LiteLLM sends it as the Azure `api-key` header for
//     key-based auth.
//   - AZURE_API_VERSION selects the Azure OpenAI data-plane API version.
// LITELLM_MASTER_KEY gates the proxy's own API; the verify step authenticates chat
// completions with it. Binding the secret via `secretKeyRef`, referencing
// model.properties.endpoint, and the `connections.model` edge create the
// deploy-ordering edge.
// The real connectivity signal is a chat completion: LiteLLM only calls Azure when a
// completion is requested, so the verify step drives one and asserts a model reply.
resource litellmctr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'litellmctr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      litellm: {
        image: 'ghcr.io/berriai/litellm:v1.91.0'
        // Write a static config (the model name "chat" -> Azure deployment "chat")
        // then start the proxy. The heredoc is quoted so the `os.environ/...`
        // placeholders are written literally and resolved by LiteLLM at runtime.
        command: [
          '/bin/sh'
          '-c'
          '''
set -eu
cat > /tmp/litellm.config.yaml <<'EOF'
model_list:
  - model_name: chat
    litellm_params:
      model: azure/chat
      api_base: os.environ/AZURE_API_BASE
      api_key: os.environ/AZURE_API_KEY
      api_version: os.environ/AZURE_API_VERSION
EOF
exec litellm --config /tmp/litellm.config.yaml --host 0.0.0.0 --port 4000
'''
        ]
        ports: {
          // LiteLLM's OpenAI-compatible HTTP API (chat completions + /health).
          web: {
            containerPort: 4000
          }
        }
        env: {
          AZURE_API_BASE: {
            value: model.properties.endpoint
          }
          // The apiKey is a recipe SECRET OUTPUT: bind it WHOLE from the managed
          // Radius.Security/secrets resource Radius materialized from the recipe's
          // `outputs.secrets` (`<resourceName>-secrets`, key `apiKey`). LiteLLM reads
          // the whole env var via `os.environ/AZURE_API_KEY`, so a single
          // `secretKeyRef` maps cleanly onto one env var — no interpolation needed.
          AZURE_API_KEY: {
            valueFrom: {
              secretKeyRef: {
                secretName: model.properties.secrets.name
                key: 'apiKey'
              }
            }
          }
          AZURE_API_VERSION: {
            value: '2025-04-01-preview'
          }
          // Gates the proxy's API; the verify step uses this as the bearer token.
          LITELLM_MASTER_KEY: {
            value: 'sk-radius-verify'
          }
        }
      }
    }
    connections: {
      model: {
        source: model.id
      }
    }
  }
}
