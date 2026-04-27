extension radius
extension containers
extension kafkaBrokers

@description('The Radius environment ID')
param environment string

resource myapp 'Radius.Core/applications@2025-08-01-preview' = {
  name: 'myapp'
  properties: {
    environment: environment
  }
}

resource mycontainer 'Radius.Compute/containers@2025-08-01-preview' = {
  name: 'mycontainer'
  properties: {
    environment: environment
    application: myapp.id
    containers: {
      kafkatest: {
        image: 'ghcr.io/radius-project/samples/demo:latest'
        ports: {
          web: {
            containerPort: 3000
          }
        }
      }
    }
    connections: {
      kafka: {
        source: kafka.id
      }
    }
  }
}

resource kafka 'Radius.Messaging/kafkaBrokers@2025-08-01-preview' = {
  name: 'kafka'
  properties: {
    environment: environment
    application: myapp.id
    size: 'S'
    topicName: 'test-topic'
  }
}
