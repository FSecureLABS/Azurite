<#
    Azurite Explorer file: AzuriteExplorer.ps1
    Author: Apostolos Mastoris (@Lgrec0)
    License: BSD 3-Clause
    Required Dependencies: Azure PowerShell API
    Optional Dependencies: None
#>

<#
    Main function to retrieve the configuration of all the components in the given Azure subscription.
    The function does not accept any parameters.
    The function creates a number of JSON files that provide information about the various components in the Azure subscription.
#>
function Review-AzureRmSubscription {
<#
    .SYNOPSIS
        Main function to retrieve the configuration of all the components in a given Azure subscription specified by the Subscription Id.
        The function does not accept any parameters. The output is a number of JSON files that provide 
        information about the various components in the Azure subscription.
    .EXAMPLE
        PS C:\> Review-AzureRmSubscription
        
        Main function to retrieve the configuration of all the components in a given Azure subscription specified by the Subscription Id.
#>

# Print script banner and version information.
    Write-Host "   
 █████╗ ███████╗██╗   ██╗██████╗ ██╗████████╗███████╗                        
██╔══██╗╚══███╔╝██║   ██║██╔══██╗██║╚══██╔══╝██╔════╝                        
███████║  ███╔╝ ██║   ██║██████╔╝██║   ██║   █████╗                          
██╔══██║ ███╔╝  ██║   ██║██╔══██╗██║   ██║   ██╔══╝                          
██║  ██║███████╗╚██████╔╝██║  ██║██║   ██║   ███████╗                        
╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝   ╚══════╝                        
                                                                             
            ███████╗██╗  ██╗██████╗ ██╗      ██████╗ ██████╗ ███████╗██████╗ 
            ██╔════╝╚██╗██╔╝██╔══██╗██║     ██╔═══██╗██╔══██╗██╔════╝██╔══██╗
            █████╗   ╚███╔╝ ██████╔╝██║     ██║   ██║██████╔╝█████╗  ██████╔╝
            ██╔══╝   ██╔██╗ ██╔═══╝ ██║     ██║   ██║██╔══██╗██╔══╝  ██╔══██╗
            ███████╗██╔╝ ██╗██║     ███████╗╚██████╔╝██║  ██║███████╗██║  ██║
            ╚══════╝╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝                                                             

Version: 0.6 Beta
Author: Apostolos Mastoris (@Lgrec0)
Email: apostolis.mastoris[at]mwrinfosecurity.com
"
    # Declaration of $ErrorActionPreference in order to be used across the script, when an exception occurs.
    # This settings will supress any error messages that appear in the console.
    $ErrorActionPreference = 'SilentlyContinue'

    # Login to Azure service using Microsoft or organisation credentials.
    # This is the secure option and most preferred.
    Login-AzureRmAccount

    # Ask for an (optional) TenantId
    $tenantId = Read-Host "Please provide a Tenant Id to perform the review (blank to leave to default)"

    # Pring information for the Azure subscriptions available for the user
    Write-Host "Tenant-Id:" $tenantId
    if ($tenantID) {
      Get-AzureRmSubscription -TenantId $tenantId
    } else {
      Get-AzureRmSubscription
    }

    # Request from the user to input the corresponding subscription Id to use during the review.
    $subscriptionId = Read-Host "Please provide the Subscription Id of the subscription to perform the review"
    
    # Get the current state of the subscription. This will assist in determining whether it is a good subscription
    # to use in the review.
    $subscriptionState = Get-AzureRmSubscription -SubscriptionId $subscriptionId | Select-Object -ExpandProperty State

    # If the subscription's state is not 'Enabled', then prompt for an enabled subscription.
    # If the subscription's state is 'Warned', then ask user's consent as this may limit some of the functionality of the tool.
    # More specificaly, if the status is 'Warned', some information may not be possible to be retrieved.
    while ($subscriptionState -ne "Enabled") {
        if ($subscriptionState -eq "Warned") {
            $statusWarnedEnquiry = Read-Host "The subscription is at 'Warned' state and some features will not be fully functional. Do you want to continue? [Y/n]?"
            if ($statusWarnedEnquiry -eq 'Y' -or $statusWarnedEnquiry -eq 'y' ) {
                break
            }
        }
        $subscriptionId = Read-Host "Please provide the subscription id of an active subscription to perform the review"
        $subscriptionState = Get-AzureRmSubscription -SubscriptionId $subscriptionId  | Select-Object -ExpandProperty State
    }

    # Get the current context for the execution of the script.
    $context = Get-AzureRmContext
    
    # Get the current role of the user that has logged in.
    $currentUserRole = Get-AzureRmRoleAssignment -IncludeClassicAdministrators | Where-Object { $_.DisplayName -eq $context.Account } | Select -ExpandProperty RoleDefinitionName
    
    # Print current user's role.
    Write-Host "[*] Current user's role:" $currentUserRole
    
    # Get all the resource groups in the given subscription.
    $resourceGroups = Get-AzureRmResourceGroup

    # If a subscription Id has been provided successfully, then retrieve the context of the current subscription.
    if ($subscriptionId) {
        $currentSubscription = Select-AzureRmSubscription -SubscriptionId $subscriptionId  -WarningAction SilentlyContinue
        $currentSubscription
        
        # Call to retrieve subscription's network configuration.
        $subscriptionConfiguration = Get-CustomAzureRmSubscriptionNetworkConfiguration
    
        # Populate the object that will contain all the information for the subscription's configuration including information for various resources.
        # This object will become available as JSON.
        $objSubscriptionConfigurationProperties = [ordered] @{}
        if ($subscriptionConfiguration) {
            $objSubscriptionConfigurationProperties.Add('subscriptionVNETs', $subscriptionConfiguration)
        }
   
        # Instantiate arrays for each of the resources that will be retrieved from the helper functions.     
        $vmInstancesInfo = @()
        $sqlServersInfo = @()
        $webAppsInfo = @()
        $localNetworkGatewaysInfo = @()
        $keyVaultsInfo = @()

        # Foreach resource group that contains resources perform perform the operations of this script iterativelly on each resource group.
        foreach ($resourceGroup in $resourceGroups) {
            Write-Host "[+] Retrieve components from Resource Group $($resourceGroup.ResourceGroupName) in subscription $($currentSubscription.SubscriptionName) ($subscriptionId):"

            # Retrieve the VM instances for a specific resource group.
            $vmInstances = Get-AzureRmVM -ResourceGroupName $resourceGroup.ResourceGroupName

            # Check if there are any VM instances in the resource group and then retrieve their configuration.
            if ($vmInstances) {
                foreach ($vmInstance in $vmInstances) {
                    if ($vmInstance.StorageProfile.OsDisk.OsType -like '*Windows*') {
                        # Retrieve configuration of Windows VMs.
                        $objVMInstancesInfo = Get-CustomAzureRmWindowsVM -vmInstanceName $vmInstance.Name -vmInstanceResourceGroupName $vmInstance.ResourceGroupName
                    } else {
                        # Retrieve configuration of Linux VMs.
                        $objVMInstancesInfo = Get-CustomAzureRmLinuxVM -vmInstanceName $vmInstance.Name -vmInstanceResourceGroupName $vmInstance.ResourceGroupName
                    }

                    $vmInstancesInfo += $objVMInstancesInfo
                }
            } else { 
                Write-Host "[*] No Virtual Machines were found." 
            }

            # Retrieve configuration for the web applications in the resource group.
            $webApps = Get-AzureRmWebApp -ResourceGroupName $resourceGroup.ResourceGroupName

            # Populate the array with the configuration of the web applications in the resource group.
            if ($webApps) {
                Write-Host '[+] Retrieve Web Application configuration.'
                foreach ($webApp in $webApps) {
                    $objWebAppsInfo = Get-CustomAzureRmWebApp -webApp $webApp -ResourceGroupName $resourceGroup.ResourceGroupName

                    $webAppsInfo += $objWebAppsInfo
                }
            } else { 
                Write-Host "[*] No Web Applications were found." 
            }

            # Retrieve configuration for the SQL Servers in the resource group.
            $sqlServers = Get-AzureRmSqlServer -ResourceGroupName $resourceGroup.ResourceGroupName

            # Populate the array with the configuration of the SQL Servers and SQL Databases in the resource group.
            if ($sqlServers) {
                Write-Host "[+] Retrieve Azure SQL Server and Azure SQL Database configuration."

                foreach ($sqlServer in $sqlServers) {

                    $objSqlServersInfo = Get-CustomAzureRmSqlServer -sqlServer $sqlServer
                    $sqlServersInfo += $objSqlServersInfo
                }
            } else {
                Write-Host "[*] No Azure SQL Servers were found."
            }

            # Retrieve configuration for the Local Network Gateways in each resource group.
            $localNetworkGateways = Get-AzureRmLocalNetworkGateway -ResourceGroupName $resourceGroup.ResourceGroupName -WarningAction SilentlyContinue

            # Populate the array with the configuration of the Local Network Gateways in the resource group.
            if ($localNetworkGateways) {
                Write-Host '[+] Retrieve Local Network Gateways configuration.'
                foreach ($localNetworkGateway in $localNetworkGateways) {
                    $objLocalNetworkGatewaysInfo = Get-CustomAzureRmGateway -localNetworkGatewayName $localNetworkGateway.Name -gatewayResourceGroupName $resourceGroup.ResourceGroupName
                    $localNetworkGatewaysInfo += $objLocalNetworkGatewaysInfo
                }
            } else {
                Write-Host "[*] No Local Network Gateways were found."
            }

            # Retrieve configuration of the Azure Key Vaults in each resource group.
            $keyVaults = Get-AzureRmKeyVault -ResourceGroupName $resourceGroup.ResourceGroupName -WarningAction SilentlyContinue

            # Populate the array with the configuration of the Azure Key Vaults in each resource group.
            if ($keyVaults) {
                Write-Host '[+] Retrieve Key Vault configuration.'
                foreach ($keyVault in $keyVaults) {
                    $objKeyVaultsInfo = Get-CustomAzureRmKeyVault -keyVaultInstanceName $keyVault.VaultName -keyVaultResourceGroupName $resourceGroup.ResourceGroupName
                    $keyVaultsInfo += $objKeyVaultsInfo
                }
            } else {
                Write-Host '[*] No Key Vaults have been configured.'
            }
        }

        # Export configuration of Virtual Machines to JSON and store in a file.
        if ($vmInstancesInfo) { 
            $vmInstancesInfo | ConvertTo-Json -Depth 6 | Out-File $(".\azure-vms_" + $subscriptionId + "_" + $context.Account + ".json") -Encoding UTF8
            <#
            $azureVMContent = $vmInstancesInfo | ConvertTo-Json -Depth 6 | Out-File $()
            $azureVMFilePath = ".\azure-vms_" + $subscriptionId + "_" + $context.Account + ".json" 
            
            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
            [System.IO.File]::W‌​riteAllLines($azureVMFilePath, $azureVMContent, $Utf8NoBomEncoding)
            #>
        }

        # Export configuration of SQL Servers and SQL Databases in JSON and store in a file.
        if ($sqlServersInfo) {
            $sqlServersInfo | ConvertTo-Json -Depth 6 | Out-File $(".\azure-sqlservers_" + $subscriptionId + "_" + $context.Account +  ".json") -Encoding UTF8
            
            <#
            $azureSqlServersContent = $sqlServersInfo | ConvertTo-Json -Depth 6
            $azureSqlServersFilePath = ".\azure-sqlservers_" + $subscriptionId + "_" + $context.Account +  ".json"

            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
            [System.IO.File]::W‌​riteAllLines($azureSqlServersFilePath, $azureSqlServersContent, $Utf8NoBomEncoding)
            #>

            $objSubscriptionConfigurationProperties.Add('subscriptionSqlServers', $sqlServersInfo)
        }

        # Export configuration of all the Web Applications in JSON and store in a file.
        if ($webAppsInfo) {
            $webAppsInfo | ConvertTo-Json -Depth 3 | Out-File $(".\azure-websites_" + $subscriptionId + "_" + $context.Account +  ".json") -Encoding UTF8
            
            <#
            $azureWebAppsContent = $webAppsInfo | ConvertTo-Json -Depth 6
            $azureWebAppsFilePath = ".\azure-websites_" + $subscriptionId + "_" + $context.Account +  ".json"

            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
            [System.IO.File]::W‌​riteAllLines($azureWebAppsFilePath, $azureWebAppsContent, $Utf8NoBomEncoding)
            #>

            $objSubscriptionConfigurationProperties.Add('subscriptionWebApps', $webAppsInfo)
        }

        # Add the Local Network Gateways resources to the subscription's configuration.
        if ($localNetworkGatewaysInfo) {
            $objSubscriptionConfigurationProperties.Add('subscriptionLocalNetworkGateways', $localNetworkGatewaysInfo)
        }

        # Export cofniguration of the Azure Key Vaults in JSON and store in a file.
        if ($keyVaultsInfo) {
            $keyVaultsInfo | ConvertTo-Json -Depth 3 | Out-File $(".\azure-key-vaults_" + $subscriptionId + "_" + $context.Account +  ".json") -Encoding UTF8
            
            <#
            $azureKeyVaultsContent = $keyVaultsInfo | ConvertTo-Json -Depth 6
            $azureKeyVaultsFilePath = ".\azure-key-vaults_" + $subscriptionId + "_" + $context.Account +  ".json"

            $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
            [System.IO.File]::W‌​riteAllLines($azureKeyVaultsFilePath, $azureKeyVaultsContent, $Utf8NoBomEncoding)
            #>

            $objSubscriptionConfigurationProperties.Add('subscriptionKeyVaults', $keyVaultsInfo)
        }

        # Create the object that contains all the information for the subscription configuration.
        $objSubscriptionConfiguration = New-Object -TypeName PSObject -Property $objSubscriptionConfigurationProperties

        # Export configuration of the Azure subscription in JSON and store in a file.
        $objSubscriptionConfiguration | ConvertTo-Json -Depth 10 | Out-File $(".\azure-subscription_" + $subscriptionId + "_" + $context.Account +  ".json") -Encoding UTF8

        <#
        $azureSubscriptionConfigurationContent = $objSubscriptionConfiguration | ConvertTo-Json -Depth 6
        $azureSubscriptionConfigurationFilePath = ".\azure-subscription_" + $subscriptionId + "_" + $context.Account +  ".json"

        $Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($False)
        [System.IO.File]::W‌​riteAllLines($azureSubscriptionConfigurationFilePath, $azureSubscriptionConfigurationContent, $Utf8NoBomEncoding)
        #>

        # finally create a json file with all resources (as not all resource types are handled in a greater level of detail)
        Get-AzureRmResource | ConvertTo-Json -Depth 10 | Out-File $(".\azure-cmdb_" + $subscriptionId + "_" + $context.Account +  ".json") -Encoding UTF8

        # Present information/statistics about the Azure subscription. 
        Write-Host "[*] Azure Subscription Information - Subscription Id $subscriptionId"
        Write-Host "    [-] Resource Groups: $($resourceGroups.Count)"
        Write-Host "    [-] Virtual Networks (VNets): $($objSubscriptionConfiguration.subscriptionVNETs.Length)"
        $subscriptionTotalSubnets = 0
        foreach ($subscriptionVNET in $objSubscriptionConfiguration.subscriptionVNETs) {
            $subscriptionTotalSubnets = $subscriptionTotalSubnets + $subscriptionVNET.vnetSubnets.Length
        }
        Write-Host "    [-] Subnets: $subscriptionTotalSubnets"
        Write-Host "    [-] Virtual Machines: $($vmInstancesInfo.Length)"
        Write-Host "    [-] Azure SQL Servers: $($sqlServersInfo.Length)"
        $subscriptionTotalSqlDatabases = 0
        foreach ($subscriptionSqlServer in $objSubscriptionConfiguration.subscriptionSqlServers) {
            $subscriptionTotalSqlDatabases = $subscriptionTotalSqlDatabases + $subscriptionSqlServer.sqlServerDatabases.Length
        }
        Write-Host "    [-] Azure SQL Databases: $subscriptionTotalSqlDatabases"
        Write-Host "    [-] Azure Web Applications: $($webAppsInfo.Length)"
    } else {
        Write-Host "[!] Please provide Subscription Id." 
    }
}

<#
    .DESCRIPTION 
    Helper function to retrieve configuration information for Windows systems.

    .PARAMETER vmInstanceName
    The Virtual Machine's name.
    
    .PARAMETER vInstanceResourceGroupName
    The Resource Group's name.

    .OUTPUT
    The function returns an object populated with the VM's details.
#>
function Get-CustomAzureRmWindowsVM {
    Param (
        [String] $vmInstanceName,
        [String] $vmInstanceResourceGroupName
    )
    
    Write-Host "[+] Retrieve Virtual Machine's $vmInstanceResourceGroupName - $vmInstanceName configuration." 

    # Get VM object based on the provided parameters.
    $vmInstance = Get-AzureRmVM -Name $vmInstanceName -ResourceGroupName $vmInstanceResourceGroupName

    # Retrieve the network configuration.
    $vmInstanceNetworkConfiguration = Get-CustomAzureRmNetworkConfiguration -vmInstance $vmInstance

    # Retrieve the encryption configuration.
    $vmInstanceEncryption =  Get-CustomAzureRmVMEncryption -vmInstance $vmInstance
   
    # Retrieve the Network Security Groups (NSGs) configuration.
    $vmInstanceNetworkSecurityGroups = Get-CustomAzureRmNetworkSecurityGroups -vmInstance $vmInstance

    # Retrieve the VM's security extensions.
    $vmInstanceSecurityExtensions = Get-CustomAzureRmVMSecurityExtensions -vmInstance $vmInstance

    # Populate the object that will be returned from the function with VM's details.
    $objVMInstanceInfoProperties = [ordered] @{
        vmName = $vmInstance.Name
        vmResourceGroupName = $vmInstance.ResourceGroupName
        vmLocation = $vmInstance.Location
        itemType = 'Virtual Machine'
        vmStorageProfile = $vmInstance.StorageProfile
        vmNetworkConfiguration = $vmInstanceNetworkConfiguration
        vmNetworkSecurityGroups = $vmInstanceNetworkSecurityGroups
        vmEncryption = $vmInstanceEncryption
    }
    
    # If network security extensions are available, include it in the object.
    if ($vmInstanceSecurityExtensions) {
        $objVMInstanceInfoProperties.Add('vmSecurityExtensions', $vmInstanceSecurityExtensions)
    }

    # Create the object containing VM's details.
    $objVMInstanceInfo = New-Object -TypeName PSObject -Property $objVMInstanceInfoProperties
    
    # Return the object to the function call.
    return $objVMInstanceInfo
}



<#
    .DESCRIPTION 
    Helprer fuction to retrieve configuration information for Linux systems.

    .PARAMETER vmInstanceName
    The Virtual Machine's name.
    
    .PARAMETER vInstanceResourceGroupName
    The Resource Group's name.

    .OUTPUT
    The function returns an object populated with the VM's details.
#>
function Get-CustomAzureRmLinuxVM {
    Param (
        [String] $vmInstanceName,
        [String] $vmInstanceResourceGroupName
    )
  
    Write-Host "[+] Retrieve Virtual Machine's $vmInstanceResourceGroupName - $vmInstanceName configuration." 

    # Get VM object based on the provided parameters.
    $vmInstance = Get-AzureRmVM -Name $vmInstanceName -ResourceGroupName $vmInstanceResourceGroupName
    
    # Retrieve the network configuration.
    $vmInstanceNetworkConfiguration = Get-CustomAzureRmNetworkConfiguration -vmInstance $vmInstance

    # System's additional configuration
    if ($vmInstance.OSProfile.LinuxConfiguration.DisablePasswordAuthentication) { $passwordAuthenticationStatus = 'Disabled' }
    else { $passwordAuthenticationStatus = 'Enabled'}
    
    # Retrieve the encryption configuration.
    $vmInstanceEncryption = Get-CustomAzureRmVMEncryption -vmInstance $vmInstance
    
    # Retrieve the Network Security Groups (NSGs) configuration.
    $vmInstanceNetworkSecurityGroups = Get-CustomAzureRmNetworkSecurityGroups -vmInstance $vmInstance

    # Retrieve the VM's security extensions.
    $vmInstanceSecurityExtensions = Get-CustomAzureRmVMSecurityExtensions -vmInstance $vmInstance

    # Populate the object that will be returned from the function with VM's details.
    $objVMInstanceInfoProperties = [ordered] @{
        vmName = $vmInstance.Name
        vmResourceGroupName = $vmInstance.ResourceGroupName
        vmLocation = $vmInstance.Location
        vmStorageProfile = $vmInstance.StorageProfile
        vmNetworkConfiguration = $vmInstanceNetworkConfiguration
        vmNetworkSecurityGroups = $vmInstanceNetworkSecurityGroups
        vmEncryption = $vmInstanceEncryption
        vmPasswordAuthentication = $passwordAuthenticationStatus
    }

    # If network security extensions are available, include it in the object.
    if ($vmInstanceSecurityExtensions) {
        $objVMInstanceInfoProperties.Add('vmSecurityExtensions', $vmInstanceSecurityExtensions)
    }

    # Create the object containing VM's details.
    $objVMInstanceInfo = New-Object -TypeName PSObject -Property $objVMInstanceInfoProperties
    
    # Return the object to the function call.
    return $objVMInstanceInfo

}

<#
    .DESCRIPTION 
    Helprer function to retrieve configuration for Azure SQL Server systems.

    .PARAMETER sqlServer
    The Azure SQL Server instance which has been retrieved from a previous operation.
    
    .OUTPUT
    The function returns an object populated with the Azure SQL Server's details.
#>
function Get-CustomAzureRmSqlServer {
    Param ([System.Object] $sqlServer)

    # Populate the object to return the Azure SQL Server's details.
    $objSqlServerInfoProperties = [ordered] @{
        sqlServerName = $sqlServer.ServerName
        sqlServerResourceGroupName = $sqlServer.ResourceGroupName
        sqlServerLocation = $sqlServer.Location
        sqlServerAdministratorLogin = $sqlServer.SqlAdministratorLogin
        sqlServerVersion = $sqlServer.ServerVersion
    }
    
    # Retrieve the Azure Active Directory administrator that has been granted access to the Azure SQL Server.
    # If a user has been configured, pupulate the object.
    $sqlServerADAdministrator = Get-AzureRmSqlServerActiveDirectoryAdministrator -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName
    if ($sqlServerADAdministrator) { 
        $objSqlServerInfoProperties.Add('sqlServerADAdministrator', $sqlServerADAdministrator) 
    }

    # Retrieve the Azure SQL Server's auditing policy.
    $sqlServerAuditingPolicy = Get-AzureRmSqlServerAuditingPolicy -ServerName $sqlServer.ServerName -ResourceGroupName $sqlServer.ResourceGroupName
    $objSqlServerInfoProperties.Add('sqlServerAuditingPolicy', $sqlServerAuditingPolicy)
    
    # Retrieve the Azure SQL Server's communication links.
    $sqlServerCommunicationLinks = Get-AzureRmSqlServerCommunicationLink -ResourceGroupName $sqlServer.ResourceGroupName -ServerName $sqlServer.ServerName
    
    # In case that there are Azure SQL Server communication links, populate the object which each one of them recursively.
    if ($sqlServerCommunicationLinks) {
        $sqlServerCommunicationLinkInfo = @()
        $index = 1
        foreach ($sqlServerCommunicationLink in $sqlServerCommunicationLinks) {
            $sqlServerCommunicationLinkInfo += $sqlServerCommunicationLink                
        }

        $objSqlServerInfoProperties.Add('sqlServerCommunicationLinks', $sqlServerCommunicationLinkInfo)
    }
        
    # Retrieve the Azure SQL Server's firewall rules. 
    $sqlServerFirewallRules = Get-AzureRmSqlServerFirewallRule -ResourceGroupName $sqlServer.ResourceGroupName -ServerName $sqlServer.ServerName        
    $sqlServerFirewallRuleInfo = @()
    $index = 1
    foreach ($sqlServerFirewallRule in $sqlServerFirewallRules) {
        $sqlServerFirewallRuleInfo += $sqlServerFirewallRule
    }

    $objSqlServerInfoProperties.Add('sqlServerFirewallRules', $sqlServerFirewallRuleInfo)
    
    # Retrieve the Azure SQL Databases that are hosted on the current Azure SQL Server.
    $sqlServerDatabases = Get-AzureRmSqlDatabase -ResourceGroupName $sqlServer.ResourceGroupName -ServerName $sqlServer.ServerName
        
    # In case there are any Azure SQL Databases hosted on the current Azure SQL Server, retrieve the details for each of the Azure SQL Database, recursively.
    if ($sqlServerDatabases) {
        $sqlServerDatabaseInfo = @()
        foreach ($sqlServerDatabase in $sqlServerDatabases) {
            # Retrieve the configuration details for an Azure SQL Database.
            $objSqlServerDatabaseInfo = Get-CustomAzureRmSqlDatabase -sqlDatabase $sqlServerDatabase

            
            if ($objSqlServerDatabaseInfo) { 
                $sqlServerDatabaseInfo += $objSqlServerDatabaseInfo 
            }
        }

        $objSqlServerInfoProperties.Add('sqlServerDatabases', $sqlServerDatabaseInfo)
    }
    
    # Create the object containing Azure SQL Server's details.
    $objSqlServerInfo = New-Object -TypeName PSObject -Property $objSqlServerInfoProperties

    # Return the object to the function call.
    return $objSqlServerInfo

}

<#
    .DESCRIPTION 
    Helprer function to retrieve the details for the Azure SQL Databases.

    .PARAMETER $sqlDatabase
    The Azure SQL Database instance that has been retrieved during a previous operation.
    
    .OUTPUT
    The function returns an object populated with the Azure SQL Database's details.
#>
function Get-CustomAzureRmSqlDatabase {
    Param ([System.Object] $sqlDatabase)

    # We are not interested in the configuration of the master DB (default Azure Database).
    # Retrieve the Azure SQL Database's details if the database name is not 'master'.
    if ($sqlDatabase.DatabaseName -ne 'master') {
        # Populate the object to return with Azure SQL Server's details.
        $objSqlDatabaseInfoProperties = [ordered] @{
            sqlDatabaseName = $sqlDatabase.DatabaseName
            sqlDatabaseServerName = $sqlDatabase.ServerName
            sqlDatabaseResourceGroupName = $sqlDatabase.ResourceGroupName
            sqlDatabaseLocation = $sqlDatabase.Location
            sqlDatabaseEdition = $sqlDatabase.Edition
            sqlDatabaseStatus = $sqlDatabase.Status
        }

        # Retrieve the Azure SQL Database's auditing policy.
        $sqlDatabaseAuditingPolicy = Get-AzureRmSqlDatabaseAuditingPolicy -ResourceGroupName $sqlDatabase.ResourceGroupName -ServerName $sqlDatabase.ServerName -DatabaseName $sqlDatabase.DatabaseName
        if ($sqlDatabaseAuditingPolicy) { 
            $objSqlDatabaseInfoProperties.Add('sqlDatabaseAuditingPolicy', $sqlDatabaseAuditingPolicy) 
        }

        # Retrieve the Azure SQL Database's data masking policy.
        $sqlDatabaseDataMaskingPolicy = Get-AzureRmSqlDatabaseDataMaskingPolicy -ResourceGroupName $sqlDatabase.ResourceGroupName -ServerName $sqlDatabase.ServerName -DatabaseName $sqlDatabase.DatabaseName
        if ($sqlDatabaseDataMaskingPolicy) {

            # Initiliase the object that returns the data masking policy.
            $objSqlDatabaseDataMaskingPolicy = New-Object PSObject
            if ($sqlDatabaseDataMaskingPolicy.DataMaskingState -eq 2) { 
                $objSqlDatabaseDataMaskingPolicy | Add-Member NoteProperty 'DataMaskingState' 'Disabled' 
            }
            else { 
                $objSqlDatabaseDataMaskingPolicy | Add-Member NoteProperty 'DataMaskingState' $sqlDatabaseDataMaskingPolicy.DataMaskingState 
            }
            
            # Retrieve the users that are able to view the data without masking.
            $objSqlDatabaseDataMaskingPolicy | Add-Member NoteProperty 'PrivilegedUsers' $sqlDatabaseDataMaskingPolicy.PrivilegedUsers
        
            $objSqlDatabaseInfoProperties.Add('sqlDatabaseDataMaskingPolicy', $objSqlDatabaseDataMaskingPolicy)
        }

        # Retrieve the Azure SQL Database's connection policy details (connection strings) for various technologies.
        $sqlDatabaseSecureConnectionPolicy = Get-AzureRmSqlDatabaseSecureConnectionPolicy -ResourceGroupName $sqlDatabase.ResourceGroupName -ServerName $sqlDatabase.ServerName -DatabaseName $sqlDatabase.DatabaseName
        if ($sqlDatabaseSecureConnectionPolicy) { 
            $objSqlDatabaseSecureConnectionPolicy = New-Object PSObject
            $objSqlDatabaseSecureConnectionPolicy | Add-Member NoteProperty 'ProxyDnsName' $sqlDatabaseSecureConnectionPolicy.ProxyDnsName
            $objSqlDatabaseSecureConnectionPolicy | Add-Member NoteProperty 'ProxyPort' $sqlDatabaseSecureConnectionPolicy.ProxyPort

            $objSqlDatabaseSecureConnectionPolicyConnectionStrings = New-Object PSObject
            $objSqlDatabaseSecureConnectionPolicyConnectionStrings | Add-Member NoteProperty 'AdoNetConnectionString' $sqlDatabaseSecureConnectionPolicy.ConnectionStrings.AdoNetConnectionString
            $objSqlDatabaseSecureConnectionPolicyConnectionStrings | Add-Member NoteProperty 'JdbcConnectionString' $sqlDatabaseSecureConnectionPolicy.ConnectionStrings.JdbcConnectionString
            
            # Currently having problems in converting to JSON.
            # $objSqlDatabaseSecureConnectionPolicyConnectionStrings | Add-Member NoteProperty 'PhpConnectionString' $sqlDatabaseSecureConnectionPolicy.ConnectionStrings.PhpConnectionString
            
            $objSqlDatabaseSecureConnectionPolicyConnectionStrings | Add-Member NoteProperty 'OdbcConnectionString' $sqlDatabaseSecureConnectionPolicy.ConnectionStrings.OdbcConnectionString
            $objSqlDatabaseSecureConnectionPolicy | Add-Member NoteProperty 'ConnectionStrings' $objSqlDatabaseSecureConnectionPolicyConnectionStrings

            # Check whether secure connection policy is enforced.
            if ( $sqlDatabaseSecureConnectionPolicy.SecureConnectionState -eq 1 ) { 
                $objSqlDatabaseSecureConnectionPolicy | Add-Member NoteProperty 'SecureConnectionState' 'Optional' 
            }
            else {  
                $objSqlDatabaseSecureConnectionPolicy | Add-Member NoteProperty 'SecureConnectionState' $sqlDatabaseSecureConnectionPolicy.SecureConnectionState 
            }
        
            $objSqlDatabaseInfoProperties.Add('sqlDatabaseSecureConnectionPolicy', $objSqlDatabaseSecureConnectionPolicy) 
        }
        
        # Retrieve the Azure SQL Database's threat detection policy details.
        $sqlDatabaseThreatDetectionPolicy = Get-AzureRmSqlDatabaseThreatDetectionPolicy -ResourceGroupName $sqlDatabase.ResourceGroupName -ServerName $sqlDatabase.ServerName -DatabaseName $sqlDatabase.DatabaseName
        if ($sqlDatabaseThreatDetectionPolicy) {
            
            $objsqlDatabaseThreadDetectionPolicy = New-Object PSObject
            
            if ($sqlDatabaseThreatDetectionPolicy.ThreatDetectionState -eq 2) { 
                $objsqlDatabaseThreadDetectionPolicy | Add-Member NoteProperty 'ThreatDetectionState' 'New' 
            }
            else { 
                $objsqlDatabaseThreadDetectionPolicy | Add-Member NoteProperty 'ThreatDetectionState' $sqlDatabaseThreatDetectionPolicy.ThreatDetectionState 
            }

            $objsqlDatabaseThreadDetectionPolicy | Add-Member NoteProperty 'NotificationRecipientsEmails' $sqlDatabaseThreatDetectionPolicy.NotificationRecipientsEmails
            $objsqlDatabaseThreadDetectionPolicy | Add-Member NoteProperty 'EmailAdmins' $sqlDatabaseThreatDetectionPolicy.EmailAdmins
            $objsqlDatabaseThreadDetectionPolicy | Add-Member NoteProperty 'ExcludedDetectionTypes' $sqlDatabaseThreatDetectionPolicy.ExcludedDetectionTypes

            $objSqlDatabaseInfoProperties.Add('sqlDatabaseThreatDetectionPolicy', $objSqlDatabaseThreatDetectionPolicy)
        
        }
        
        # Retrieve the configuration for the Azure SQL Database's Transparent Data Encryption (TDE). 
        $sqlDatabaseTransparentDataEncryption = Get-AzureRmSqlDatabaseTransparentDataEncryption -ResourceGroupName $sqlDatabase.ResourceGroupName -ServerName $sqlDatabase.ServerName -DatabaseName $sqlDatabase.DatabaseName
        if ( $sqlDatabaseTransparentDataEncryption.State -eq 1 ) { 
            $objSqlDatabaseInfoProperties.Add('sqlDatabaseTransparentDataEncryption', 'Disabled') 
        }
        else { 
            $objSqlDatabaseInfoProperties.Add('sqlDatabaseTransparentDataEncryption','Enabled')
        }
        
        # Create the object containing Azure SQL Database's details.
        $objSqlDatabaseInfo = New-Object -TypeName PSObject -Property $objSqlDatabaseInfoProperties

        # Return the object to the function call.
        return $objSqlDatabaseInfo

    } else {
        return $null
    }
}


<#
    .DESCRIPTION 
    Helprer function to retrieve the network configuration for VM's and VNET Gateways.

    .PARAMETER $vmInstance
    The Virtual Machine's instance.

    .PARAMATER $gatewayInstance
    The VNET Gateway's instance.

    .OUTPUT
    The function returns an object which contains the network configuration of either a VM or a VNET Gateway.
#>
function Get-CustomAzureRmNetworkConfiguration {
    Param (
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $vmInstance,
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetworkGateway] $gatewayInstance
    )
    
    # Check if the cmdlet was called with input a VM instance.
    if ($vmInstance) {
        
        # Get the network interface IDs of the VM.
        $vmNetworkInterfaceIds = $vmInstance.NetworkInterfaceIDs

        $vmNetworkInterfaceInfo = @()
        # For each VM network interface retrieve the configuration and store it in an object.
        foreach ($vmNetworkInterfaceId in $vmNetworkInterfaceIds) {
            # Get the name of the network interface from the network interface Id.
            # The format of a network interface Id is: 
            #/subscriptions/<SubscriptionId>/resourceGroups/<ResourceGroup>/providers/Microsoft.Network/networkInterfaces/windows311400
            $vmNetworkInterfaceName = $vmNetworkInterfaceId | Split-Path -Leaf
        
            # Retrieve network inteface details.
            $vmNetworkInterfaceConfig = Get-AzureRmNetworkInterface -Name $vmNetworkInterfaceName -ResourceGroupName $vmInstance.ResourceGroupName
        
            $vmNetworkInterfaceIpConfigurationInfo = @()
            # Each VM can have multiple interfaces (IpConfigurations)
            # Create an array of all the IpConfigurations.
            foreach ($ipConfiguration in $vmNetworkInterfaceConfig.IpConfigurations) {
                $objVMNetworkInterfaceIpConfigurationInfo = New-Object PSObject
                $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationName' $ipConfiguration.Name
                $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationPrivateIpAddress' $ipConfiguration.PrivateIpAddress
                $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationPrivateIpAddressAllocationMethod' $ipConfiguration.PrivateIpAllocationMethod
                $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationMacAddress' $ipConfiguration.MacAddress

                # The VM references the public IP address interface separately. 
                # Get the name of the public IP address interface, if available.
                if ($ipConfiguration.PublicIpAddress) {
                    $vmNetworkInterfaceIpConfigurationPublicIpInterfaceName = ($ipConfiguration.PublicIpAddress.Id) | Split-Path -Leaf
                
            
                    # Get the VM IpConfiguration's public IP address and populate the object.
                    $objVMNetworkInterfaceIpConfigurationPublicIp = Get-AzureRmPublicIpAddress -Name $vmNetworkInterfaceIpConfigurationPublicIpInterfaceName -ResourceGroupName $vmInstance.ResourceGroupName
                    $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationPublicIpAddress' $objVMNetworkInterfaceIpConfigurationPublicIp.IpAddress
                    $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationPublicIpAddressAllocationMethod' $objVMNetworkInterfaceIpConfigurationPublicIp.PublicIpAllocationMethod
                }

                # Get the Virtual Network (VNet) name from the Subnet UNC
                $vmVNETName = ($ipConfiguration.Subnet.Id).Split('/')[-3]
                $vmVNETSubnetName = ($ipConfiguration.Subnet.Id | Split-Path -Leaf)

                $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationVNETName' $vmVNETName
                $objVMNetworkInterfaceIpConfigurationInfo | Add-Member 'vmNetworkConfigurationSubnetName' $vmVNETSubnetName
            
               
                # TODO: Routing configuration.



                $vmNetworkInterfaceIpConfigurationInfo += $objVMNetworkInterfaceIpConfigurationInfo
            }

            $objVMNetworkInterfaceInfo = New-Object PSObject
            $objVMNetworkInterfaceInfo | Add-Member 'vmNetworkConfigurationIpConfigurations' $vmNetworkInterfaceIpConfigurationInfo
            $objVMNetworkInterfaceInfo | Add-Member 'vmNetworkConfigurationDNSSettings' $vmNetworkInterfaceConfig.DnsSettingsText
            $objVMNetworkInterfaceInfo | Add-Member 'vmNetworkConfigurationIpForwarding' $vmNetworkInterfaceConfig.EnableIPForwarding

            $vmNetworkInterfaceInfo += $objVMNetworkInterfaceInfo   
        }

        return $vmNetworkInterfaceInfo

    } elseif ($virtualNetworkGatewayInstance) {

        # Each VNet ateway can have multiple interfaces (IpConfigurations).
        # Retrieve the information for each VNet Gateway.
        $virtualNetworkGatewayIpConfigurationInfo = @()
        foreach ($virtualNetworkGatewayIpConfiguration in $virtualNetworkGatewayInstance.IpConfigurations) {
                                           
            $objVirtualNetworkGatewayIpConfigurationInfo = New-Object PSObject
            $objVirtualNetworkGatewayIpConfigurationInfo | Add-Member NoteProperty 'virtualNetworkGatewayPrivateIpAddress' $virtualNetworkGatewayIpConfiguration.PrivateIpAddress
            $objVirtualNetworkGatewayIpConfigurationInfo | Add-Member NoteProperty 'virtualNetworkGatewayPrivateIpAddressAllocationMethod' $virtualNetworkGatewayIpConfiguration.PrivateIpAllocationMethod
            # $objVirtualNetworkGatewayIpConfigurationInfo | Add-Member NoteProperty 'virtualNetworkGatewayMacAddress' $virtualNetworkGatewayIpConfiguration.MacAddress
            
            # The VNet Gateway references the public IP address interface separately.          
            # Get the name of public IP address interface, if available.
            if ($virtualNetworkGatewayIpConfiguration.PublicIpAddress) {
                $virtualNetworkGatewayIpConfigurationPublicIpInterfaceName = ($virtualNetworkGatewayIpConfiguration.PublicIpAddress.Id) | Split-Path -Leaf
            
                # Get VNet Gateway Ip Configuration's public IP address.
                $virtualNetworkGatewayIpConfigurationPublicIpAddress = Get-AzureRmPublicIpAddress -Name $virtualNetworkGatewayIpConfigurationPublicIpInterfaceName -ResourceGroupName $virtualNetworkGatewayInstance.ResourceGroupName
                $objVirtualNetworkGatewayIpConfigurationInfo | Add-Member 'virtualNetworkGatewayPublicIpAddress' $virtualNetworkGatewayIpConfigurationPublicIpAddress.IpAddress
                $objVirtualNetworkGatewayIpConfigurationInfo | Add-Member 'virtualNetworkGatewayPublicIpAddressAllocationMethod' $virtualNetworkGatewayIpConfigurationPublicIpAddress.PublicIpAllocationMethod
            }
                                  
            $virtualNetworkGatewayIpConfigurationInfo += $objVirtualNetworkGatewayIpConfigurationInfo
        }
        
        return $virtualNetworkGatewayIpConfigurationInfo
    }
}

<#
    .DESCRIPTION 
    Helprer function to retrieve the encryption status and configuration for the VMs.

    .PARAMETER $vmInstance
    The Virtual Machine's instance.

    .OUTPUT
    The function returns an object which contains the encryption status and configuration of a VM.
#>
function Get-CustomAzureRmVMEncryption {
    Param ([Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $vmInstance)
    
    # Retrieve the encryption status for the VM.
    $vmEncryptionStatus = Get-AzureRmVMDiskEncryptionStatus -ResourceGroupName $vmInstance.ResourceGroupName -VMName $vmInstance.Name

    # Initialiase the object that will contain theinformation for the VM's encryption configuration.
    $objVMDiskEncryption = New-Object PSObject

    # Check whether the 'Data' volume is encrypted.
    # Status '1': NotEncrypted
    if (($vmEncryptionStatus.DataVolumesEncrypted -eq '1') -or ($vmEncryptionStatus.DataVolumesEncrypted -eq '2')) { 
        # $objVMDiskEncryption | Add-Member NoteProperty 'dataVolumesEncryption' $vmEncryptionStatus.DataVolumesEncrypted
        $objVMDiskEncryption | Add-Member NoteProperty 'dataVolumesEncryption' 'Disabled'
    } else {
        $objVMDiskEncryption | Add-Member NoteProperty 'dataVolumesEncryption' 'Enabled'
    }    

    # Check whether the 'Os' volume is encrypted.
    # Status '1': NotEncrypted
    # Status '2': Unknown
    if (($vmEncryptionStatus.OsVolumeEncrypted -eq '1') -or ($vmEncryptionStatus.OsVolumeEncrypted -eq '2')) { 
        
        # $objVMDiskEncryption | Add-Member NoteProperty 'osVolumeEncryption' $vmEncryptionStatus.OsVolumeEncrypted
        $objVMDiskEncryption | Add-Member NoteProperty 'osVolumeEncryption' 'Disabled'
           
    } else {
        # $objVMDiskEncryption | Add-Member NoteProperty 'osVolumeEncryption' $vmEncryptionStatus.OsVolumeEncrypted
        $objVMDiskEncryption | Add-Member NoteProperty 'osVolumeEncryption' 'Enabled'
        $objVMDiskEncryption | Add-Member NoteProperty 'osVolumeEncryptionInfo'  $vmEncryptionStatus.OsVolumeEncryptionSettings
    }    
    return $objVMDiskEncryption
}

<#
    .DESCRIPTION 
    Helprer function to retrieve the security extensions that have been deployed and configuratio in a VM.

    .PARAMETER $vmInstance
    The Virtual Machine's instance.

    .OUTPUT
    The function returns an object which contains the details of the extensions that have been deployed in a VM.
#>
function Get-CustomAzureRmVMSecurityExtensions {
    Param ([Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $vmInstance)

    $vmExtensionInfo = @()

    # For some reason this function does not work if I don't retrieve the VM object.
    $objVMInstance = Get-AzureRmVM -ResourceGroupName $vmInstance.ResourceGroupName -Name $vmInstance.Name

    # Retrieve the information for all the extensions that is believed to be security-related.
    foreach ($vmExtension in $objVMInstance.Extensions) {
        if ($vmExtension.Publisher -like '*security*') {
            $objVMExtensionInfo = New-Object PSObject
            $objVMExtensionInfo | Add-Member NoteProperty 'vmExtensionPublisher' $vmExtension.Publisher
            $objVMExtensionInfo | Add-Member NoteProperty 'vmExtensionType' $vmExtension.VirtualMachineExtensionType
            $objVMExtensionInfo | Add-Member NoteProperty 'vmExtensionName' $vmExtension.Name
            $objVMExtensionInfo | Add-Member NoteProperty 'vmExtensionVersion' $vmExtension.TypeHandlerVersion
            $objVMExtensionInfo | Add-Member NoteProperty 'vmExtensionProvisioningState' $vmExtension.ProvisioningState
            
            # The value of this property is a String.
            $objVMExtensionInfo | Add-Member NoteProperty 'vmExtensionSettings' $vmExtension.Settings.ToString()

            $vmExtensionInfo += $objVMExtensionInfo
        }
    }

    # Return the object containing the details of the security extensions of a VM.
    return $vmExtensionInfo
}


<#
    .DESCRIPTION 
    Helprer function to retrieve the Network Security Groups (NSGs) for Virtual Machines and Subnets.

    .PARAMETER $vmInstance
    The Virtual Machine's instance.

    .PARAMETER $subnet
    The subnet's instance.

    .OUTPUT
    The function returns an object which contains the Network Security Groups (NSGs) configuration for Virtual Machines and Subnets.
#>
function Get-CustomAzureRmNetworkSecurityGroups {
    Param (
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $vmInstance,
        [Microsoft.Azure.Commands.Network.Models.PSSubnet] $subnet
    )

    # Check if the cmdlet was called with input a VM instance.
    if ($vmInstance) {

        # Get the network interface IDs
        $vmNetworkInterfaceIds = $vmInstance.NetworkInterfaceIDs
        $vmNetworkInterfaceNetworkSecurityGroups = @()

        # The NSGs are associated with the VM's network interface (NIC).
        # Retrieve information about each VM's network interface.
        foreach ($vmNetworkInterfaceId in $vmNetworkInterfaceIds) {

            # Get the name of the network interface from the UNC.
            $vmNetworkInterfaceName = $vmNetworkInterfaceId | Split-Path -Leaf
            
            # Collect the configuration of the associated VM's network interface.
            $vmNetworkInterfaceConfig = Get-AzureRmNetworkInterface -Name $vmNetworkInterfaceName -ResourceGroupName $vmInstance.ResourceGroupName
        
            # The network interface is associated with a NSG if there's the NSG's Id in the NIC's configuration.
            # Check if there's is an NSG associated and retrieve the configuration.
            if ($vmNICNetworkSecurityGroupName = $vmNetworkInterfaceConfig.NetworkSecurityGroup.Id) {

                # Get the network interface NSG's name
                $vmNICNetworkSecurityGroupName =  $vmNICNetworkSecurityGroupName | Split-Path -Leaf

                # Collect the coonfiguration information for the NSG.
                $vmNICNetworkSecurityGroup = Get-AzureRmNetworkSecurityGroup -Name $vmNICNetworkSecurityGroupName -ResourceGroupName $vmInstance.ResourceGroupName

                # Create the object containing the Virtual Machine's Network Security Group details.
                $objVMNetworkInterfaceNetworkSecurityGroups = New-Object PSObject
                $objVMNetworkInterfaceNetworkSecurityGroups | Add-Member NoteProperty 'vmNICNetworkSecurityGroupName' $vmNICNetworkSecurityGroup.Name
                $objVMNetworkInterfaceNetworkSecurityGroups | Add-Member NoteProperty 'vmNICNetworkSecurityGroupCustomRules' $vmNICNetworkSecurityGroup.SecurityRules
                $objVMNetworkInterfaceNetworkSecurityGroups | Add-Member NoteProperty 'vmNICNetworkSecurityGroupDefaultRules' $vmNICNetworkSecurityGroup.DefaultSecurityRules
                       
                $vmNetworkInterfaceNetworkSecurityGroups += $objVMNetworkInterfaceNetworkSecurityGroups
            }
        }

        # Return the object for the configuration of the VM's NSGs.
        return $vmNetworkInterfaceNetworkSecurityGroups
        
    # Check if the cmdlet was called with input a Subnet instance.
    } elseif ($subnet) {
        # Check if the Subnet has a NSG associated with it.
        if ($subnet.NetworkSecurityGroup.Id) {

                # Get Subnet's NSG's name.
                $subnetNetworkSecurityGroupName =  $subnet.NetworkSecurityGroup.Id | Split-Path -Leaf

                # Get Subnet NSG Resource Group's name
                $subnetNetworkSecurityGroupResourceGroupName = ($subnet.NetworkSecurityGroup.Id).Split('/')[4]
                
                # Use the information gathered to retrieve the NSG configuration for the Subnet.
                $subnetNetworkSecurityGroup = Get-AzureRmNetworkSecurityGroup -Name $subnetNetworkSecurityGroupName -ResourceGroupName $subnetNetworkSecurityGroupResourceGroupName
                
                # Create the object containing the Subnet's Network Security Group details.
                $subnetNetworkSecurityGroups = New-Object PSObject
                $subnetNetworkSecurityGroups | Add-Member NoteProperty 'subnetNetworkSecurityGroupName' $subnetNetworkSecurityGroup.Name
                $subnetNetworkSecurityGroups | Add-Member NoteProperty 'subnetNetworkSecurityGroupCustomRules' $subnetNetworkSecurityGroup.SecurityRules
                $subnetNetworkSecurityGroups | Add-Member NoteProperty 'subnetNetworkSecurityGroupDefaultRules' $subnetNetworkSecurityGroup.DefaultSecurityRules        
            
        }
        # Return the object for the configuration of the Subnet's NSGs.
        return $subnetNetworkSecurityGroups
    }
}

<#
    .DESCRIPTION 
    Helprer function to retrieve the routing configuration (Route Tables) for Subnets.

    .PARAMETER $subnet
    The subnet's instance.

    .OUTPUT
    The function returns an object which contains the route table configuration for the Subnets.

    .NOTES
    Under development.
#>
function Get-CustomAzureRmRouteTable {
    Param (
        [Microsoft.Azure.Commands.Network.Models.PSSubnet] $subnet
    )

    # TODO: Check if you can have more route tables associated with the same subnet.
    if ($subnet.RouteTable.Id) {
        
        # Get subnet's route table.
        $subnetRouteTable = Get-AzureRmRouteTable -Id $subnet.RouteTable.Id

        # TODO: Otherwise, get subnet's route table (workaround as Id is not an accepted parameter.)
        $subnetRouteTableName = $subnet.RouteTable.Id | Split-Path -Leaf
        $subnetRouteTableNameResourceGroupName = ($subnet.RouteTable.Id).Split('/')[4]
        $subnetRouteTable = Get-AzureRmRouteTable -Name $subnetRouteTableName -ResourceGroupName $subnetRouteTableResourceGroupName
                
        # TODO: Populate the object to contain the details about the subnet.
        $objSubnetRouteTableInfoProperties = [ordered] @{
            subnetRouteTableName = $subnetRouteTableName
            subnetRouteTableConfig = $subnetRouteTable.Routes
        }

        # Create the object containing the Subnet's Route Table details.
        $objSubnetRouteTableInfo = New-Object -TypeName PSObject -Property $objSubnetRouteTableInfoProperties

    }
}

<#
    .DESCRIPTION 
    Helprer function to retrieve details and configuration for Azure gateways (VNet and Local Network gateways). The method is called from the
    Get-CustomAzureRmSubscriptionNetworkConfiguration helper function, to retrieve information about each Azure Gateway when one is discovered.

    .PARAMETER $virtualNetworkGatewayName
    The Virtual Network (VNet) Gateway's name.

    .PARAMETER $localNetworkGatewayName
    The Local Network Gateway's name.

    .PARAMETER $gatewayResourceGroupName
    The gateway's Resource Group name.

    .OUTPUT
    The function returns an object which contains information about the configuration and connections for either the VNet Gateway or the Local Network Gateway.
#>
function Get-CustomAzureRmGateway {
    Param (
        [String] $virtualNetworkGatewayName,
        [String] $localNetworkGatewayName,
        [String] $gatewayResourceGroupName
    )

    # Check if the cmdlet was called with input a VNet Gateway's name.
    if ($virtualNetworkGatewayName) {

        # Retrieve the instance for the given VNet Gateway.
        $virtualNetworkGatewayInstance = Get-AzureRmVirtualNetworkGateway -Name $virtualNetworkGatewayName -ResourceGroupName $gatewayResourceGroupName

        # Retrieve the gateway's network configuration.
        # The call is made to the custom cmdlet defined in this script.
        $virtualNetworkGatewayInstanceNetworkConfiguration = Get-CustomAzureRmNetworkConfiguration -gatewayInstance $virtualNetworkGatewayInstance

        # Retrieve the VNet Gateway connections for the resource group that the current VNet gateway belongs to.
        $virtualNetworkGatewayConnections = Get-AzureRmVirtualNetworkGatewayConnection -ResourceGroupName $gatewayResourceGroupName
        
        # Check whether there are any connections returned.
        if ($virtualNetworkGatewayConnections) {
            
            # Collect information about each Virtual Network Gateway connection with other VNET Gateways or Local Network Gateways.
            $virtualNetworkGatewayConnectionInfo = @()
            foreach ($virtualNetworkGatewayConnection in $virtualNetworkGatewayConnections) {
                # Check whether the connection type is Vnet2Vnet.
                # If this is the case, then it's probably a VNet Gateway to VNet Gateway connection.
                if ($virtualNetworkGatewayConnection.ConnectionType -eq 'Vnet2Vnet') {
                    $vnetGateway1 = $virtualNetworkGatewayConnection.VirtualNetworkGateway1.Id | Split-Path -Leaf
                    $vnetGateway2 = $virtualNetworkGatewayConnection.VirtualNetworkGateway2.Id | Split-Path -Leaf

                    # Get VNet connection's Pre-Shared Key (PSK)
                    # This is the key requireed for the authentication and encryption between the gateways.
                    # It is returned in clear text.
                    $virtualNetworkGatewayPSK = Get-AzureRmVirtualNetworkGatewayConnectionSharedKey -ResourceGroupName $gatewayResourceGroupName -Name $virtualNetworkGatewayConnection.Name
                    # Check whether the current VNet Gateway (when the function is called) is related to any of the VNet Gateway connections returned in the same Resource Group.
                    if ($virtualNetworkGatewayName -eq $vnetGateway1 -or $virtualNetworkGatewayName -eq $vnetGateway2) {
                        # Populate the VNet Gateway connection object with the connection information.
                        $objVirtualNetworkGatewayConnectionInfoProperties = [ordered] @{
                            virtualNetworkGatewayConnectionName = $virtualNetworkGatewayConnection.Name
                            virtualNetworkGatewayConnectionType = $virtualNetworkGatewayConnection.ConnectionType
                            virtualNetworkGatewayConnectionGateway1 = $vnetGateway1
                            virtualNetworkGatewayConnectionGateway2 = $vnetGateway2
                            virtualNetworkGatewayConnectionProvisioningState = $virtualNetworkGatewayConnection.ProvisioningState
                            virtualNetworkGatewayConnectionPSK = $virtualNetworkGatewayPSK
                        }
                    }
                # Check whether the connection type is IPSec.
                # If this is the case, then it's probably a VNet to Local Network Gateway connection.
                } elseif ($virtualNetworkGatewayConnection.ConnectionType -eq 'IPSec') {
                    # Check that the vnetGateway1 property of the connection has a value.
                    if ($virtualNetworkGatewayConnection.VirtualNetworkGateway1.Id) {
                        $vnetGateway1 = $virtualNetworkGatewayConnection.VirtualNetworkGateway1.Id | Split-Path -Leaf
                        # This function is called when a VNet Gateway has been discovered in a VNet.
                        # Check whether the vnetGateway1 property of the connection is the same as the current Vnet Gateway.
                        # This check is performed to discover at which property the name of the current VNet Gateway exists.
                        if ($virtualNetworkGatewayName -eq $vnetGateway1) {
                            # If the previous condition is true, get the name of the Local Network Gateway participating in the connection.
                            if ($localNetworkGateway1 = $virtualNetworkGatewayConnection.LocalNetworkGateway1.Id) {
                                $localNetworkGateway = $localNetworkGateway1 | Split-Path -Leaf
                            } elseif ($localNetworkGateway2 = $virtualNetworkGatewayConnection.LocalNetworkGateway2.Id) {
                                $localNetworkGateway = $localNetworkGateway2 | Split-Path -Leaf
                            } else {
                                $localNetworkGateway = $null
                            }
                        }
                    # Check that the vnetGateway2 property of the connection has a value.
                    } elseif ($virtualNetworkGatewayConnection.VirtualNetworkGateway2.Id) {
                        $vnetGateway2 = $virtualNetworkGatewayConnection.VirtualNetworkGateway2.Id | Split-Path -Leaf
                        # This function is called when a VNet Gateway has been discovered in a VNet.
                        # Check whether the vnetGateway2 of the connection is the same as the current vnetGateway.
                        # This check is performed to discover at which property the name of the current VNet Gateway exists.
                        if ($virtualNetworkGatewayName -eq $vnetGateway2) {
                            # If the previous condition is true, get the name of the Local Network Gateway participating in the connection.
                            if ($localNetworkGateway1 = $virtualNetworkGatewayConnection.LocalNetworkGateway1.Id) {
                                $localNetworkGateway = $localNetworkGateway1 | Split-Path -Leaf
                            } elseif ($localNetworkGateway2 = $virtualNetworkGatewayConnection.LocalNetworkGateway2.Id) {
                                $localNetworkGateway = $localNetworkGateway2 | Split-Path -Leaf
                            } else {
                                $localNetworkGateway = $null
                            }
                        }
                    }

                    # If a Local Network Gateway exists in the connection, get the information about the connection
                    # and populate the object.
                    if ($localNetworkGateway) {
                        $objVirtualNetworkGatewayConnectionInfoProperties = [ordered] @{
                            virtualNetworkGatewayConnectionName = $virtualNetworkGatewayConnection.Name
                            virtualNetworkGatewayConnectionType = $virtualNetworkGatewayConnection.ConnectionType
                            virtualNetworkGatewayConnectionGateway1 = $vnetGateway1
                            virtualNetworkGatewayConnectionGateway2 = $localNetworkGateway
                            virtualNetworkGatewayConnectionProvisioningState = $virtualNetworkGatewayConnection.ProvisioningState
                        }
                    }
                }

                $objVirtualNetworkGatewayConnectionInfo = New-Object -TypeName PSObject -Property $objVirtualNetworkGatewayConnectionInfoProperties
                $virtualNetworkGatewayConnectionInfo += $objVirtualNetworkGatewayConnectionInfo
            }
        }

        # Populate the object for the VNet Gateway configuration details.
        $objVirtualNetworkGatewayInstanceInfoProperties = [ordered] @{
            virtualNetworkGatewayName = $virtualNetworkGatewayInstance.Name
            virtualNetworkGatewayResourceGroupName = $virtualNetworkGatewayInstance.ResourceGroupName
            virtualNetworkGatewayLocation = $virtualNetworkGatewayInstance.Location
            itemType = 'Virtual Network Gateway'
            virtualNetworkGatewayNetworkConfiguration = $virtualNetworkGatewayInstanceNetworkConfiguration
            virtualNetworkGatewayType =$virtualNetworkGatewayInstance.GatewayType
            virtualNetworkGatewayBgp = $virtualNetworkGatewayInstance.EnableBgp 
        }

        # If there are any Gateway connections, add this information too.
        if ($virtualNetworkGatewayConnectionInfo) {
            $objVirtualNetworkGatewayInstanceInfoProperties.Add('virtualNetworkGatewayConnections', $objVirtualNetworkGatewayConnectionInfo)
        }
    
        $objVirtualNetworkGatewayInstanceInfo = New-Object -TypeName PSObject -Property $objVirtualNetworkGatewayInstanceInfoProperties
    
        return $objVirtualNetworkGatewayInstanceInfo
    # Check if the cmdlet was called with input a Local Network Gateway's name.
    } elseif ($localNetworkGatewayName) {
        # Retrieve the instance for the given Local Network Gateway.
         $localNetworkGatewayInstance = Get-AzureRmLocalNetworkGateway -Name $localNetworkGatewayName -ResourceGroupName $gatewayResourceGroupName -WarningAction SilentlyContinue
         
         # Populate the object for the Local Network Gateway network configuration details.
         $objLocalNetworkGatewayInstanceNetworkConfigurationProperties = @{
            localNetworkGatewayPublicIpAddress = $localNetworkGatewayInstance.GatewayIpAddress
            localNetworkGatewayBgp = $localNetworkGatewayInstance.BgpSettings.BgpPeeringAddress
            localNetworkGatewayAddressSpace = $localNetworkGatewayInstance.LocalNetworkAddressSpace.AddressPrefixes
         }

         $objLocalNetworkGatewayInstanceNetworkConfiguration = New-Object -TypeName PSObject -Property $objLocalNetworkGatewayInstanceNetworkConfigurationProperties

         # Populate the object for the main Local Network Gateway configuration details.
         $objLocalNetworkGatewayInstanceInfoProperties = [ordered] @{
            localNetworkGatewayName = $localNetworkGatewayInstance.Name
            localNetworkGatewayResourceGroupName = $localNetworkGatewayInstance.ResourceGroupName
            localNetworkGatewayLocation = $localNetworkGatewayInstance.Location
            itemType = 'Local Network Gateway'
            localNetworkGatewayNetworkConfiguration = $objLocalNetworkGatewayInstanceNetworkConfiguration
        }

        $objLocalNetworkGatewayInstanceInfo = New-Object -TypeName PSObject -Property $objLocalNetworkGatewayInstanceInfoProperties

        return $objLocalNetworkGatewayInstanceInfo
    }

}

<#
    .DESCRIPTION
    Helprer function to retrieve details and configuration for the Azure Web Applications (App Services). 
    The method is also called from the Get-CustomAzureRmSubscriptionNetworkConfiguration helper function.

    .PARAMETER $webApp
    The Azure Web Application instance.

    .PARAMETER $resourceGroupName
    The Azure Web Application's Resource Group name.

    .OUTPUT
    The function returns an object which contains information about the configuration of an Azure Web Application.
#>
function Get-CustomAzureRmWebApp {
    Param (
        [System.Object] $webApp,
        [String] $resourceGroupName
    )

    # Gets a Web Application's certificate SSL binding.
    $webAppSSLBinding = Get-AzureRmWebAppSSLBinding -WebApp $webApp
    
    # Retrieve Web Application's publishing profile for website and ftp in all available formats.
    # Contains deployment username and password, connection strings for SQL and MySQL DBMS.
    # Requires elevated privileges. Not possible to retrieve with 'Reader' role.
    Try {
        if ($currentUserRole -notlike "*Reader*") {
            Get-AzureRMWebAppPublishingProfile -Name $webApp.Name -ResourceGroupName $resourceGroupName -Format WebDeploy -OutputFile "$($webApp.Name.ToString())-publishingprofile-webdeploy.xml" | Out-Null
            Get-AzureRMWebAppPublishingProfile -Name $webApp.Name -ResourceGroupName $resourceGroupName -Format FileZilla3 -OutputFile "$($webApp.Name.ToString())-publishingprofile-filezilla3.xml" | Out-Null
            Get-AzureRMWebAppPublishingProfile -Name $webApp.Name -ResourceGroupName $resourceGroupName -Format Ftp -OutputFile "$($webApp.Name.ToString())-publishingprofile-ftp.xml" | Out-Null
        } else {
            Write-Host "[!] Unauthorised operation: Retrieve WebAppPublishingProfle - Reason: Insufficient user privileges"
        }
    }
    Catch [CloudException] {
        Write-Host '[!] Get-AzureRMWebAppPublishingProfile operation not available for this subscription.'
    }

    # Initialise and populate the object to contain the Web Application's information.
    $objWebAppInfo = New-Object PSObject
    $objWebAppInfo | Add-Member NoteProperty 'webAppName' $webApp.Name
    $objWebAppInfo | Add-Member NoteProperty 'webAppResourceGroupName' $resourceGroupName
    $objWebAppInfo | Add-Member NoteProperty 'webAppSiteName' $webApp.SiteName
    $objWebAppInfo | Add-Member NoteProperty 'webAppLocation' $webApp.Location
    $objWebAppInfo | Add-Member NoteProperty 'webAppState' $webApp.State
    $objWebAppInfo | Add-Member NoteProperty 'webAppHostNames' $webApp.HostNames
    $objWebAppInfo | Add-Member NoteProperty 'webAppHostNamesSslStates' $webApp.HostNamesSslStates
    $objWebAppInfo | Add-Member NoteProperty 'webAppOutboundIpAddresses' $webApp.OutboundIpAddresses

    # In case there is an SSL certificate binding, 
    # retrieve the Web Application's certificate details using the certificate's thumbprint.
    if ($webAppSSLBinding) { 
        $webAppSSLCertificate = Get-AzureRmWebAppCertificate -Thumbprint $webAppSSLBinding.Thumbprint

        $objWebAppSSLCertificateInfo = New-Object PSObject
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateName' $webAppSSLCertificate.Name
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateFriendlyName' $webAppSSLCertificate.FriendlyName
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateSubjectName' $webAppSSLCertificate.SubjectName
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateIssuer' $webAppSSLCertificate.Issuer
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateIssueDate' $webAppSSLCertificate.IssueDate
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateExpirationDate' $webAppSSLCertificate.ExpirationDate
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateThumbprint' $webAppSSLCertificate.Thumbprint
        $objWebAppSSLCertificateInfo | Add-Member NoteProperty 'webAppSSLCertificateId' $webAppSSLCertificate.Id

        $objWebAppInfo | Add-Member NoteProperty 'webAppSSLCertificate' $objWebAppSSLCertificateInfo
    }

    return $objWebAppInfo
}

<#
    .DESCRIPTION
    Helprer function to retrieve the configuration of the Azure Key Vault. 

    .PARAMETER $keyVaultInstanceName
    The Azure Key Vault's name.

    .PARAMETER $keyVaultResourceGroupName
    The Azure Key Vault's Resource Group name.

    .OUTPUT
    The function returns an object which contains information about the configuration of an Azure Key Vault.
#>
function Get-CustomAzureRmKeyVault {
    Param (
        [String] $keyVaultInstanceName,
        [String] $keyVaultResourceGroupName
    )
    
    Write-Host "[+] Retrieve Key Vault's $keyVaultResourceGroupName - $($keyVaultInstanceName) configuration." 

    # Retrieve the Azure Key Vault instance referenced by the parameters provided as input.
    $keyVaultInstance = Get-AzureRmKeyVault -VaultName $keyVaultInstanceName -ResourceGroupName $keyVaultResourceGroupName -WarningAction SilentlyContinue

    # Populate the object to return with Azure Key Vault's details.
    $objKeyVaultInfoProperties = [ordered] @{
        keyVaultName = $keyVaultInstance.VaultName
        keyVaultResourceGroupName = $keyVaultInstance.ResourceGroupName
        keyVaultLocation = $keyVaultInstance.Location
        keyVaultSKU = $keyVaultInstance.Sku
        keyVaultURI = $keyVaultInstance.VaultUri
        keyVaultEnabledForDeployment = $keyVaultInstance.EnabledForDeployment
        keyVaultEnabledForTemplateDeployment = $keyVaultInstance.EnabledForTemplateDeployment
        keyVaultEnabledForDiskEncryption = $keyVaultInstance.EnabledForDiskEncryption
        keyVaultAccessPolicies = $keyVaultInstance.AccessPolicies
    }

    # Retrieve the instances of the Keys that are contained in the Azure Key Vault.
    Try {
        $keyVaultKeys = Get-AzureKeyVaultKey -VaultName $keyVaultInstance.VaultName -WarningAction SilentlyContinue
    }
    Catch [Microsoft.Azure.KeyVault.KeyVaultClientException] {
        Write-Host '[!] Get-AzureKeyVaultKey operation not available for this subscription.'
        $keyVaultKeys = $null
        $ErrorActionPreference = ‘Continue’
    }

    # In case that the Azure Key Vault contains Keys,
    # Retrieve the information for each of the Azure Key Vault Keys.
    if ($keyVaultKeys) {
        $keyVaultKeysInfo = @()
        foreach ($keyVaultKey in $keyVaultKeys) {
            
            $keyInstance = Get-AzureKeyVaultKey -Name $keyVaultKey.Name -VaultName $keyVaultKey.VaultName -WarningAction SilentlyContinue

            # Populate an object which contains the information for the Key Vault Keys.
            $objKeyVaultKeyInfoProperties = [ordered] @{
                keyName = $keyInstance.Name
                keyKeyVaultName = $keyInstance.VaultName
                keyEnabled = $keyInstance.Attributes.Enabled
                keyURI = $keyInstance.Key.Kid
                keyType = $keyInstance.Key.Kty
                keyOperations = $keyInstance.Key.KeyOps
            
            }

            # Get the expiration date of the Azure Key Vault Key, if it's set.
            if ($keyInstance.Attributes.Expires) {
                $objKeyVaultKeyInfoProperties.Add('keyExpiryDate', $keyInstance.Attributes.Expires)
            } else {
                $objKeyVaultKeyInfoProperties.Add('keyExpiryDate', 'Not Defined')
            }

            $keyVaultKeysInfo += $objKeyVaultKeyInfoProperties
        }

        $objKeyVaultInfoProperties.Add('keyVaultKeys', $keyVaultKeysInfo)
    }

    # Retrieve the instances of the Secrets that are contained in the Azure Key Vault.
    Try {
        $keyVaultSecrets = Get-AzureKeyVaultSecret -VaultName $keyVault.VaultName -WarningAction SilentlyContinue
    }
    Catch [Microsoft.Azure.KeyVault.KeyVaultClientException] {
        Write-Host '[!] Get-AzureKeyVaultKey operation not available for this subscription.'
        $keyVaultKeys = $null
        $ErrorActionPreference = ‘Continue’
    }

    # In case that the Azure Key Vault contains Secrets,
    # Retrieve the information for each of the Azure Key Vault Secrets.
    if ($keyVaultSecrets) {
        $keyVaultSecretsInfo = @()
        foreach ($keyVaultSecret in $keyVaultSecrets) {
            
            $secretInstance = Get-AzureKeyVaultSecret -Name $keyVaultSecret.Name -VaultName $keyVaultSecret.VaultName -WarningAction SilentlyContinue

            # Populate an object which contains the information for the Key Vault Secrets.
            $objKeyVaultSecretInfoProperties = [ordered] @{
                secretName = $secretInstance.Name
                secretKeyVaultName = $secretInstance.VaultName
                secretEnabled = $secretInstance.Attributes.Enabled
                secretURI = $secretInstance.Id
            }

            # Get the expiration date of the Azure Key Vault Secret, if it's set.
            if ($secretInstance.Attributes.Expires) {
                $objKeyVaultSecretInfoProperties.Add('secretExpiryDate', $secretInstance.Attributes.Expires)
            } else {
                $objKeyVaultSecretInfoProperties.Add('secretExpiryDate', 'Not Defined')
            }

            $keyVaultSecretsInfo += $objKeyVaultSecretInfoProperties
        }

        $objKeyVaultInfoProperties.Add('keyVaultSecrets', $keyVaultSecretsInfo)
    }

    # Create the object containing Azure Key Vault's details.
    $objKeyVaultInfo = New-Object -TypeName PSObject -Property $objKeyVaultInfoProperties

    # Return the object to the function call.
    return $objKeyVaultInfo

}

<#
    .DESCRIPTION
    Helprer function to retrieve information for the network configuration of the provided Azure subscription.
    The function does not accept any arguments. It retrieves the requested information from the selected (current) subscription.
    Information that is returned in the object follows the hierarchy: 
    1. VNets -> Subnets -> VMs and VNET Gateways
    2. Azure SQL Server -> Azure SQL Database
    3. Web Applications
    4. Local Gateways  

    .OUTPUT
    The function returns an object which contains information about the network configuration and some of the resources of the Azure subscription.
#>
function Get-CustomAzureRmSubscriptionNetworkConfiguration {

    Write-Host "[+] Retrieve Subscription's network configuration."

    # Get the Virtual Network (VNet) instances in the subscription.
    $subscriptionVNETs = Get-AzureRmVirtualNetwork

    # If there are any VNets in the subscription, iterate through them to retrieve all the relevant information.
    if ($subscriptionVNETs) {
        
        # Initialise an array to contain all the VNets in the subscription.
        $subscriptionVNETInfo = @()
        foreach ($subscriptionVNET in $subscriptionVNETs) {
            
            # Populate an object to include the information for each VNet in the subscription.
            $objSubscriptionVNETInfo = New-Object PSObject
            $objSubscriptionVNETInfo | Add-Member NoteProperty 'vnetName' $subscriptionVNET.Name
            $objSubscriptionVNETInfo | Add-Member NoteProperty 'vnetResourceGroup' $subscriptionVNET.ResourceGroupName
            $objSubscriptionVNETInfo | Add-Member NoteProperty 'vnetLocation' $subscriptionVNET.Location

            # Return all the address spaces of the VNet.
            $objSubscriptionVNETInfo | Add-Member NoteProperty 'vnetAddressSpaces' $subscriptionVNET.AddressSpace
            
            # If the VNet contains subnets, retrieve information about each subnet recursively.
            if ($subscriptionVNET.Subnets.Count) {
                
                # Initialise an array to return all the subnets' info.                
                $subscriptionVNETSubnetInfo = @()
                
                # Retrieve the configuration for each subnet (Virtual Machines, IP addresses, etc)
                foreach ($subscriptionVNETSubnet in $subscriptionVNET.Subnets) {

                    $objSubscriptionVNETSubnetInfo = New-Object PSObject
                    $objSubscriptionVNETSubnetInfo | Add-Member NoteProperty 'subnetName' $subscriptionVNETSubnet.Name
                    $objSubscriptionVNETSubnetInfo | Add-Member NoteProperty 'subnetAddressSpace' $subscriptionVNETSubnet.AddressPrefix

                    # If the subnet has multiple network configurations, iterate through them and retrieve the information.
                    if ($subscriptionVNETSubnet.IpConfigurations.Count) {
                        
                        # Initialise an array to contain info for each subnet, 
                        $subscriptionVNETSubnetItemInfo = @()
                        foreach ($subscriptionVNETSubnetIpConfiguration in $subscriptionVNETSubnet.IpConfigurations) {
                            
                            
                            # Check if the subnet's name is not "GatewaySubnet" i.e. it is a gateway subnet ;) and if true, 
                            # perform operations to retrieve information for a VM.
                            if ($subscriptionVNETSubnet.Name -ne 'GatewaySubnet') {
                                
                                # Get the subnet's network interface name from IpConfiguration Id
                                $networkInterfaceName = ($subscriptionVNETSubnetIpConfiguration.Id).Split('/')[-3]

                                # Get resource group; A network interface can belong to a different resource group
                                # than the Virtual Network or the Virtual Machine attached to.
                                $networkInterfaceResourceGroupName = ($subscriptionVNETSubnetIpConfiguration.Id).Split('/')[4]
                                
                                # Retrieve the configuration associated with the retrieved Network Interface.
                                $networkInterfaceConfig = Get-AzureRmNetworkInterface -Name $networkInterfaceName -ResourceGroupName $networkInterfaceResourceGroupName
             
                                # Check that the Network Interface is attached to a VM.
                                if ($networkInterfaceConfig.VirtualMachine -ne $null) {
                                    $vmName = $networkInterfaceConfig.VirtualMachine.Id | Split-Path -Leaf

                                    # Collect information about the VM (using the custom function Get-CustomAzureRmWindowsVM).
                                    $objSubscriptionVNETSubnetItemInfo = Get-CustomAzureRmWindowsVM -vmInstanceName $vmName -vmInstanceResourceGroupName $networkInterfaceResourceGroupName
                         
                               }
                            # If the subnet's name is "GatewaySubnet" perform the following operations to retrieve information for the VNet Gateway subnet.
                            } else {
                                
                                # Subnet must be in the same resource group as the VNet. 
                                # Get the subnet's name.
                                $gatewaySubnetName = ($subscriptionVNETSubnetIpConfiguration.Id).Split('/')[-3]
                                
                                # Retrieve information for the VNet Gateway.
                                $gatewaySubnetVirtualNetworkGateway = Get-AzureRmVirtualNetworkGateway -Name $gatewaySubnetName -ResourceGroupName $subscriptionVNET.ResourceGroupName

                                # Retrieve information about the configuration of the VNet Gateway (using custom function Get-CustomAzureRmGateway).
                                $objSubscriptionVNETSubnetItemInfo = Get-CustomAzureRmGateway -virtualNetworkGatewayName $gatewaySubnetVirtualNetworkGateway.Name -gatewayResourceGroup $gatewaySubnetVirtualNetworkGateway.ResourceGroupName  
                                                                
                            }

                            # If information about a subnet item (VM or VNet Gateway) was retrieved, then populate the subnet item's array.
                            if ($objSubscriptionVNETSubnetItemInfo) {
                                $subscriptionVNETSubnetItemInfo += $objSubscriptionVNETSubnetItemInfo
                                Remove-Variable -Name objSubscriptionVNETSubnetItemInfo
                            }
                        }
                        
                        # If information about subnet items (VM or VNet Gateway) was retrieved, then populate the subnet's object.
                        if ($subscriptionVNETSubnetItemInfo) {                          
                            $objSubscriptionVNETSubnetInfo | Add-Member NoteProperty 'subnetItems' $subscriptionVNETSubnetItemInfo
                            Remove-Variable -Name subscriptionVNETSubnetItemInfo
                        }
                                
                    } else {
                        Write-Host "[*] No items were retrieved for Subnet $($subscriptionVNETSubnet.Name) in Virtual Network $($subscriptionVNET.Name)."
                    }

                    # Retrieve subnet's Network Security Groups (NSGs) (using the custom function Get-CustomAzureRmNetworkSecurityGroups).
                    # Then, append them in the subnet's object.
                    $subscriptionVNETSubnetNetworkSecurityGroups = Get-CustomAzureRmNetworkSecurityGroups -subnet $subscriptionVNETSubnet
                    $objSubscriptionVNETSubnetInfo | Add-Member NoteProperty 'subnetNetworkSecurityGroups' $subscriptionVNETSubnetNetworkSecurityGroups

                    # TODO: Retrieve subnet's route table.
                    #$subscriptionVNETSubnetRouteTable = Get-CustomAzureRmRouteTable -subnet $subscriptionVNETSubnet
                    $objSubscriptionVNETSubnetInfo | Add-Member NoteProperty 'subnetRouteTable' $subscriptionVNETSubnetRouteTable

                    $subscriptionVNETSubnetInfo += $objSubscriptionVNETSubnetInfo  
                }

                # Append the object containing the subnet's information to the VNet object.
                $objSubscriptionVNETInfo | Add-Member NoteProperty 'vnetSubnets' $subscriptionVNETSubnetInfo
                    
            }
     
            $subscriptionVNETInfo += $objSubscriptionVNETInfo

       }

      
       return $subscriptionVNETInfo
   }

   else {
        Write-Host "No Virtual Networks were configured for $subscription.SubscriptionName ($($subscription.SubscriptionId))."

        return $null
   }
}

