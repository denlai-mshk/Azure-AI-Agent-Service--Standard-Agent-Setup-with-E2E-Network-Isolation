/*
  Streamlined main.bicep for setting up Capability Host for an existing 2nd project
  Using existing AI Foundry (AI Services) account, Cosmos DB, Storage Account, and AI Search resources
  Assumes private endpoints and DNS are already configured externally
  All resource names, IDs, and connection strings are provided as parameters
*/

// ===== PARAMETERS =====

@description('Name of existing AI Services account')
param aiAccountName string

@description('Name of the existing 2nd project in AI Foundry')
param projectName string

@description('Capability Host name for the project')
param projectCapHost string = 'caphostproj'

@description('Resource ID for existing AI Search')
param aiSearchResourceId string

@description('Resource ID for existing Storage Account')
param azureStorageAccountResourceId string

@description('Resource ID for existing Cosmos DB')
param azureCosmosDBAccountResourceId string

@description('AI Project object ID in Microsoft Entra ID (service principal object id)')
param projectPrincipalId string

@description('Cosmos DB connection string for capability host')
param cosmosDBConnection string

@description('Azure Storage connection string for capability host')
param azureStorageConnection string

@description('AI Search connection string for capability host')
param aiSearchConnection string

param deploymentTimestamp string = utcNow('yyyyMMddHHmmss')

// ===== EXTRACT SUBSCRIPTION / RESOURCE GROUP INFO FROM RESOURCE IDS =====

var uniqueSuffix = substring(uniqueString('${resourceGroup().id}-${deploymentTimestamp}'), 0, 4)

var aiSearchParts = split(aiSearchResourceId, '/')
var aiSearchSubscriptionId = aiSearchParts[2]
var aiSearchResourceGroupName = aiSearchParts[4]
var aiSearchName = last(aiSearchParts)

var cosmosParts = split(azureCosmosDBAccountResourceId, '/')
var cosmosDBSubscriptionId = cosmosParts[2]
var cosmosDBResourceGroupName = cosmosParts[4]
var cosmosDBName = last(cosmosParts)

var storageParts = split(azureStorageAccountResourceId, '/')
var azureStorageSubscriptionId = storageParts[2]
var azureStorageResourceGroupName = storageParts[4]
var azureStorageName = last(storageParts)

// ===== EXISTING RESOURCES =====

resource storage 'Microsoft.Storage/storageAccounts@2022-05-01' existing = {
  name: azureStorageName
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
}

resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' existing = {
  name: aiSearchName
  scope: resourceGroup(aiSearchSubscriptionId, aiSearchResourceGroupName)
}

resource cosmosDB 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDBName
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
}

// ===== CAPABILITY HOST MODULE =====

module addProjectCapabilityHost 'modules-network-secured/add-project-capability-host.bicep' = {
  name: 'capabilityHost-configuration-${uniqueSuffix}-deployment'
  params: {
    accountName: aiAccountName
    projectName: projectName
    cosmosDBConnection: cosmosDBConnection
    azureStorageConnection: azureStorageConnection
    aiSearchConnection: aiSearchConnection
    projectCapHost: projectCapHost
  }
  dependsOn: [
    aiSearch
    storage
    cosmosDB
  ]
}

// ===== ROLE ASSIGNMENTS =====

module storageAccountRoleAssignment 'modules-network-secured/azure-storage-account-role-assignment.bicep' = {
  name: 'storage-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(azureStorageSubscriptionId, azureStorageResourceGroupName)
  params: {
    azureStorageName: azureStorageName
    projectPrincipalId: projectPrincipalId
  }
  dependsOn: [
    storage
  ]
}

module cosmosAccountRoleAssignments 'modules-network-secured/cosmosdb-account-role-assignment.bicep' = {
  name: 'cosmos-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(cosmosDBSubscriptionId, cosmosDBResourceGroupName)
  params: {
    cosmosDBName: cosmosDBName
    projectPrincipalId: projectPrincipalId
  }
  dependsOn: [
    cosmosDB
  ]
}

module aiSearchRoleAssignments 'modules-network-secured/ai-search-role-assignments.bicep' = {
  name: 'aisearch-ra-${uniqueSuffix}-deployment'
  scope: resourceGroup(aiSearchSubscriptionId, aiSearchResourceGroupName)
  params: {
    aiSearchName: aiSearchName
    projectPrincipalId: projectPrincipalId
  }
  dependsOn: [
    aiSearch
  ]
}
