
<#
.SYNOPSIS
Imports a module (similar to Import-Module), but will try to install it if it's not available 

.DESCRIPTION
Imports a module (similar to Import-Module), but will try to install it if it's not available 

Combines checking for module, installing it and importing into one handy command. 
Can also update a module and reload it if a newer version is requested.


.PARAMETER modules
List of modules to load.

.PARAMETER version
Require specific version of the package. Can be a SemVer number, or 'latest'.

If a newer version is requested (than the one that's available on the system), the module will be updated and reloaded.

.PARAMETER package
Name of the package that contains the requested module (i.e. name of choco package to install)

.PARAMETER package
Forces reload of the module, even if an appropriate version is already loaded. 
If the module needs updating (i.e. because requested version is higher than the loaded one), 
then the module will be reloaded irrespectively of this flag.

.PARAMETER source
The source to get the package from. 
Valid values: 
'oneget', 'psgallery', 'choco',
'choco:{url_of_repository}', 'psgallery:{urlofrepository}'
Default: oneget.

.PARAMETER wait
In some scenarios, there's a need to invoke an elevated command to install additional tools (i.e.: chocolatey).
Use -Wait switch to wait for user input after running these commands.

.PARAMETER scope
The scope in which the module will be installed (same as Scope of Install-Module)

.PARAMETER SkipPublisherCheck
Pass -SkipPublisherCheck to Install-Module

.PARAMETER AllowClobber
Pass -AllowClobber to Install-Module

.PARAMETER Force
Pass -Force to Install-Module

.INPUTS
None.

.OUTPUTS
None.

.EXAMPLE

PS> Request-Module Pester -version 4.4

#>
function Request-Module { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $modules, 
        $version = $null,
        $package = $null,
        [switch][bool] $reload,
        $source = "oneget",
        [switch][bool] $wait = $false,
        [Parameter()]
        [ValidateSet("AllUsers", "CurrentUser", "Auto")]
        [string] $scope = "CurrentUser",
        [switch][bool] $SkipPublisherCheck,
        [switch][bool] $AllowClobber = $true,
        [switch][bool] $Force
    ) 

    $original_version = $version
    if ($version -eq "latest") {
        $version = "999.999.999"
    }
    
    Import-Module process -Global -Verbose:$false
    if ($scope -eq "Auto") {
        $scope = "CurrentUser"
        if (test-isadmin) { $scope = "AllUsers" }
    }

    foreach ($_ in $modules) { 
        $name = $_
        $currentversion = $null
        $reloadPath = $null
        $mo = Get-Module $_
        $loaded = $mo -ne $null
        $found = $mo -ne $null
        if ($loaded) { $currentversion = $mo.Version[0] }
        if ($loaded -and !$reload -and ($mo.Version[0] -ge $version -or $version -eq $null)) { 
            Write-Verbose "module $_ is loaded with version $($mo.version). Nothing to do here"
            return 
        }
     
        if (!$found) {
            Write-Verbose "module $_ not loaded. looking for available versions"
            $available = @(Get-Module $_ -ListAvailable | sort version -Descending)
            $matchingVers = @($available | ? { $_.Version -ge $version })
            $mo = $matchingVers | select -First 1
            $found = $mo -ne $null
        }

    
        if ($found) {
            Write-Verbose "found module $($mo.name) version $($mo.version). requested version = $version. found=$found reload=$reload"
        }
        else {
            Write-Verbose "module $_ not found"
        }
       
        $needsReload = $reload -or ($version -ne $null -and $currentversion -lt $version)
        if ($loaded -and $needsReload) {
            Write-Verbose "removing module $mo"
            $removedModule = $mo
            Remove-Module $mo -Verbose:$false
        }
     
        function init-psget {
            if ($global:psgetready) {
                return
            }
            Write-Verbose "initializing psget"
            if ((Get-Command Install-PackageProvider -Module PackageManagement -ErrorAction Ignore) -ne $null) {
                Import-Module PackageManagement -Verbose:$false
                $nuget = Get-PackageProvider -Name Nuget -Force -ForceBootstrap
                if ($nuget -eq $null) {
                    Write-Host "installing nuget package provider"
                    # this isn't availalbe in the current official release of oneget (?)
                    Install-PackageProvider -Name NuGet -Force -MinimumVersion 2.8.5.201 -Verbose
                } 
            }
            Import-Module powershellget -Verbose:$false
            if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne "Trusted") {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            }
            $global:psgetready = $true
        }
        function RequestPowershellModule($name) {
            $psrepository = $null
            if ($source.startswith("psgallery:")) {
                $psrepository = $source.substring("psgallery:".Length)
            }
            Write-Warning "trying powershellget package manager repository='$psrepository'"
            init-psget
            $islinked = $false
           
            if ($mo -eq $null) {
                $p = @{
                    Name        = $name
                    Verbose     = $true
                    Scope       = $scope
                    ErrorAction = "Stop"
                }
   
   
                if ($AllowClobber -and ((Get-Command install-module).Parameters.AllowClobber) -ne $null) {
                    $p += @{ AllowClobber = $true }  
                } 
                if ($SkipPublisherCheck -and ((Get-Command install-module).Parameters.SkipPublisherCheck) -ne $null) {
                    $p += @{ SkipPublisherCheck = $true }  
                } 
                if ($Force) {
                    $p += @{ Force = $true }
                }

                if ($psrepository -ne $null) {
                    $p += @{ Repository = $psrepository }
                }
                $cmd = "install-module"
                Write-Warning "$cmd [scope=$scope]"                       
                foreach ($kvp in $p.GetEnumerator()) {
                    $val = $kvp.value
                    if ($val -eq $true) { $val = "`$true" }
                    $cmd += " -$($kvp.key):$($val)"
                }
                if ($scope -eq "CurrentUser") {                       
                    Install-Module @p
                }
                else {
                    Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -Wait       
                    if ($LASTEXITCODE -ne 0) { Write-Error "install-module failed" }                 
                }
            }            
            else {
               
                # remove module to avoid loading multiple versions                    
                Remove-Module $name -ErrorAction Ignore
                $toupdate = $name
                $p = @{
                    Name        = $toupdate
                    Verbose     = $true
                    ErrorAction = "Stop"
                }
                if ($psrepository -ne $null) {
                    # update-module has no repository parameter
                    #  $p += @{ Repository = $psrepository }
                }
                $cmd = "update-module"
                foreach ($kvp in $p.GetEnumerator()) {
                    $val = $kvp.value
                    if ($val -eq $true) { $val = "`$true" }
                    $cmd += " -$($kvp.key):$($val)"
                }
                Write-Warning "$cmd [scope=$scope]"                    
                if ($scope -eq "CurrentUser") {
                    try {   
                        Import-Module pathutils -Verbose:$false
                        $path = $mo.path                       
                        try {
                            $target = pathutils\Get-JunctionTarget (Split-Path -Parent $path)
                            $islinked = $target -ne $null
                        }
                        catch {
                            Write-Warning $_.Exception.message
                        }
                        if ($islinked) {
                            Write-Verbose "module $toupdate is linked to path $target. updating from source control"
                            pathutils\Update-ModuleLink $toupdate -ErrorAction stop
                        }
                        else {
                            Write-Verbose "updating module $toupdate"
                            Update-Module @p                                      
                        }
                    }
                    catch {
                        if ($_.Exception.Message.Contains("Install-Module")) { 
                            # "was not installed by using Install-Module"
                            throw
                        }
                        elseif ($_.Exception.Message.Contains("Administrator")) {
                            # "cannot be updated because Administrator rights are required"
                            Write-Warning "need to update module as admin"
                            # if module was installed as Admin, try to update as admin
                            Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -Wait    
                            if ($LASTEXITCODE -ne 0) { Write-Error "update-module failed" }
                        }
                        else {
                            throw
                        }
                    }
                }
                else {
                    Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -Wait
                    if ($LASTEXITCODE -ne 0) { Write-Error "update-module failed" }
   
                }
            }
            $mo = Get-Module $name -ListAvailable | sort version -Descending | select -First 1   
           
            if ($mo -ne $null -and $mo.Version[0] -lt $version -and !$islinked) {
                # ups, update-module did not succeed?
                # if module is already installed, oneget will try to update from same repositoty
                # if the repository has changed, we need to force install 
   
                Write-Warning "requested module $name version $version, but found $($mo.Version[0])!"
                $p = @{
                    Name        = $name
                    Verbose     = $true
                    Scope       = $scope
                    ErrorAction = "Stop"
                    Force       = $true
                }
                if ($AllowClobber -and ((Get-Command install-module).Parameters.AllowClobber) -ne $null) {
                    $p += @{ AllowClobber = $true }  
                } 
                if ($SkipPublisherCheck -and ((Get-Command install-module).Parameters.SkipPublisherCheck) -ne $null) {
                    $p += @{ SkipPublisherCheck = $true }  
                } 
                if ($psrepository -ne $null) {
                    $p += @{ Repository = $psrepository }
                }
                $cmd = "install-module"
                Write-Warning "trying again: $cmd [scope=$scope]"
         
                foreach ($kvp in $p.GetEnumerator()) {
                    $val = $kvp.value
                    if ($val -eq $true) { $val = "`$true" }
                    $cmd += " -$($kvp.key):$($val)"
                }
                if ($scope -eq "CurrentUser") {                       
                    Install-Module @p
                }
                else {                      
                    Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -Wait    
                    if ($LASTEXITCODE -ne 0) { Write-Error "update-module failed" }                    
                }
                $mo = Get-Module $name -ListAvailable | sort version -Descending | select -First 1  
            }
   
            if ($mo -eq $null) { 
                Write-Warning "failed to install module $name through oneget"
                Write-Warning "available modules:"
                $list = Find-Module $name
                $list
            }
            elseif ($mo.Version[0] -lt $version -and $original_version -ne "latest") {
                Write-Warning "modules found:"
                $m = Find-Module $name
                $m | Format-Table | Out-String | Write-Warning                    
                Write-Warning "sources:"
                $s = Get-PackageSource
                $s | Format-Table | Out-String | Write-Warning
            }   
        }
        function RequestChocoPackage($name) {
            if ($mo -eq $null) {
                # install 
                $cmd = "Process\invoke choco install -y $package -verbose"
                if ($source.startswith("choco:")) {
                    $customsource = $source.substring("choco:".length)
                    $cmd = "Process\invoke choco install -y $package -source $customsource -verbose"
                }
                $processModulePath = Split-Path -Parent (Get-Module Process).path
                # ensure choco is installed, then install package
                Invoke-AsAdmin -ArgumentList @("-Command", "
                   try {
                      `$env:PSModulePath = `$env:PSModulePath + ';$processModulePath'
                   . '$PSScriptRoot\functions\helpers.ps1';
                   Import-Module Require
                   req Process
                   write-host 'Ensuring chocolatey is installed';
                   _ensure-choco;
                   write-host 'installing chocolatey package $package';
                   $cmd;
                   } finally {
                       if (`$$wait) { Read-Host 'press Enter to close  this window and continue'; }
                   }
               ") -Wait
                if ($LASTEXITCODE -ne 0) { Write-Error "choco install failed" }
   
                #refresh PSModulePath
                # throw "Module $name not found. `r`nSearched paths: $($env:PSModulePath)"
            }
            elseif ($mo.Version[0] -lt $version) {
                # update
                Write-Warning "requested module $name version $version, but found $($mo.Version[0])!"
                # ensure choco is installed, then upgrade package
                $cmd = "Process\invoke choco upgrade -y $package -verbose"
                if ($source.startswith("choco:")) {
                    $customsource = $source.substring("choco:".length)
                    $cmd = "Process\invoke choco upgrade -y $package -source $customsource -verbose"
                }
                $processModulePath = Split-Path -Parent ((Get-Module Process).path)
      
                Invoke-AsAdmin -ArgumentList @("-Command", "
                   try {       
                   `$ex = `$null;              
                   `$env:PSModulePath = `$env:PSModulePath + ';$processModulePath'
                   Import-Module Require
                   req Process
                   . '$PSScriptRoot\functions\helpers.ps1';
                   write-host 'Ensuring chocolatey is installed';
                   _ensure-choco;
                   write-host 'updating chocolatey package $package';
                   $cmd;
                   
                   if (`$$wait) { Read-Host 'press Enter to close  this window and continue' }
                   
                   } catch {
                       write-error `$_;
                       `$ex = `$_;
                       if (`$$wait) { Read-Host 'someting went wrong. press Enter to close this window and continue' }
                       throw;
                   }
                   finally {
                   }
               ") -Wait  
                if ($LASTEXITCODE -ne 0) { Write-Error "choco upgrade failed" }
   
            }
   
            refresh-modulepath 
            if ($mo -ne $null) { Remove-Module $name }
            Import-Module $name -ErrorAction Ignore
        }
   
       
        if (!$found) {
            . "$PSScriptRoot\functions\helpers.ps1"
            
            $verstring = "not found"
            if ($currentversion -ne $null) { $verstring = "is not satisfied by current version=$currentversion" }
            Write-Warning "module $_ version >= $version $verstring. installing from $source"
            if ($source -eq "choco" -or $source.startswith("choco:")) {
                requestchocopackage -name $_
            }
            if ($source -in "oneget", "psget", "powershellget", "psgallery" -or $source.startswith("psgallery:")) {
                RequestPowershellModule -name $_
            }
            
            $mo = Get-Module $name -ListAvailable | sort version -Descending
            $found = $mo -ne $null -and $mo.Version[0] -ge $version
        }
        else {
            if (($matchingvers -ne $null) -and ($matchingvers.count -ge 0)) {
                Import-Module $_ -MinimumVersion $version
                $mo = Get-Module $_
            }
        }

        if ($removedModule) {
            $moduleDir = Split-Path $removedModule.Path -Parent
            $isFromSource = $false
            try {
                $gitCheck = git -C $moduleDir rev-parse --is-inside-work-tree 2>$null
                $isFromSource = ($gitCheck -eq "true")
            }
            catch {}
            if ($isFromSource) {
                Write-Verbose "Module $_ was loaded from source: '$($removedModule.Path)'. Reloading from the same path."
                Import-Module $removedModule.Path -DisableNameChecking -Global -Force -ErrorAction stop
                continue
            }
        }

        if (!($mo)) {          
            throw "Module $_ not found. `r`nSearched paths: $($env:PSModulePath)"
        }
        if ($original_version -eq "latest") {
            Import-Module $_ -DisableNameChecking -Global -ErrorAction stop
            $mo = Get-Module $_
            Write-Host "lastest version of module $_ : $($mo.version)"
        }
        else {
            if ($mo.Version[0] -lt $version) {
                throw "requested module $_ version $version, but found $($mo.Version[0])!"
            }
            Import-Module $_ -DisableNameChecking -MinimumVersion $version -Global -ErrorAction stop
        }

        
    }
}


if ((Get-Alias Require-Module -ErrorAction ignore) -eq $null) { New-Alias Require-Module Request-Module }
if ((Get-Alias req -ErrorAction ignore) -eq $null) { New-Alias req Request-Module }

Export-ModuleMember -Function "Request-Module" -Alias *