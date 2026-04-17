extension radius

resource recipepack 'Radius.Core/recipePacks@2025-08-01-preview' = {
  name: 'pg-recipepack'
  properties: {
    recipes: {
      'Radius.Data/postgreSqlDatabases': {
        recipeKind: 'bicep'
        recipeLocation: 'ghcr.io/reshrahim/recipes/azure-postgresql:1.0'
      }
      'Radius.Compute/containers': {
        recipeKind: 'bicep'
        recipeLocation: 'ghcr.io/reshrahim/recipes/containers:1.0'
      }
      'Radius.Security/secrets': {
        recipeKind: 'bicep'
        recipeLocation: 'ghcr.io/reshrahim/recipes/secrets:1.0'
      }
    }
  }
}
