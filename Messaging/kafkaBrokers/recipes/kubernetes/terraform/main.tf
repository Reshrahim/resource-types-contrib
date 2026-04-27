terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.37.1"
    }
  }
}

variable "context" {
  description = "This variable contains Radius Recipe context."
  type = any
}

variable "memory" {
  description = "Memory limits for the Kafka container"
  type = map(object({
    memoryRequest = string
  }))
  default = {
    S = {
      memoryRequest = "512Mi"
    },
    M = {
      memoryRequest = "1Gi"
    },
    L = {
      memoryRequest = "2Gi"
    }
  }
}

locals {
  resource_name      = var.context.resource.name
  application_name   = var.context.application != null ? var.context.application.name : ""
  environment_name   = var.context.environment != null ? var.context.environment.name : ""
  resource_group     = element(split("/", var.context.resource.id), 5)
  namespace          = var.context.runtime.kubernetes.namespace
  port               = 9092
  tag                = "3.9"
  topic_name         = try(var.context.resource.properties.topicName, "default-topic")
  size_value         = try(var.context.resource.properties.size, "S")
  cluster_id         = substr(sha256(var.context.resource.id), 0, 22)

  labels = {
    "radapp.io/resource"       = local.resource_name
    "radapp.io/application"    = local.application_name
    "radapp.io/environment"    = local.environment_name
    "radapp.io/resource-type"  = replace(var.context.resource.type, "/", "-")
    "radapp.io/resource-group" = local.resource_group
  }
}

resource "kubernetes_deployment" "kafka" {
  metadata {
    name      = local.resource_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    selector {
      match_labels = {
        "radapp.io/resource" = local.resource_name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        container {
          name  = "kafka"
          image = "bitnami/kafka:${local.tag}"

          port {
            container_port = local.port
          }

          resources {
            requests = {
              memory = var.memory[local.size_value].memoryRequest
            }
          }

          env {
            name  = "KAFKA_CFG_NODE_ID"
            value = "0"
          }

          env {
            name  = "KAFKA_CFG_PROCESS_ROLES"
            value = "broker,controller"
          }

          env {
            name  = "KAFKA_CFG_CONTROLLER_QUORUM_VOTERS"
            value = "0@localhost:9093"
          }

          env {
            name  = "KAFKA_CFG_CONTROLLER_LISTENER_NAMES"
            value = "CONTROLLER"
          }

          env {
            name  = "KAFKA_CFG_LISTENERS"
            value = "PLAINTEXT://:${local.port},CONTROLLER://:9093"
          }

          env {
            name  = "KAFKA_CFG_ADVERTISED_LISTENERS"
            value = "PLAINTEXT://${local.resource_name}.${local.namespace}.svc.cluster.local:${local.port}"
          }

          env {
            name  = "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP"
            value = "PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT"
          }

          env {
            name  = "KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE"
            value = "true"
          }

          env {
            name  = "KAFKA_KRAFT_CLUSTER_ID"
            value = local.cluster_id
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "kafka" {
  metadata {
    name      = local.resource_name
    namespace = local.namespace
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      "radapp.io/resource" = local.resource_name
    }

    port {
      port = local.port
    }
  }
}

output "result" {
  value = {
    resources = [
      "/planes/kubernetes/local/namespaces/${local.namespace}/providers/core/Service/${local.resource_name}",
      "/planes/kubernetes/local/namespaces/${local.namespace}/providers/apps/Deployment/${local.resource_name}"
    ]
    values = {
      host = "${kubernetes_service.kafka.metadata[0].name}.${kubernetes_service.kafka.metadata[0].namespace}.svc.cluster.local"
      port = local.port
    }
  }
}
