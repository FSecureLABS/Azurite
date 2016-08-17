# Azurite - Azurite Explorer and Azurite Visualizer

Auditing Cloud services has become an essential task and significant effort is required to assess the security of the available resources.

_Azurite_ was developed to assist penetration testers and auditors during the enumeration and reconnaisance activities within the Microsof Azure public Cloud environment. It consists of two helper scripts: Azurite Explorer and Azurite Visualizer. The scripts are used to collect, passively, verbose information of the main components within a deployment to be reviewed offline, and visulise the assosiation between the resources using an interactive representation. One of the main features of the visual representation is to provide a quick way to identify insecure Network Security Groups (NSGs) in a subnet or Virtual Machine configuration.

# Quick Start Guide

## Pre-requisites

* Download and install the Azure PowerShell Cmdlets ([How to install and configure Azure PowerShell](https://azure.microsoft.com/en-gb/documentation/articles/powershell-install-configure/)).
* Download and install Python 2.7.
* Download and install Firefox.
* Clone the repository:
```
git clone https://github.com/mwrlabs/Azurite.git
```

* Get the submodule for netjsongraph.js:
```
git submodule init
git submodule update
```

## Azurite Explorer & Azurite Visualizer

### Azurite Explorer

_Azurite Explorer_ implements functionality to retrieve the configuration of Azure-hosted deployments and export the output in structured JSON objects for offline review. Currently, Azurite Explorer supports only the resources deployed with the Azure Resource Manager deployment model. 

Import the AzureRM module:

    # PS> Import-Module AzureRM

Import Azurite Explorer module in PowerShell and retrieve the information for an Azure subscription. 

    # PS> Import-Module AzuriteExplorer.ps1
    # PS> Review-CustomAzureRmSubscription

Provide credentials for the Azure subscription under review. The user should belong to one of the following roles:
* Owner
* Contributor
* Reader

It is also required to know the ID of the target Azure subscription.

Azurite Explorer's output will be saved in the following files:
* azure-vms\_&lt;subscription-id&gt;\_&lt;user-email&gt;.json
* azure-websites\_&lt;subscription-id&gt;\_&lt;user-email&gt;.json
* azure-sqlservers\_&lt;subscription-id&gt;\_&lt;user-email&gt;.json
* azure-key-vaults\_&lt;subscription-id&gt;\_&lt;user-email&gt;.json
* azure-subscription\_&lt;subscription-id&gt;\_&lt;user-email&gt;.json

### Azurite Visualizer

_Azurite Visualizer_ will assist assessor to get a better understanding of the Azure deployment by visualizing the output exported by Azurite Explorer. It also allows to interactively collect information for the resources and it highlights any weak Network Security Groups (NSGs) associated with Subnets and Virtual Machines.

Retrieve the exported file azure-subscription\_&lt;subscription-id&gt;\_&lt;user-email&gt;.json from Azurite Explorer and use it as input to _AzuriteVisualiser.py_.

    # python AzuriteVisualizer.py azure-subscription_<subscription-id>_<user-email>.json

The aforementioned operation will generate the file _azure-subscription-nodes.json_ which contains the formatted JSON object. Finally, open _AzuriteVisualizer.html_ in Firefox to view the graph representation of the Azure subscription's topology of the resources.

# Remarks

The Azurite Visualizer Graph is based on the [netjsongraph.js](https://github.com/interop-dev/netjsongraph.js) and currently supports only the Firefox browser.

Development of Azurite is ongoing, and this first release provides support for mainstream Azure components, including:

* Virtual Networks (VNets)
* Subnets
* Virtual Network Gateways
* Azure SQL Servers
* Azure SQL Databases
* Azure Websites
* Azure Key Vaults

# Contact

Feel free to submit issues or ping me on Twitter - [@Lgrec0](https://twitter.com/Lgrec0)
