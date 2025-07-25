extension aws

@description('Radius-provided object containing information about the resource calling the Recipe')
param context object

@description('Name of the EKS cluster used for app deployment')
param eksClusterName string

@description('List of subnetIds for the subnet group')
param subnetIds array = []

// MemoryDB Cluster configuration
// https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-memorydb-cluster.html

@description('Node type for the MemoryDB cluster')
param nodeType string = 'db.t4g.small'

@description('ACL name for the MemoryDB cluster')
param aclName string = 'open-access'

@description('Number of replicas per shard for the MemoryDB cluster')
param numReplicasPerShard int = 0

resource eksCluster 'AWS.EKS/Cluster@default' existing = {
  alias: eksClusterName
  properties: {
    Name: eksClusterName
  }
}

param memoryDBSubnetGroupName string = 'memorydb-subnetgroup-${uniqueString(context.resource.id, eksClusterName)}'
resource subnetGroup 'AWS.MemoryDB/SubnetGroup@default' = {
  alias: memoryDBSubnetGroupName
  properties: {
    SubnetGroupName: memoryDBSubnetGroupName
    SubnetIds: ((empty(subnetIds)) ? eksCluster.properties.ResourcesVpcConfig.SubnetIds : concat(subnetIds,eksCluster.properties.ResourcesVpcConfig.SubnetIds))
    Tags: [
      {
        Key: 'radapp.io/environment'
        Value: context.environment.id
      }
      {
        Key: 'radapp.io/application'
        Value: context.application.id
      }
      {
        Key: 'radapp.io/resource'
        Value: context.resource.id
      }
    ]
  }
}

param memoryDBClusterName string = 'memorydb-cluster-${uniqueString(context.resource.id, eksClusterName)}'
resource memoryDBCluster 'AWS.MemoryDB/Cluster@default' = {
  alias: memoryDBClusterName
  properties: {
    ClusterName: memoryDBClusterName
    NodeType: nodeType
    ACLName: aclName
    SecurityGroupIds: [eksCluster.properties.ClusterSecurityGroupId] 
    SubnetGroupName: subnetGroup.name
    NumReplicasPerShard: numReplicasPerShard
    Tags: [
      {
        Key: 'radapp.io/environment'
        Value: context.environment.id
      }
      {
        Key: 'radapp.io/application'
        Value: context.application.id
      }
      {
        Key: 'radapp.io/resource'
        Value: context.resource.id
      }
    ]
  }
}

output result object = {
  values: {
    host: memoryDBCluster.properties.ClusterEndpoint.Address
    port: memoryDBCluster.properties.ClusterEndpoint.Port
    tls: true
  }
}
