// Developer-facing definition that deploys the REAL Radius.Data/redisCaches
// resource type (authored in this repo at Data/redisCaches/redisCaches.yaml). The
// platform engineer wired its recipe to a standard Azure Verified Module (see
// the recipe pack), so this definition carries no module details — Radius
// provisions a real Azure Managed Redis cache and maps the module's `hostName`
// and `port` outputs onto `properties.host` and `properties.port`, while its
// sensitive `primaryConnectionString` output is routed via `outputs.secrets` into
// a managed Radius.Security/secrets resource (`redis-secrets`), surfaced on the
// resource as the readOnly `secrets` reference.
//
// Azure Managed Redis generates its own access keys; the recipe enables access-key
// auth and the ready-to-use `rediss://:<key>@host:10000` TLS URL becomes the managed
// secret's `connectionString` key. The connection injects CONNECTION_REDIS_HOST /
// CONNECTION_REDIS_PORT (the NON-SECRET properties) into the connected container; the
// connection string is a SECRET OUTPUT, so the container binds it into
// CONNECTION_REDIS_URL from the managed secret via `secretKeyRef` — never reading it
// as a plain property. The demo app uses that URL (which carries the credential) to
// prove the end-to-end app -> Redis data path.

extension radius
extension redisCaches
extension containerImages
@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'redis-azure-app-test'
  properties: {
    environment: environment
  }
}

resource redis 'Radius.Data/redisCaches@2025-08-01-preview' = {
  name: 'redis'
  properties: {
    environment: environment
    application: app.id
    // Smallest Azure Managed Redis SKU (Balanced_B0); the recipe maps this `size`.
    size: 'S'
  }
}

// Radius.Compute/containerImages builds a container image from source inside the
// cluster (dynamic-rp's rootless BuildKit sidecar) and pushes it to the registry
// configured on the recipe. Here we build the SAME upstream the demo container
// runs — the radius-project/samples demo app (samples/demo) — from its git repo
// to exercise the direct-module containerImages recipe end to end (BuildKit
// clone -> build -> push). This is a DECOUPLED build check: the democtr container
// below keeps running the PUBLISHED `ghcr.io/radius-project/samples/demo:latest`
// image, so the app's data-path verification does not depend on the cluster being
// able to pull the freshly built image. Reaching a successful deploy proves the
// build-and-push path works; `imageReference` is populated with the pushed ref.
resource demoImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'redis-demo-image'
  properties: {
    environment: environment
    application: app.id
    // Set an explicit tag. The recipe's tag-validation precondition interpolates
    // ${local.user_tag} into its error_message, which Terraform evaluates eagerly;
    // leaving tag unset makes that null and fails with "Cannot include a null value
    // in a string template" before the build even starts. A concrete tag avoids
    // that path (and pins the pushed image ref).
    tag: 'demo-e2e'
    build: {
      // samples has no release tags, so pin to an immutable commit SHA. The demo
      // app lives in the samples/demo subdirectory (selected via go-getter
      // `//samples/demo`); its Dockerfile is a standard node multi-stage build.
      source: 'git::https://github.com/radius-project/samples.git//samples/demo?ref=190d9c4c84278980d9fae402330bd5ead76b31a5'
      // Single-arch keeps the in-cluster build fast and avoids cross-compilation
      // failures; the runner and cluster are linux/amd64.
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

// The demo container (ghcr.io/radius-project/samples/demo) auto-selects its Redis
// backend when a Redis connection is present and prefers CONNECTION_REDIS_URL (a
// full `rediss://:<key>@host:port` URL) over discrete HOST/PORT vars. The
// `connections` entry below injects the NON-SECRET HOST and PORT from the
// redisCaches resource's properties. The connection URL is a recipe SECRET OUTPUT,
// so it is NOT injected through the connection; instead the container binds it into
// CONNECTION_REDIS_URL from the managed Radius.Security/secrets resource
// (`redis-secrets`, key `connectionString`) via `secretKeyRef`. The URL carries the
// access key, so the app authenticates over TLS to the real Azure Managed Redis. The
// app self-creates its state and serves GET/POST /api/todos against the cache.
resource democtr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'democtr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      demo: {
        image: 'ghcr.io/radius-project/samples/demo:latest'
        ports: {
          web: {
            containerPort: 3000
          }
        }
        env: {
          // The connection string is a WHOLE value (the full `rediss://:<key>@host:port`
          // URL), so it maps cleanly onto a single env var — no interpolation needed.
          // Bind it from the managed secret Radius materialized from the recipe's
          // `outputs.secrets` (`redis.properties.secrets.name` = `redis-secrets`, key
          // `connectionString`). Naming the env var CONNECTION_REDIS_URL matches what the
          // demo app reads (the connection injects HOST/PORT under the same prefix); the
          // URL is no longer injected there because it is a secret output.
          CONNECTION_REDIS_URL: {
            valueFrom: {
              secretKeyRef: {
                secretName: redis.properties.secrets.name
                key: 'connectionString'
              }
            }
          }
        }
      }
    }
    connections: {
      redis: {
        source: redis.id
      }
    }
  }
}
