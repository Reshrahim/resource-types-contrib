## Test Your Resource Type and Recipes

1. Create the Resource Type in Radius:

    ```bash
    rad resource-type create <resourceTypeName> -f types.yaml
    ```

1. Generate Bicep Extension to enable tooling support:

    ```bash
    rad bicep publish-extension -f types.yaml --target <extensionName>.tgz
    ```

1. Publish the Recipe to a Registry

    For Bicep, Recipes leverage [Bicep registries](https://learn.microsoft.com/azure/azure-resource-manager/bicep/private-module-registry) for template storage. 

    - Make sure you have the right permissions to push to the registry. Owner or Contributor alone won't allow you to push.

    - Make sure to log in to your registry before publishing the recipe. e.g.

        ```bash
        az acr login --name <registryname>
        ``` 

    - Once you've authored a Recipe, you can publish it to your preferred OCI-compliant registry with [`rad bicep publish`](https://docs.radapp.io/reference/cli/rad_bicep_publish/).

        ```bash
        rad bicep publish --file myrecipe.bicep --target br:<registrypath>/myrecipe:1.1.0
        ```

    - For Terraform Recipes, the easiest way is to publish to a Git repository with anonymous access otherwise, you will need to configure [Git authentication](https://docs.radapp.io/guides/recipes/terraform/howto-private-registry/). Learn more about Recipes in this [How-to guide](https://docs.radapp.io/guides/recipes/howto-author-recipes/).

1. Register the recipe in your environment using the `rad recipe register` command

    **Bicep Recipe via rad CLI**
    ```bash
        rad recipe register default --environment default \
    --resource-type Radius.Resources/postgreSQL \
    --template-kind bicep \
    --template-path <host>/<registry>/rediscache:latest
    ```

    **Terraform recipe via rad CLI**
    ```bash
    rad recipe register default \
    --environment default \
    --resource-type Radius.Datastores/redisCaches \
    --template-kind terraform \
    --template-path git::<git-server-name>/<repository-name>.git//<directory>/<subdirectory>
    ```

    **Via Radius environment bicep**
    ```bicep
    extension radius
    resource env 'Applications.Core/environments@2023-10-01-preview' = {
        name: 'prod'
        properties: {
            compute: {
                kind: 'kubernetes'
                resourceId: 'self'
                namespace: 'default'
            }
            recipes: {
                'Applications.Datastores/redisCaches':{
                    'redis-bicep': {
                        templateKind: 'bicep'
                        templatePath: 'https://ghcr.io/USERNAME/recipes/myrecipe:1.1.0'
                        // Optionally set parameters for all resources calling this Recipe
                        parameters: {
                            port: 3000
                        }
                    }
                    'redis-terraform': {
                        templateKind: 'terraform'
                        templatePath: 'user/recipes/myrecipe'
                        templateVersion: '1.1.0'
                        // Optionally set parameters for all resources calling this Recipe
                        parameters: {
                            port: 3000
                        }
                    }
                }   
            }
        }
    }
    ```

1. Author the resource types in your application and verify that it works as expected
    
    ```bicep
    resource redis 'Radius.Datastores/redisCaches@2023-07-24-preview'= {
        name: 'myresource'
        properties: {
            environment: environment
            application: application
        }
    }
    ```

    Deploy and test the application using the recipe:

    ```bash
    rad deploy app.bicep 
    ```

## Add a functional test to validate your Resource Type and Recipe

< to be filled>

