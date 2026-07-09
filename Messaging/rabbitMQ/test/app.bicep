// Developer-facing connection test for the REAL Radius.Messaging/rabbitMQ
// resource type (authored in this repo at Messaging/rabbitMQ/rabbitMQ.yaml). The
// platform engineer wired its recipe to a standard Azure Verified Module (see
// the recipe pack), so Radius provisions a real Azure Service Bus namespace + queue,
// maps the module `name` output onto `properties.host`, and routes its sensitive
// connection-string output into a managed secret via `outputs.secrets` (surfaced on
// the resource as the readOnly `secrets` reference).
//
// Azure Service Bus is not a RabbitMQ broker and does not speak RabbitMQ's native
// AMQP 0-9-1, but it DOES speak AMQP 1.0. This verification runs warpstreamlabs/bento
// (a small, Apache-2.0 Go stream processor, ~35 MB busybox image) which ships a
// generic `amqp_1` input and output. It exercises a real app -> broker data path: it
// SENDS one message to the provisioned queue (`jobs`) and then RECEIVES it back,
// authenticating with SASL PLAIN over TLS (port 5671) using the namespace's
// RootManageSharedAccessKey. The container runs the published warpstreamlabs/bento
// image pulled from a registry; its static busybox build ships ca-certificates, so
// TLS to *.servicebus.windows.net verifies.

extension radius
extension rabbitMQ
extension containerImages
@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'rabbitmq-azure-app-test'
  properties: {
    environment: environment
  }
}

// Radius.Compute/containerImages builds a container image from source inside the
// cluster (dynamic-rp's rootless BuildKit sidecar) and pushes it to the registry
// configured on the recipe. Here we build the upstream mccutchen/go-httpbin image
// from its git repo to exercise the direct-module containerImages recipe end to end
// (BuildKit clone -> build -> push). This is a DECOUPLED build check: the bentoctr
// container below keeps running the published `ghcr.io/warpstreamlabs/bento:1.18.1`
// image, so the app's AMQP data-path verification does not depend on the cluster
// being able to pull the freshly built image. Reaching a successful deploy proves
// the build-and-push path works; `imageReference` is populated with the pushed ref.
//
// go-httpbin is a tiny, permissively licensed Go HTTP server with a standard
// root Dockerfile and (importantly) a stdlib-only dependency tree, so the
// in-cluster `go mod download`/build stays small and fast — unlike heavyweight Go
// apps whose large module trees can exhaust the rootless builder's ephemeral disk.
resource httpbinImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'httpbin-image'
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
      // Immutable ref so the recipe's content-addressable tag is stable. The build
      // context is the repo root, which holds go-httpbin's Dockerfile.
      source: 'git::https://github.com/mccutchen/go-httpbin.git//?ref=v2.23.1'
      // Single-arch keeps the in-cluster build fast and avoids cross-compilation
      // failures; the runner and cluster are linux/amd64.
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

resource queue 'Radius.Messaging/rabbitMQ@2025-08-01-preview' = {
  name: 'rabbitmq'
  properties: {
    environment: environment
    application: app.id
    queue: 'jobs'
  }
}

resource bentoctr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'bentoctr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      bento: {
        image: 'ghcr.io/warpstreamlabs/bento:1.18.1'
        // The host is read directly off the `queue` resource (a non-secret
        // property). The connection string is a recipe SECRET OUTPUT, so it is
        // bound from the managed secret via `secretKeyRef` rather than read as a
        // plain property.
        env: {
          RABBITMQ_HOST: {
            value: '${queue.properties.host}'
          }
          RABBITMQ_CONNECTIONSTRING: {
            // Bind the connection string from the managed Radius.Security/secrets
            // resource Radius materialized from the recipe's `outputs.secrets`
            // (`<resourceName>-secrets`, key `connectionString`). bento consumes the
            // connection string as a WHOLE value (its startup script parses the SAS
            // key out at runtime), so it maps cleanly onto a single `secretKeyRef` —
            // no `$(VAR)` interpolation needed.
            valueFrom: {
              secretKeyRef: {
                secretName: queue.properties.secrets.name
                key: 'connectionString'
              }
            }
          }
        }
        // bento is a run-to-completion stream processor, so we drive it with a small
        // script:
        //   1. read the connection info from RABBITMQ_HOST (the
        //      Service Bus namespace name) and RABBITMQ_CONNECTIONSTRING (the full
        //      RootManageSharedAccessKey connection string). We parse the SAS key value
        //      out of the connection string with busybox sed.
        //   2. write a send config (generate 1 message -> amqp_1 output to queue `jobs`)
        //      and a receive config (amqp_1 input from `jobs`, wrapped in read_until so
        //      it stops after the first message -> stdout).
        //   3. run send, then receive — the real app -> broker round-trip that proves
        //      connectivity end to end. SASL PLAIN uses user=RootManageSharedAccessKey
        //      and the parsed key as the password; the `amqps://` scheme selects TLS on
        //      5671 and the baked-in ca-certificates verify the Azure certificate. Each
        //      run is bounded by `timeout` so a broker/connection fault fails the
        //      container clearly instead of hanging on bento's connection retries.
        //   4. hold the container open with `tail -f /dev/null` so the Radius
        //      Deployment stays healthy after the one-shot verification.
        command: [
          '/bin/sh'
          '-c'
          '''
set -eu
NS="$RABBITMQ_HOST"
KEY=$(printf '%s' "$RABBITMQ_CONNECTIONSTRING" | sed -n 's/.*SharedAccessKey=//p')
cat > /tmp/send.yaml <<EOF
input:
  generate:
    count: 1
    interval: ""
    mapping: 'root = "radius-bento-verify"'
output:
  amqp_1:
    url: amqps://$NS.servicebus.windows.net
    target_address: jobs
    sasl:
      mechanism: plain
      user: RootManageSharedAccessKey
      password: "$KEY"
EOF
cat > /tmp/recv.yaml <<EOF
input:
  read_until:
    check: 'true'
    input:
      amqp_1:
        url: amqps://$NS.servicebus.windows.net
        source_address: jobs
        azure_renew_lock: true
        sasl:
          mechanism: plain
          user: RootManageSharedAccessKey
          password: "$KEY"
output:
  stdout: {}
EOF
echo "[bento] sending 1 message to Service Bus queue jobs"
timeout 120 /bento -c /tmp/send.yaml
echo "[bento] receiving 1 message from Service Bus queue jobs"
timeout 120 /bento -c /tmp/recv.yaml
echo "[bento] AMQP 1.0 send/receive round-trip OK"
exec tail -f /dev/null
'''
        ]
      }
    }
    // Models the app -> broker edge in the Radius graph, ordering this after the
    // rabbitmq resource.
    connections: {
      rabbitmq: {
        source: queue.id
      }
    }
  }
}
