// Developer-facing connection test for the REAL Radius.Storage/objectStorage
// resource type (authored in this repo at Storage/objectStorage/objectStorage.yaml). The
// platform engineer wired its recipe to a standard Azure Verified Module (see
// the recipe pack), so Radius provisions a real Azure Storage account, creates the
// requested blob container, maps the module's non-secret outputs onto
// `properties.endpoint` and `properties.accountName`, and routes the account key
// (a recipe SECRET OUTPUT) into the managed Radius.Security/secrets resource that
// `properties.secrets` references.
//
// This verification runs SFTPGo (drakkan/sftpgo), a small, self-hostable storage
// protocol gateway written in Go. Unlike the stock demo image, SFTPGo natively
// speaks Azure Blob Storage (internal/vfs/azblobfs.go), so it exercises a real
// app -> Blob data path: an SFTP/FTP/WebDAV client writing through SFTPGo lands
// objects directly in the provisioned Azure Storage container. The container runs
// the published upstream image `ghcr.io/drakkan/sftpgo:v2.7.4` directly (it ships
// the sftpgo binary with the +azblob provider built in).

extension radius
extension objectStorage
extension containerImages
@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'storage-azure-app-test'
  properties: {
    environment: environment
  }
}

// Radius.Compute/containerImages builds a container image from source inside the
// cluster (dynamic-rp's rootless BuildKit sidecar) and pushes it to the registry
// configured on the recipe. Here we build the upstream drakkan/sftpgo image from
// its git repo to exercise the direct-module containerImages recipe end to end
// (BuildKit clone -> build -> push). This is a DECOUPLED build check: the sftpgoctr
// container below keeps running the published `ghcr.io/drakkan/sftpgo:v2.7.4`
// image, so the app's data-path verification does not depend on the cluster being
// able to pull the freshly built image. Reaching a successful deploy proves the
// build-and-push path works; `imageReference` is populated with the pushed ref.
resource sftpgoImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'sftpgo-image'
  properties: {
    environment: environment
    application: app.id
    // Set an explicit tag. The recipe's tag-validation precondition interpolates
    // ${local.user_tag} into its error_message, which Terraform evaluates eagerly;
    // leaving tag unset makes that null and fails with "Cannot include a null value
    // in a string template" before the build even starts. A concrete tag avoids
    // that path (and pins the pushed image ref).
    tag: 'v2.7.4'
    build: {
      // Immutable ref so the recipe's content-addressable tag is stable. sftpgo is
      // a Go project with a root Dockerfile that builds cleanly in BuildKit.
      source: 'git::https://github.com/drakkan/sftpgo.git//?ref=v2.7.4'
      // Single-arch keeps the in-cluster build fast and avoids cross-compilation
      // failures; the runner and cluster are linux/amd64.
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

resource store 'Radius.Storage/objectStorage@2025-08-01-preview' = {
  name: 'store'
  properties: {
    environment: environment
    application: app.id
    // Object container (blob container / S3 bucket) created inside the generated
    // storage account. Matches the provisioning test's explicit `data` container.
    containerName: 'data'
  }
}

resource sftpgoctr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'sftpgoctr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      sftpgo: {
        image: 'ghcr.io/drakkan/sftpgo:v2.7.4'
        // SFTPGo keeps users in a data provider. We use the in-memory provider
        // (nothing to initialize, no persistence needed for a verification run) and
        // load a single user whose filesystem is the provisioned Azure Blob
        // container. The user + Azure credentials are written to a JSON dump at
        // startup from the environment variables below, then `sftpgo serve` loads
        // it via SFTPGO_LOADDATA_FROM (the documented initial-data load; the memory
        // provider's `name` field is NOT a load mechanism). FilesystemProvider `3`
        // is Azure Blob (github.com/sftpgo/sdk: AzureBlobFilesystemProvider);
        // `account_key` is a plaintext KMS secret that SFTPGo encrypts on import.
        command: [
          '/bin/sh'
          '-c'
          '''
set -eu
cat > /var/lib/sftpgo/init.json <<EOF
{"admins":[{"username":"admin","password":"radius-verify-Admin1!","status":1,"permissions":["*"]}],"users":[{"username":"radius","password":"radius-verify-Pass1!","status":1,"permissions":{"/":["*"]},"home_dir":"/srv/sftpgo/data/radius","filesystem":{"provider":3,"azblobconfig":{"container":"$AZ_CONTAINER","account_name":"$AZ_ACCOUNT","account_key":{"status":"Plain","payload":"$AZ_KEY"}}}}]}
EOF
exec sftpgo serve
'''
        ]
        ports: {
          // SFTP data path: an SFTP client writing here streams objects into the
          // Azure Blob container.
          sftp: {
            containerPort: 2022
          }
          // HTTP admin/REST API; exposes an unauthenticated /healthz endpoint.
          http: {
            containerPort: 8080
          }
        }
        env: {
          // In-memory data provider; users are preloaded at startup from the JSON
          // dump written by the command above via SFTPGO_LOADDATA_FROM.
          SFTPGO_DATA_PROVIDER__DRIVER: {
            value: 'memory'
          }
          SFTPGO_LOADDATA_FROM: {
            value: '/var/lib/sftpgo/init.json'
          }
          // Force SFTPGo to log to stdout (empty log_file_path) instead of its
          // default rotating file. Without this, `kubectl logs` returns nothing
          // and any loaddata/restore error (e.g. a rejected user record, which
          // silently leaves the `radius` user absent and makes SFTP logins fail
          // with "Permission denied") is invisible to CI.
          SFTPGO_LOG_FILE_PATH: {
            value: ''
          }
          // Azure Blob backend coordinates. The non-secret account name and
          // container come straight off the objectStorage resource's properties;
          // the account key is a recipe SECRET OUTPUT, bound from the managed
          // Radius.Security/secrets resource via `secretKeyRef` (see AZ_KEY).
          // Referencing these also creates the deploy-ordering edge, so the account
          // + container exist before SFTPGo starts.
          AZ_ACCOUNT: {
            value: store.properties.accountName
          }
          AZ_KEY: {
            // The account key never lands on the objectStorage resource — it is
            // written into the managed secret (`<resourceName>-secrets`, here
            // `store-secrets`) via the recipe's `outputs.secrets`. Bind it from that
            // secret by reference with `secretKeyRef` (key `accountKey`) instead of
            // reading a plain property. The container command above expands
            // `$AZ_KEY` from this env var at runtime, so the plaintext is assembled
            // in the kubelet and never passes through Radius state.
            valueFrom: {
              secretKeyRef: {
                secretName: store.properties.secrets.name
                key: 'accountKey'
              }
            }
          }
          AZ_CONTAINER: {
            value: store.properties.containerName
          }
        }
      }
    }
    // Models the app -> storage edge in the Radius graph (and injects
    // CONNECTION_STORE_* variables, which SFTPGo ignores in favor of its own
    // SFTPGO_* / dump configuration).
    connections: {
      store: {
        source: store.id
      }
    }
  }
}
