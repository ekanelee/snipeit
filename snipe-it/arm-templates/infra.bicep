param mysqserverlName string
param location string
param tag string
param mysqllogin string
@secure()
param mysqlpassword string
param SnipeITStorageAccount_name string
param SnipeITDB_name string
param SnipeITServerFarm_name string
param SnipeITWebsite_name string

var dockerFile = loadFileAsBase64('./DockerCompose.yml')
var DockerComposeString = 'COMPOSE|${dockerFile}'
var azFileSettings = true

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-10-01-preview' = {
  name: mysqserverlName
  location: location
  tags:{ project: tag }
  sku: {
    name: 'Standard_B1s'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: mysqllogin
    administratorLoginPassword: mysqlpassword
    storage: {
      storageSizeGB: 20
      iops: 360
      autoGrow: 'Enabled'
      autoIoScaling: 'Enabled'
    }
    version: '8.0.21'
    backup: {
        backupRetentionDays: 7
        geoRedundantBackup: 'Disabled'
    }
    replicationRole: 'None'
    network: {
        publicNetworkAccess: 'Enabled'
    }
}
}

// Deployment of the storage account
resource SnipeITStorageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
    name: SnipeITStorageAccount_name
    location: resourceGroup().location
    tags: {
        Project: 'SnipeIT'
    }
    sku: {
        name: 'Standard_LRS'
    }
    kind: 'StorageV2'
    properties: {
        minimumTlsVersion: 'TLS1_2'
        allowBlobPublicAccess: true
        allowSharedKeyAccess: true
        largeFileSharesState: 'Enabled'
        networkAcls: {
            bypass: 'AzureServices'
            virtualNetworkRules: []
            ipRules: []
            defaultAction: 'Allow'
        }
        supportsHttpsTrafficOnly: true
        encryption: {
            services: {
                file: {
                    keyType: 'Account'
                    enabled: true
                }
                blob: {
                    keyType: 'Account'
                    enabled: true
                }
            }
            keySource: 'Microsoft.Storage'
        }
        accessTier: 'Hot'
    }


    // Nested deployment of file services for the storage account
    resource SnipeITStorageAccountFileServices 'fileServices' = {
        name: 'default'
        // Nested deployment of specific file shares
        // SSL cert and app data file share
        resource SnipeITCertFileShare 'shares' = {
            name: 'snipeit'
            properties: {
                accessTier: 'TransactionOptimized'
                shareQuota: 102400
                enabledProtocols: 'SMB'
            }
        }
        // Logs file share
        resource SnipeITLogsFileShare 'shares' = {
            name: 'snipeit-logs'
            properties: {
                accessTier: 'TransactionOptimized'
                shareQuota: 102400
                enabledProtocols: 'SMB'
            }
        }
    }
}

// MySql settings required else the initial migration fails
resource MySqlServer_innodb_buffer_pool_dump_at_shutdown 'Microsoft.DBforMySQL/flexibleServers/configurations@2022-01-01' = {
  parent: mysqlServer
  name: 'innodb_buffer_pool_dump_at_shutdown'
  properties: {
    value: 'OFF'
  }
}

resource MySqlServer_innodb_buffer_pool_load_at_startup 'Microsoft.DBforMySQL/flexibleServers/configurations@2022-01-01' = {
  parent: mysqlServer
  name: 'innodb_buffer_pool_load_at_startup'
  properties: {
    value: 'OFF'
  }
}

resource MySqlServer_sql_generate_invisible_primary_key 'Microsoft.DBforMySQL/flexibleServers/configurations@2022-01-01' = {
  parent: mysqlServer
  name: 'sql_generate_invisible_primary_key'
  properties: {
    value: 'OFF'
  }
}

resource MySqlServerFirewallRules_AzureIps 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2022-01-01' = {
    name: 'AllowAllWindowsAzureIps'
    parent: mysqlServer
    properties: {
        startIpAddress: '0.0.0.0'
        endIpAddress: '0.0.0.0'
    }
}

//Deployment of the server farm
resource SnipeITServerFarm 'Microsoft.Web/serverfarms@2022-03-01' = {
    name: SnipeITServerFarm_name
    location: resourceGroup().location
    tags: {
        Project: 'SnipeIT'
    }
    sku: {
        name: 'B1'
        tier: 'Basic'
        size: 'B1'
        family: 'B'
        capacity: 1
    }
    kind: 'linux'
    properties: {
        reserved: true
    }
}

// SQL Database deployment
resource SnipeITDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2022-01-01' = {
    name: SnipeITDB_name
    parent: mysqlServer
    location: resourceGroup().location
    properties: {
        charset: 'utf8mb4'
        collation: 'utf8mb4_general_ci'
    }
}

resource SonarQubeWebSite 'Microsoft.Web/sites@2022-09-01' = {
    name: SnipeITWebsite_name
    location: resourceGroup().location
    dependsOn: [
        SnipeITDatabase
        SnipeITStorageAccount
    ]
    tags: {
        Project: 'SnipeIT'
    }
    kind: 'app,linux,container'
    properties: {
        enabled: true
        serverFarmId: SnipeITServerFarm.id
        siteConfig: {
            appCommandLine: ''
            linuxFxVersion: DockerComposeString
            acrUseManagedIdentityCreds: false
            alwaysOn: true
            scmType: 'None'
        }
    }
    resource SnipeITWebsiteAppSettings 'config@2021-02-01' = {
        name: 'appsettings'
        properties: {
            APP_DEBUG: 'false'
            APP_URL: 'https://${SnipeITWebsite_name}.azurewebsites.net'
            APP_KEY: 'base64:6M3RwWh4re1FQGMTent3hON9D7ZJJDHxW1123456789='
            DB_CONNECTION: 'mysql'
            DB_SSL: 'true'
            DB_SSL_IS_PAAS: 'true'
            DB_SSL_CA_PATH: '/var/lib/snipeit/DigiCertGlobalRootCA.crt.pem'
            MYSQL_DATABASE: SnipeITDB_name
            MYSQL_USER: mysqllogin
            MYSQL_PASSWORD: mysqlpassword

            MYSQL_PORT_3306_TCP_ADDR: '${mysqserverlName}.mysql.database.azure.com'
            MYSQL_PORT_3306_TCP_PORT: '3306'

            DOCKER_REGISTRY_SERVER_URL: 'https://index.docker.io/'
            DOCKER_REGISTRY_SERVER_USERNAME: ''
            DOCKER_REGISTRY_SERVER_PASSWORD: ''
            WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'false'
            
            MAIL_DRIVER: 'smtp'
            MAIL_ENV_ENCRYPTION: 'tcp'
            MAIL_PORT_587_TCP_ADDR: 'smtp.sendgrid.net'
            MAIL_PORT_587_TCP_PORT: '587' 
            MAIL_ENV_USERNAME: 'apikey' 
            MAIL_ENV_FROM_ADDR: 'alerts@mydomain.com'
            MAIL_ENV_FROM_NAME: 'Snipe IT'
        }
    }
    resource SnipeITWebsiteConfig 'config@2021-02-01' = if (azFileSettings == true) {
        name: 'web'
        properties: {
            azureStorageAccounts: {
                'snipeit': {
                    type: 'AzureFiles'
                    accountName: SnipeITStorageAccount.name
                    shareName: 'snipeit'
                    mountPath: '/var/lib/snipeit'
                    accessKey: SnipeITStorageAccount.listKeys().keys[0].value
                }
                'snipeit-logs': {
                    type: 'AzureFiles'
                    accountName: SnipeITStorageAccount.name
                    shareName: 'snipeit-logs'
                    mountPath: '/var/www/html/storage/logs'
                    accessKey: SnipeITStorageAccount.listKeys().keys[0].value
                }

            }
        }
    }
}
