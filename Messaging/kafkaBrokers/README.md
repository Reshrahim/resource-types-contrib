# Radius.Messaging/kafkaBrokers

## Overview

The **Radius.Messaging/kafkaBrokers** resource type represents an Apache Kafka broker. It allows developers to create and easily connect to a Kafka broker as part of their Radius applications.

Developer documentation is embedded in the resource type definition YAML file, and it is accessible via the `rad resource-type show Radius.Messaging/kafkaBrokers` command.

## Recipes

A list of available Recipes for this resource type, including links to the Bicep and Terraform templates:

|Platform| IaC Language| Recipe Name | Stage |
|---|---|---|---|
| Kubernetes | Bicep | kubernetes-kafka.bicep | Alpha |
| Kubernetes | Terraform | main.tf | Alpha |

## Recipe Input Properties

Properties for the **Radius.Messaging/kafkaBrokers** resource type are provided via the [Recipe Context](https://docs.radapp.io/reference/context-schema/) object. These properties include:

- `context.properties.size` (string, optional): The size of the Kafka broker. Defaults to `S` if not provided.
- `context.properties.topicName` (string, optional): The name of the default Kafka topic. Defaults to `default-topic` if not provided.

## Recipe Output Properties

The **Radius.Messaging/kafkaBrokers** resource type expects the following output properties to be set in the Results object in the Recipe:

- `context.properties.host` (string): The hostname used to connect to the Kafka broker.
- `context.properties.port` (integer): The port number used to connect to the Kafka broker.
