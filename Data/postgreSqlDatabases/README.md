# Radius.Data/postgreSqlDatabases

## Overview

The **Radius.Data/postgreSqlDatabases** resource type represents a PostgreSQL database. It allows developers to create and easily connect to a PostgreSQL database as part of their Radius applications.

All recipes use **password-based authentication** via a `Radius.Security/secrets` resource. The `secretName` property is required — it references a secret containing the `username` and `password` for the database.

Developer documentation is embedded in the resource type definition YAML file, and it is accessible via the `rad resource-type show Radius.Data/postgreSqlDatabases` command.

## Recipes

| Platform | IaC Language | Recipe Name | Stage |
|---|---|---|---|
| Kubernetes | Bicep | kubernetes-postgresql.bicep | Alpha |
| Kubernetes | Terraform | main.tf | Alpha |
| Azure | Bicep | azure-postgresql.bicep | Alpha |

## Recipe Input Properties

Properties for the **Radius.Data/postgreSqlDatabases** resource type are provided via the [Recipe Context](https://docs.radapp.io/reference/context-schema/) object:

- `context.properties.secretName` (string, required): Name of the K8s secret containing database credentials (`username`, `password`).
- `context.properties.size` (string, optional): The size of the database (`S`, `M`, `L`). Defaults to `S`.
- `context.properties.database` (string, optional): The name of the database. Defaults to `postgres_db`.

## Recipe Output Properties

The recipe sets these properties on the resource via the `result.values` object:

- `host` (string): The hostname used to connect to the database.
- `port` (integer): The port number used to connect to the database.
- `database` (string): The name of the database.
