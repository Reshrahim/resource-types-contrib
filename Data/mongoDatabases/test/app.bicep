extension radius
extension mongoDatabases
extension containerImages

@description('The ID of your Radius Environment. Set automatically by the rad CLI.')
param environment string

@description('The Radius resource name. The workflow passes the same globally-unique value used for the Cosmos DB account so verification can use one name for both Radius and Azure.')
param accountName string

var databaseName = 'mongo_db'

resource app 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'mongodb-azure-app-test'
  properties: {
    environment: environment
  }
}

resource mongo 'Radius.Data/mongoDatabases@2025-08-01-preview' = {
  name: accountName
  properties: {
    environment: environment
    application: app.id
    database: databaseName
  }
}

// Radius.Compute/containerImages builds a container image from source inside the
// cluster (dynamic-rp's rootless BuildKit sidecar) and pushes it to the registry
// configured on the recipe. Here we build the upstream mongo-express image from
// its git repo to exercise the direct-module containerImages recipe end to end
// (BuildKit clone -> build -> push). This is a DECOUPLED build check: the mectr
// container below keeps running the published `mongo-express:1.0.2-18-alpine3.19`
// image, so the app's data-path verification does not depend on the cluster being
// able to pull the freshly built image. Reaching a successful deploy proves the
// build-and-push path works; `imageReference` is populated with the pushed ref.
resource mongoExpressImage 'Radius.Compute/containerImages@2025-08-01-preview' = {
  name: 'mongo-express-image'
  properties: {
    environment: environment
    application: app.id
    // Set an explicit tag. The recipe's tag-validation precondition interpolates
    // ${local.user_tag} into its error_message, which Terraform evaluates eagerly;
    // leaving tag unset makes that null and fails with "Cannot include a null value
    // in a string template" before the build even starts. A concrete tag avoids
    // that path (and pins the pushed image ref).
    tag: 'v1.0.2'
    build: {
      // Immutable ref so the recipe's content-addressable tag is stable.
      source: 'git::https://github.com/mongo-express/mongo-express.git//?ref=v1.0.2'
      // Single-arch keeps the in-cluster build fast and avoids cross-compilation
      // failures; the runner and cluster are linux/amd64.
      platforms: [
        'linux/amd64'
      ]
    }
  }
}

// mongo-express (https://github.com/mongo-express/mongo-express) is a standard,
// third-party MongoDB admin web app — not a Radius sample. On startup it opens a
// real authenticated connection to MongoDB using the connection string in
// ME_CONFIG_MONGODB_URL and serves a web UI that enumerates the server's databases.
// We point it at the REAL Azure Cosmos DB Mongo API account by binding it the
// connection string the recipe wrote (via `outputs.secrets`, mapped from the AVM
// `primaryReadWriteConnectionString` output) into the managed Radius.Security/secrets
// resource — read here via `secretKeyRef` (`mongo.properties.secrets.name`, key
// `connectionString`), never as a plain resource property. Reaching the UI and seeing
// our database (`mongo_db`) listed proves the end-to-end app -> Cosmos DB Mongo data
// path — a real client connecting and authenticating against the provisioned
// account, not just that the account exists.
//
// Env variables are exactly those documented in the mongo-express repository:
//   - ME_CONFIG_MONGODB_URL          the MongoDB connection string
//   - ME_CONFIG_MONGODB_SSL          match the connection string's ssl=true so the
//                                    driver does not reject a tls/ssl mismatch
//   - ME_CONFIG_BASICAUTH            disable the web login so the verify step can
//                                    reach the UI without credentials
//   - ME_CONFIG_MONGODB_ENABLE_ADMIN allow it to enumerate all databases (so the
//                                    homepage lists `mongo_db`)
resource mectr 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'mectr'
  properties: {
    environment: environment
    application: app.id
    containers: {
      mongoexpress: {
        image: 'mongo-express:1.0.2-18-alpine3.19'
        ports: {
          web: {
            containerPort: 8081
          }
        }
        env: {
          // The Cosmos DB Mongo connection string is a recipe SECRET OUTPUT. It is
          // bound WHOLE into ME_CONFIG_MONGODB_URL from the managed
          // Radius.Security/secrets resource Radius materialized from the recipe's
          // `outputs.secrets` (`<resourceName>-secrets`, key `connectionString`) via
          // `secretKeyRef` — never read as a plain property. mongo-express needs the
          // entire connection string, so this whole-value secret maps cleanly onto a
          // single env var (no `$(VAR)` interpolation needed).
          ME_CONFIG_MONGODB_URL: {
            valueFrom: {
              secretKeyRef: {
                secretName: mongo.properties.secrets.name
                key: 'connectionString'
              }
            }
          }
          // Cosmos DB for MongoDB requires TLS, and its connection string carries
          // `ssl=true`. mongo-express otherwise passes an explicit `tls:false` option
          // to the driver, which rejects the mismatch with
          // "All values of tls/ssl must be the same." Setting this to true makes the
          // driver option agree with the connection string.
          ME_CONFIG_MONGODB_SSL: {
            value: 'true'
          }
          // Disable basic auth so the verification step can curl the UI without
          // credentials. In mongo-express 1.0.2 the gate is ME_CONFIG_BASICAUTH
          // (useBasicAuth = getBoolean(ME_CONFIG_BASICAUTH)); the Docker image
          // defaults it on with admin:pass, which returns 401 to an unauthenticated
          // curl. Setting it false serves the homepage anonymously.
          ME_CONFIG_BASICAUTH: {
            value: 'false'
          }
          // Enable admin access so the homepage enumerates all databases (and lists
          // our `mongo_db`), exercising a real read against the account.
          ME_CONFIG_MONGODB_ENABLE_ADMIN: {
            value: 'true'
          }
        }
      }
    }
    // Model the app -> database edge in the Radius graph, ordering this after the
    // mongo resource.
    connections: {
      mongo: {
        source: mongo.id
      }
    }
  }
}
