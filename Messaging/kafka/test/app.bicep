// Kafka app-to-broker CONNECTION test on Azure — kcat variant.
//
// This is an ADDITIONAL sample alongside quarkus-kafka-quickstart (the Quarkus
// producer/processor) and kafka-ui. It exercises the same Event Hubs Kafka
// connection surface, but its purpose is to exercise Radius.Compute/containerImages:
// the client image is BUILT FROM SOURCE (edenhill/kcat) by the platform's
// containerImages recipe rather than pulled from a registry.
//
// kcat is a tiny (~500 KB) OSS command-line Kafka producer/consumer. Its own
// in-repo Dockerfile builds librdkafka + kcat from source via bootstrap.sh, so
// no custom Dockerfile is authored here — BuildKit runs the upstream Dockerfile
// and Radius surfaces the result as `imageReference`.
//
// CAVEAT — the pinned 1.7.0 release Dockerfile builds on alpine:3.10, whose apk
// package mirrors are end-of-life; the build depends on those mirrors still
// serving the librdkafka build dependencies. If the build becomes flaky, bump
// the ref to a newer commit whose Dockerfile uses a supported base image.
//
// CREDENTIAL MODEL — as with the other kafka samples, Azure generates the
// namespace SAS key; the recipe maps it (via `outputs.secrets`) into the managed
// `Radius.Security/secrets` resource Radius materializes for the kafka resource.
// This container binds it into KAFKA_CONNECTIONSTRING from that secret via
// `secretKeyRef` (using `kafkaBroker.properties.secrets.name` + key
// `connectionString`) — never reading it as a plain property. The kcat round-trip
// below authenticates with exactly that value, so a successful produce -> consume
// is the proof the generated secret survived intact end to end. kcat is the CLEAN
// secret-output consumer: it needs the connection string as a WHOLE value, which
// maps directly onto a single `secretKeyRef` key (no JAAS-string interpolation).

extension radius
extension kafka
extension containerImages

@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'kafka-azure-app-kcat-test'
  properties: {
    environment: environment
  }
}

resource kafkaBroker 'Radius.Messaging/kafka@2025-08-01-preview' = {
  name: 'kafka'
  properties: {
    environment: environment
    application: app.id
    // The platform recipe pre-creates one event hub named by this property
    // ({{context.resource.properties.topic}}); Event Hubs has no Kafka-side
    // topic auto-creation, so kcat produces/consumes on exactly this topic.
    topic: 'kcat-verify'
  }
}

// Build kcat from source. BuildKit (the dynamic-rp buildkitd sidecar) runs
// edenhill/kcat's own Dockerfile — which compiles librdkafka + kcat via
// bootstrap.sh — and the containerImages recipe pushes the result to the
// platform's registry, exposing the pushed ref as `imageReference` below.
// Build only linux/amd64: kcat's Dockerfile compiles from source and the CI
// builder is amd64, so a multi-arch (arm64) cross-compile would fail with
// `exec format error` (there is no QEMU/binfmt fallback in this recipe).
resource kcatImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'kcat-image'
  properties: {
    environment: environment
    application: app.id
    // Pin an explicit tag. The terraform recipe's input-validation block
    // interpolates properties.tag into its error_message unconditionally,
    // so a null tag makes terraform fail evaluating the (passing) check.
    // A pinned tag also keeps the pushed image reference stable per ref.
    tag: '1.7.0'
    build: {
      source: 'git::https://github.com/edenhill/kcat.git//?ref=1.7.0'
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

resource kcatctr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'kcatctr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      kcat: {
        image: kcatImage.properties.imageReference
        // The bootstrap host is read directly from `kafkaBroker.properties.host`
        // (a non-secret property). The SAS connection string is a recipe SECRET
        // OUTPUT, so it is bound from the managed secret via `secretKeyRef` rather
        // than read as a property.
        env: {
          KAFKA_HOST: {
            value: '${kafkaBroker.properties.host}'
          }
          KAFKA_CONNECTIONSTRING: {
            // Bind the connection string from the managed Radius.Security/secrets
            // resource Radius materialized from the recipe's `outputs.secrets`
            // (`<resourceName>-secrets`, key `connectionString`). A whole-value
            // secret maps cleanly onto one env var here — no interpolation needed.
            valueFrom: {
              secretKeyRef: {
                secretName: kafkaBroker.properties.secrets.name
                key: 'connectionString'
              }
            }
          }
        }
        // kcat is a run-to-completion CLI, so a small script drives the test:
        //   1. write a librdkafka config file (-F) with the Event Hubs SASL_SSL
        //      settings, taking the bootstrap host and SAS connection string from
        //      the KAFKA_HOST / KAFKA_CONNECTIONSTRING env vars,
        //   2. PRODUCE one message to the `kcat-verify` topic,
        //   3. CONSUME it back from the beginning (-c 1 -e exits after one message)
        //      — the real app -> broker -> app round-trip,
        //   4. hold the container open with `tail -f /dev/null` so the Radius
        //      Deployment stays healthy.
        // The Event Hubs Kafka username is the literal string `$ConnectionString`;
        // it is escaped (\$) so the unquoted heredoc writes it verbatim instead of
        // shell-expanding it. Event Hubs requires SASL_SSL + PLAIN on port 9093.
        command: [
          '/bin/sh'
          '-c'
          '''
set -eu
CONF=/tmp/kcat.conf
cat > "$CONF" <<EOF
bootstrap.servers=$KAFKA_HOST.servicebus.windows.net:9093
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.username=\$ConnectionString
sasl.password=$KAFKA_CONNECTIONSTRING
EOF
MSG="radius-kcat-verify-$(date +%s)"
echo "producing: $MSG"
printf '%s\n' "$MSG" | kcat -F "$CONF" -P -t kcat-verify
echo "consuming:"
kcat -F "$CONF" -C -t kcat-verify -o beginning -c 1 -e
echo "kcat round-trip OK"
exec tail -f /dev/null
'''
        ]
      }
    }
    // Models the app -> broker edge in the Radius graph and orders this after the
    // kafka resource.
    connections: {
      kafka: {
        source: kafkaBroker.id
      }
    }
  }
}
