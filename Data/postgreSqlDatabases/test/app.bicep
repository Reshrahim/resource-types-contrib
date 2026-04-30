extension radius
extension containers
extension postgreSqlDatabases
extension secrets

@description('The Radius environment ID')
param environment string

@secure()
@description('The password for the PostgreSQL database admin user. Generate with: -p password=$(openssl rand -hex 16)')
param password string

resource myapp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'myapp'
  properties: {
    environment: environment
  }
}

resource dbCredentials 'Radius.Security/secrets@2025-08-01-preview' = {
  name: 'db-creds'
  properties: {
    environment: environment
    application: myapp.id
    data: {
      USERNAME: {
        value: 'pgadmin'
      }
      PASSWORD: {
        value: password
      }
    }
  }
}

resource mycontainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'mycontainer'
  properties: {
    environment: environment
    application: myapp.id
    containers: {
      demo: {
        image: 'ghcr.io/radius-project/samples/demo:latest'
        ports: {
          web: {
            containerPort: 3000
          }
        }
      }
    }
    connections: {
      postgresql: {
        source: postgresql.id
      }
    }
  }
}

resource postgresql 'Radius.Data/postgreSqlDatabases@2025-08-01-preview' = {
  name: 'postgresql'
  properties: {
    environment: environment
    application: myapp.id
    size: 'S'
    secretName: dbCredentials.name
  }
}
