if (!(Get-Module powershell-yaml -ListAvailable)) {
    Install-Module -Name powershell-yaml
}
Import-Module powershell-yaml


$provider_vars = @{
    client_id               = ""
    client_secret           = ""
    subscription_id         = ""
    tenant_id               = ""

    env_client_id           = ""
    env_client_secret       = ""

    env_subscription_id     = ""
    env_agent_client_id     = ""
    env_agent_client_secret = ""
    env_tenant_id           = ""
}

<#
.SYNOPSIS
# Initializes terraform with local storage

.DESCRIPTION
Long description

.EXAMPLE
An example

.NOTES
General notes
#>
function Initialize-TerraformLocal {
    param(
        [Switch][boolean]$reconfigure,
        [Switch][boolean]$migrate
    )

    $provider_override = @"
        terraform {
            backend "local" {}
        }      
"@
    $provider_override | out-file "provider_override.tf" -encoding utf8


    $provider_vars | Out-TerraformVars "_provider.auto.tfvars"

    $a = @()
    if ($reconfigure) { $a += @("--reconfigure") }
    if ($migrate) { $a += @("--migrate-state") }
    
    terraform init $a
}

function Initialize-TerraformBlob {
    param(
        [Parameter(Mandatory = $true)]
        $envName,
        # i.e.: mystate.blob.core.windows.net/tfstates/statefile
        $statefile,
        [Switch][boolean]$reconfigure,
        [Switch][boolean]$upgrade,
        [Switch][boolean]$migrate,
        [switch][boolean]$list,
        [switch][boolean]$newState
    )

    $targetSub = $null
    $config = Import-EnvConfig
    $envs = $config.envs
    
    $envData = $envs[$envName]
    if (!$envData) {
        $envData = @{}
    }
    if ($statefile) {
        $envData.statefile = $statefile
    }
    
    if (!$envData.statefile) {
        Write-Warning "no statefile given and no env data for environment '$envName' found in .environments.yaml."
        Write-Warning "You can use '-statefile' paramater to provide statefile path, i.e.: '-statefile mystate.blob.core.windows.net/tfstates/foobar-infra-ci'"
        if ($envs -and $envs.keys) {
            write-host "Available environments:"
            $envs.keys | write-host
        }
        return
    }
    
    $sub = select-subscription $envData
    $backendConfig = Get-BackendConfig -statefile $envData.statefile -sub $sub
    $backendConfig | Out-TerraformVars "_backend.tfvars"

    $provider_override = @"
        terraform {
            backend "azurerm" {}
        }      
"@
    $provider_override | out-file "provider_override.tf" -encoding utf8


    $a = @()
    if ($reconfigure) { $a += @("--reconfigure") }
    if ($upgrade) { $a += @("--upgrade") }
    if ($migrate) { $a += @("--migrate-state") }

    write-verbose "terraform init --backend-config `"_backend.tfvars`" $a" -Verbose
    terraform init --backend-config "_backend.tfvars" $a

    if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }


    $provider_vars.subscription_id = $sub.id
    $provider_vars.env_subscription_id = $sub.id
    # other azurerrm provider connection variables to empty - terraform will try to use az CLI
    $provider_vars | Out-TerraformVars "_provider.auto.tfvars"
    

    $envvars = Get-ConfigVars -config $config -envdata $envData
    $envvars | Out-TerraformVars "_env.auto.tfvars"

    $config.envs.$envName = $envData

    Export-EnvConfig $config

    Test-State $statefile -newState:$newState
}
<#
.SYNOPSIS
Initializes terraform with az storage

.PARAMETER name
The name of release pipeline that the state was created by. I.e. "paylink-infra"

.PARAMETER key
key under which state is stored in azure storage account. Most probably in the format "{releasename}-{env}" (i.e. paylink-infra-ci)

.PARAMETER releaseName
name of release pipeline to get settings from. The script will try to determine 'key' parameter from the release

.PARAMETER env
Environment to use. This will determine the storage account name in azure and blob key.

.PARAMETER organization

.PARAMETER project

.EXAMPLE
az login
az account set --subscription DEVTEST-EU1
Initialize-TerraformAzure -name paylink-infra -env ci    
terraform show

.NOTES
This script uses az CLI to interact with azure.
You have to be logged in with az CLI and have correct subscription selected.
#>
function Initialize-TerraformAzure {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "key")]
        [Parameter(Mandatory = $true, ParameterSetName = "statefile")]
        [Parameter(Mandatory = $true, ParameterSetName = "env", Position = 0)]
        [ArgumentCompleter(
            {
                param($Command, $Parameter, $WordToComplete, $CommandAst, $FakeBoundParams)

                $envs = (Import-EnvConfig).envs
                
                return $envs.Keys
            }
        )]
        $env,
        [Parameter(Mandatory = $true, ParameterSetName = "key")]
        $key,
        [Parameter(Mandatory = $false, ParameterSetName = "key")]
        $storageAccountName = $null,
        [Parameter(Mandatory = $true, ParameterSetName = "statefile")]
        $statefile = $null,
        
        [Switch][boolean]$reconfigure,
        [Switch][boolean]$upgrade,
        [Switch][boolean]$migrate,
        [switch][boolean]$newState,
        [switch][boolean]$list
    )

    if ($key) {
        if (!$key.Contains($env)) {
            write-warning "key '$key' does not contains environment name '$env'. Are you sure this is what you wanted?"
        }
        # configure azurerm backend to use the same storage as pipelines
        if ($storageAccountName -ne $null) {
            $accountName = $storageAccountName
        } elseif ($env:TF_STORAGE_ACCOUNT_NAME) {
            $accountName = $env:TF_STORAGE_ACCOUNT_NAME
        } else {
            Write-Warning "No storage account name provided. Set -storageAccountName or $env:TF_STORAGE_ACCOUNT_NAME to override."
            throw "Storage account name must be provided via -storageAccountName or TF_STORAGE_ACCOUNT_NAME environment variable."
        }

        $containerName = "tfstates"
        $statefile = "$accountName.blob.core.windows.net/$containerName/$key"
    }

    Initialize-TerraformBlob -envName:$env -statefile:$statefile -newState:$newState -reconfigure:$reconfigure -upgrade:$upgrade -migrate:$migrate -list:$list

    Write-Warning "Remember to set `$env:AZDO_PERSONAL_ACCESS_TOKEN variable!"
}

function Set-AzurePAT($pat) {
    Set-EnvVar -user AZDO_PERSONAL_ACCESS_TOKEN $pat
    Set-EnvVar -user TF_VAR_DEVOPS_PAT $pat
}

function Test-State ($statefile, [switch][bool]$newState) {
    $state = terraform show -no-color | out-string
    if (!$newState -and ([string]::IsNullOrWhitespace($state) -or $state.Trim() -eq "No state.")) { 
        throw "terraform state at '$statefile' is empty. Make sure you used the right name/env/key combination."
    }
}

function Export-EnvConfig($config) {
    $filename = ".environments.yaml"
    $config | ConvertTo-Yaml | Out-File $filename
}

function Import-EnvConfig {
    $filename = ".environments.yaml"
    $config = @{}
    if ((Test-Path $filename)) {
        $config = get-content $filename | ConvertFrom-Yaml -Ordered
    }
    if (!$config) {
        $config = @{}
    }
    if ($config.envs) {
        # new format
        return $config
    }
    else {
        # old format - wrap it
        return @{ envs = $config }
    }
}


function Get-BackendConfig($statefile, $sub) {
    if (!($statefile -match "(?<account>.*).blob.core.windows.net/(?<container>.*)/(?<blob>.*)")) {
        throw "only azurerm state files are supported, in the format: '{account}.blob.core.windows.net/{container}/{blob}'"
    }

    $accountName = $matches["account"]
    $containerName = $matches["container"]
    $key = $matches["blob"]

    Write-Verbose "looking for statefile container: $statefile" -verbose

    $accountInfo = az storage account list --query "[?name=='$($accountName)']" | out-string | ConvertFrom-Json
    if (!$accountInfo) {
        throw "account '$accountName' not found in subscription '$($sub.name)'. You can change current subscription with 'az account set --subscription <name>'"
    }
    $resourceGroup = $accountInfo[0].resourceGroup
    
    $accessKeys = az storage account keys list --account-name $accountName | convertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "failed to retrieve account keys for account '$accountName' in rg '$resourceGroup'"
    }
    write-verbose "using storage container '$resourceGroup/$accountName/$containerName/$key'" -Verbose

    $foundBlobs = az storage blob list --account-key $accessKeys[0].value --account-name $accountName --container-name $containerName --prefix $key | out-string | convertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "FAILED CMD: az storage blob list"
    }
    if (!$foundBlobs -and !$newState) {
        throw "blob '$resourceGroup/$accountName/$containerName/$key' not found. If you're trying to use an existing state file, you probobly got the path to statefile wrong. If you want to create a new one, use -newState"
    } 

    if ($list) {
        $foundBlobs | % { [PSCustomObject]@{
                Name         = $_.Name
                Size         = $_.Properties.contentLength
                LastModified = $_.Properties.lastModified
            } }
        return $null
    }
    
    write-verbose "found matching blobs:" -verbose
    $foundBlobs | % { write-verbose $_.name -verbose }

    
    return @{
        resource_group_name  = "$resourceGroup"
        storage_account_name = "$accountName"
        container_name       = "$containerName"

        # this has to be unique for each pipeline and each env
        key                  = "$key"

        # get storage access key from container in AZ portal
        access_key           = "$($accessKeys[0].value)"
    }
}

function Select-Subscription($envdata) {
    $targetSub = $envData.subscription
    
    if ($targetSub) {
        write-verbose "switching to subscription '$targetSub'" -Verbose
        az account set -s $targetSub
    }
    else {
        Write-Warning "no subscription specified, using current one from az CLI"
    }
    $sub = az account show | out-string | ConvertFrom-Json

    $envData.subscription = $sub.name

    Write-Verbose "using subscription '$($sub.name)'" -Verbose

    return $sub
}

function Get-ConfigVars($config, $envdata) {
    $envvars = @{
        env_environment_name = "$($env)"
        environment          = "$($env)"
        tf_environment_name  = "$($env)"
        aks_domain_infix     = "$($env.Split("_")[-1])"
        env_location         = "westeurope"
    }

    if ($config.vars) {
        foreach ($kvp in $config.vars.GetEnumerator()) {
            $envvars[$kvp.key] = $kvp.value
        }
    }
    if ($envData.vars) {
        foreach ($kvp in $envData.vars.GetEnumerator()) {
            $envvars[$kvp.key] = $kvp.value
        }
    }

    if ($config.vars) {
        foreach ($kvp in $config.vars.GetEnumerator()) {
            $envvars[$kvp.key] = $kvp.value
        }
    }
    return $envvars
}

function Out-TerraformVars(    
    [Parameter(Mandatory = $true)]
    $file, 
    [Parameter(ValueFromPipeline, Mandatory = $true)] $dictionary, 
    [switch][bool] $append) {
    if (!$append -and (test-path $file)) {
        rm $file
    }
    $dictionary.GetEnumerator() | % {
        
        "$($_.key)=`"$($_.value)`"" | out-file $file -encoding utf8 -Append
    }
}

function Generate-TerraformVars() {
    $result = terraform plan -input=false -no-color 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "terraform plan passed, all vars seem OK"
    }

    $errors = ParseErrors $result
    
    $vars = @{}
    foreach ($err in $errors) {
        if ($err.message -eq "No value for required variable" -and $err.variableName) {
            $vars[$err.variableName] = ""
        }
    }
    $vars | Out-TerraformVars "_vars.auto.tfvars"
}

function ParseErrors([string[]] $terraformOutput) {
    $inside = $false
    $result = @()
    $err = $null
    foreach ($line in $terraformOutput) {
        if ($line -match "Error:\s*(.*)$") {
            $err = @{
                message = $matches[1]
            }
            $result += $err
        }

        if ($err -ne $null -and $err.message -eq "No value for required variable") {
            if ($line -match "[0-9]+: variable `"(.*?)`"") {
                $err.variableName = $matches[1]
                $err = $null
            }
        }
    }

    return $result
}