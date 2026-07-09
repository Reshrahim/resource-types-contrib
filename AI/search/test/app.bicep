// Developer-facing connection test for the REAL Radius.AI/search resource type
// (authored in this repo at AI/search/search.yaml). The platform engineer wired
// its recipe to a standard Azure Verified Module (see the recipe pack recipepack/azure/aks-recipepack.bicep), so this
// definition carries no module details — Radius provisions a real Azure AI Search
// service, maps the module's `endpoint` output onto `properties.endpoint`, and
// routes its secure `primaryKey` output into the managed secret via `outputs.secrets`
// (surfaced on the resource as the readOnly `secrets` reference). This container
// binds the key from that managed secret via `secretKeyRef` — never reading it as a
// plain property.
//
// This verification runs hurl (Orange-OpenSource/hurl), a small, Apache-2.0 command
// line HTTP tool, to exercise a real app -> search data path against Azure AI Search's
// REST API. Unlike an on-demand RAG client, hurl drives a deterministic round-trip:
// it checks service stats (auth), CREATES an index, UPLOADS a document, then SEARCHES
// until the document is returned. The container runs the published upstream image
// `ghcr.io/orange-opensource/hurl:8.0.1` directly (it ships hurl on PATH and bundled
// ca-certificates for TLS calls to *.search.windows.net).

extension radius
extension search
extension containerImages
@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'search-azure-app-test'
  properties: {
    environment: environment
  }
}

// Radius.Compute/containerImages builds a container image from source inside the
// cluster (dynamic-rp's rootless BuildKit sidecar) and pushes it to the registry
// configured on the recipe. Here we build the upstream traefik/whoami image (a
// tiny Go HTTP server with a root Dockerfile that builds fast) from its git repo
// to exercise the direct-module containerImages recipe end to end (BuildKit clone
// -> build -> push). This is a DECOUPLED build check: the hurlctr container below
// keeps running the published `ghcr.io/orange-opensource/hurl:8.0.1` image, so
// the app's data-path verification does not depend on the cluster being able to
// pull the freshly built image. hurl itself is Rust and compiles slowly, so a
// small OSS project is built instead — for a decoupled check the built image only
// needs to build+push. Reaching a successful deploy proves the build-and-push
// path works; `imageReference` is populated with the pushed ref.
resource whoamiImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'whoami-image'
  properties: {
    environment: environment
    application: app.id
    // Set an explicit tag. The recipe's tag-validation precondition interpolates
    // ${local.user_tag} into its error_message, which Terraform evaluates eagerly;
    // leaving tag unset makes that null and fails with "Cannot include a null value
    // in a string template" before the build even starts. A concrete tag avoids
    // that path (and pins the pushed image ref).
    tag: 'v1.10.3'
    build: {
      // Immutable ref so the recipe's content-addressable tag is stable.
      source: 'git::https://github.com/traefik/whoami.git//?ref=v1.10.3'
      // Single-arch keeps the in-cluster build fast and avoids cross-compilation
      // failures; the runner and cluster are linux/amd64.
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

resource searchService 'Radius.AI/search@2025-08-01-preview' = {
  name: 'search'
  properties: {
    environment: environment
    application: app.id
  }
}

resource hurlctr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'hurlctr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      hurl: {
        image: 'ghcr.io/orange-opensource/hurl:8.0.1'
        // The non-secret `endpoint` is read directly off `searchService.properties.endpoint`.
        // The admin API key is a recipe SECRET OUTPUT, so it is bound from the managed
        // Radius.Security/secrets resource via `secretKeyRef` rather than read as a property.
        env: {
          SEARCH_ENDPOINT: {
            value: '${searchService.properties.endpoint}'
          }
          SEARCH_APIKEY: {
            // Bind the admin API key from the managed Radius.Security/secrets resource
            // Radius materialized from the recipe's `outputs.secrets` (`<resourceName>-secrets`,
            // key `apiKey`). This is the CLEAN whole-value case: the key maps directly onto a
            // single `secretKeyRef` env var — no interpolation needed. The hurl script below
            // reads it at runtime via `$SEARCH_APIKEY` and passes it as the `apikey` variable,
            // so the plaintext never lands in Radius state.
            valueFrom: {
              secretKeyRef: {
                secretName: searchService.properties.secrets.name
                key: 'apiKey'
              }
            }
          }
        }
        // hurl is a run-to-completion CLI, so we drive it with a small script:
        //   1. write a .hurl file describing the REST round-trip against the
        //      SEARCH_ENDPOINT and SEARCH_APIKEY: check service stats
        //      (auth), create-or-update the `radius-verify` index, upload a document,
        //      then search — retrying until Azure finishes async indexing,
        //   2. run `hurl --test` (fails non-zero if any assert fails) — the real
        //      app -> search write+read that proves connectivity end to end,
        //   3. hold the container open with `tail -f /dev/null` so the Radius
        //      Deployment stays healthy. The upload uses mergeOrUpload and the index
        //      create tolerates 2xx, so re-runs are idempotent.
        command: [
          '/bin/sh'
          '-c'
          '''
set -eu
cat > /tmp/verify.hurl <<'HURL'
# 1. Service stats — proves the endpoint + admin key authenticate.
GET {{endpoint}}/servicestats?api-version=2024-07-01
api-key: {{apikey}}
HTTP 200

# 2. Create (or update) the verification index. First run returns 201, re-runs 204.
PUT {{endpoint}}/indexes/radius-verify?api-version=2024-07-01
api-key: {{apikey}}
Content-Type: application/json
{
  "name": "radius-verify",
  "fields": [
    { "name": "id", "type": "Edm.String", "key": true, "searchable": false },
    { "name": "content", "type": "Edm.String", "searchable": true }
  ]
}
HTTP *
[Asserts]
status >= 200
status < 300

# 3. Upload a document (mergeOrUpload keeps re-runs idempotent).
POST {{endpoint}}/indexes/radius-verify/docs/index?api-version=2024-07-01
api-key: {{apikey}}
Content-Type: application/json
{
  "value": [
    { "@search.action": "mergeOrUpload", "id": "1", "content": "radius search verify" }
  ]
}
HTTP 200

# 4. Search for the document. Indexing is async, so retry until it is returned.
POST {{endpoint}}/indexes/radius-verify/docs/search?api-version=2024-07-01
api-key: {{apikey}}
Content-Type: application/json
[Options]
retry: 20
retry-interval: 3s
{
  "search": "radius",
  "select": "id,content"
}
HTTP 200
[Asserts]
jsonpath "$.value[0].id" == "1"
jsonpath "$.value[0].content" contains "radius"
HURL
echo "[hurl] running Azure AI Search REST round-trip"
hurl --test --variable endpoint="$SEARCH_ENDPOINT" --variable apikey="$SEARCH_APIKEY" /tmp/verify.hurl
echo "[hurl] Azure AI Search round-trip OK"
exec tail -f /dev/null
'''
        ]
      }
    }
    // Models the app -> search edge in the Radius graph, ordering this after the
    // search resource.
    connections: {
      search: {
        source: searchService.id
      }
    }
  }
}
