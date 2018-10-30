function Request-Module { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $modules, 
        $version = $null,
        $package = $null,
        [switch][bool] $reload,
        $source = "oneget",
        [switch][bool] $wait = $false,
        [Parameter()]
        [ValidateSet("AllUsers","CurrentUser","Auto")]
        [string] $scope = "CurrentUser",
        [switch][bool] $SkipPublisherCheck,
        [switch][bool] $AllowClobber = $true
    ) 

    $original_version = $version
    if ($version -eq "latest") {
        $version = "999.999.999"
    }
    
    import-module process -Global -Verbose:$false
    if ($scope -eq "Auto") {
        $scope = "CurrentUser"
        if (test-IsAdmin) { $scope = "AllUsers" }
    }

    foreach($_ in $modules)
    { 
        $name = $_
        $currentversion = $null
        $mo = gmo $_
        $loaded = $mo -ne $null
        $found = $loaded
        if ($loaded) { $currentversion = $mo.Version[0] }
        if ($loaded -and !$reload -and ($mo.Version[0] -ge $version -or $version -eq $null)) { 
            write-verbose "module $_ is loaded with version $($mo.version). Nothing to do here"
            return 
        }
     
        if (!$loaded) {
            try {
                write-verbose "module $_ is not loaded. trying to load."
                ipmo $_ -ErrorAction SilentlyContinue -Global -Verbose:$false
                $mo = gmo $_
                $loaded = $mo -ne $null
                if ($loaded) {
                    write-verbose "loaded"
                }
                
                $found = $loaded
            } catch {
                write-verbose "failed to load module $name : $($_.Exception.Message)"
            }
        } 
        
       
        if(!$found) {
            $mo = gmo $_ -ListAvailable | sort version -Descending
            write-verbose "module $_ not found"
        }
        $found = $mo -ne $null -and $mo.Version[0] -ge $version
    
        if ($mo -ne $null) {
            write-verbose "found module $($mo.name) version $($mo.version). found=$found reload=$reload"
        }
        else {
            write-verbose "module $_ not found"
        }

        if(!$found -and $mo -ne $null) {
            $available = @(gmo $_ -ListAvailable | sort version -Descending)
            $mo = $available
            $matchingVers = @($available | ? { $_.Version -ge $version })
            $found = ($matchingVers.Length -gt 0)
            write-verbose "found $($matchingVers.count) matching versions from total $($available.count)"
            #$found = $available -ne $null
        }
       
        if ($mo -ne $null) {
            write-verbose "version=$version mo=$mo mo.version=$($mo.Version[0]) requested version = $version"
        }
        if ($reload -or ($version -ne $null -and $loaded -and $currentversion -lt $version)) {
            write-verbose "removing module $_"
            if (gmo $_) { rmo $_ -Verbose:$false }
        }
     
        function init-psget {
            if ($global:psgetready) {
                return
            }
            write-verbose "initializing psget"
            if ((get-command Install-PackageProvider -module PackageManagement -ErrorAction Ignore) -ne $null) {
               import-module PackageManagement -Verbose:$false
               $nuget = get-packageprovider -Name Nuget -force -forcebootstrap
               if ($nuget -eq $null) {
                   write-host "installing nuget package provider"
                   # this isn't availalbe in the current official release of oneget (?)
                   install-packageprovider -Name NuGet -Force -MinimumVersion 2.8.5.201 -verbose
               } 
           }
           import-module powershellget -Verbose:$false
           if ((get-PSRepository -Name PSGallery).InstallationPolicy -ne "Trusted") {
               Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
           }
           $global:psgetready = $true
       }
       function RequestPowershellModule($name) {
           $psrepository = $null
           if ($source.startswith("psgallery:")) {
               $psrepository = $source.substring("psgallery:".Length)
           }
           write-warning "trying powershellget package manager repository='$psrepository'"
           init-psget
           $islinked = $false
           
           if ($mo -eq $null) {
               $p = @{
                   Name = $name
                   Verbose = $true
                   Scope = $scope
                   ErrorAction = "Stop"
               }
   
   
               if ($AllowClobber -and ((get-command install-module).Parameters.AllowClobber) -ne $null) {
                   $p += @{ AllowClobber = $true }  
               } 
               if ($SkipPublisherCheck -and ((get-command install-module).Parameters.SkipPublisherCheck) -ne $null) {
                   $p += @{ SkipPublisherCheck = $true }  
               } 
               if ($psrepository -ne $null) {
                   $p += @{ Repository = $psrepository }
               }
               $cmd = "install-module"
               write-warning "$cmd [scope=$scope]"                       
               foreach($kvp in $p.GetEnumerator()) {
                   $val = $kvp.value
                   if ($val -eq $true) { $val = "`$true" }
                   $cmd += " -$($kvp.key):$($val)"
               }
               if ($scope -eq "CurrentUser") {                       
                   install-module @p
               } else {
                   Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -wait       
                   if ($LASTEXITCODE -ne 0) { write-error "install-module failed" }                 
               }
           }            
           else {
               
               # remove module to avoid loading multiple versions                    
               rmo $name -erroraction Ignore
               $toupdate = $name
               $p = @{
                   Name = $toupdate
                   Verbose = $true
                   ErrorAction = "Stop"
               }
               if ($psrepository -ne $null) {
                   # update-module has no repository parameter
                 #  $p += @{ Repository = $psrepository }
               }
               $cmd = "update-module"
               foreach($kvp in $p.GetEnumerator()) {
                   $val = $kvp.value
                   if ($val -eq $true) { $val = "`$true" }
                   $cmd += " -$($kvp.key):$($val)"
               }
               write-warning "$cmd [scope=$scope]"                    
               if ($scope -eq "CurrentUser") {
                   try {   
                       ipmo pathutils -Verbose:$false
                       $path = $mo.path                       
                       try {
                           $target = pathutils\Get-JunctionTarget (split-path -parent $path)
                           $islinked = $target -ne $null
                       } catch {
                           write-warning $_.Exception.message
                       }
                       if ($islinked) {
                           write-verbose "module $toupdate is linked to path $target. updating from source control"
                           pathutils\update-modulelink $toupdate -ErrorAction stop
                       } else {
                            write-verbose "updating module $toupdate"
                           update-module @p                                      
                       }
                   } catch {
                       if ($_.Exception.Message.Contains("Install-Module")) { 
                           # "was not installed by using Install-Module"
                           throw
                       }
                       elseif ($_.Exception.Message.Contains("Administrator")) {
                           # "cannot be updated because Administrator rights are required"
                           write-warning "need to update module as admin"
                           # if module was installed as Admin, try to update as admin
                           Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -wait    
                           if ($LASTEXITCODE -ne 0) { write-error "update-module failed" }
                       }
                       else {
                           throw
                       }
                   }
               } else {
                   Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -wait
                   if ($LASTEXITCODE -ne 0) { write-error "update-module failed" }
   
               }
           }
           $mo = gmo $name -ListAvailable | sort version -Descending | select -first 1   
           
           if ($mo -ne $null -and $mo.Version[0] -lt $version -and !$islinked) {
               # ups, update-module did not succeed?
               # if module is already installed, oneget will try to update from same repositoty
               # if the repository has changed, we need to force install 
   
               write-warning "requested module $name version $version, but found $($mo.Version[0])!"
               $p = @{
                   Name = $name
                   Verbose = $true
                   Scope = $scope
                   ErrorAction = "Stop"
                   Force = $true
               }
               if ($AllowClobber -and ((get-command install-module).Parameters.AllowClobber) -ne $null) {
                   $p += @{ AllowClobber = $true }  
               } 
               if ($SkipPublisherCheck -and ((get-command install-module).Parameters.SkipPublisherCheck) -ne $null) {
                   $p += @{ SkipPublisherCheck = $true }  
               } 
               if ($psrepository -ne $null) {
                   $p += @{ Repository = $psrepository }
               }
               $cmd = "install-module"
               write-warning "trying again: $cmd [scope=$scope]"
         
               foreach($kvp in $p.GetEnumerator()) {
                   $val = $kvp.value
                   if ($val -eq $true) { $val = "`$true" }
                   $cmd += " -$($kvp.key):$($val)"
               }
               if ($scope -eq "CurrentUser") {                       
                   install-module @p
               } else {                      
                   Invoke-AsAdmin -ArgumentList @("-Command", $cmd) -wait    
                   if ($LASTEXITCODE -ne 0) { write-error "update-module failed" }                    
               }
               $mo = gmo $name -ListAvailable | sort version -Descending | select -first 1  
           }
   
           if ($mo -eq $null) { 
               Write-Warning "failed to install module $name through oneget"
               Write-Warning "available modules:"
               $list = find-module $name
               $list
           } elseif ($mo.Version[0] -lt $version -and $original_version -ne "latest") {
               Write-Warning "modules found:"
               $m = find-module $name
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
               $processModulePath = split-path -parent (gmo Process).path
               # ensure choco is installed, then install package
               Invoke-AsAdmin -ArgumentList @("-Command", "
                   try {
                      `$env:PSModulePath = `$env:PSModulePath + ';$processModulePath'
                   . '$PSScriptRoot\functions\helpers.ps1';
                   ipmo Require
                   req Process
                   write-host 'Ensuring chocolatey is installed';
                   _ensure-choco;
                   write-host 'installing chocolatey package $package';
                   $cmd;
                   } finally {
                       if (`$$wait) { Read-Host 'press Enter to close  this window and continue'; }
                   }
               ") -wait
               if ($LASTEXITCODE -ne 0) { write-error "choco install failed" }
   
               #refresh PSModulePath
               # throw "Module $name not found. `r`nSearched paths: $($env:PSModulePath)"
           }
           elseif ($mo.Version[0] -lt $version) {
               # update
               write-warning "requested module $name version $version, but found $($mo.Version[0])!"
               # ensure choco is installed, then upgrade package
               $cmd = "Process\invoke choco upgrade -y $package -verbose"
               if ($source.startswith("choco:")) {
                   $customsource = $source.substring("choco:".length)
                   $cmd = "Process\invoke choco upgrade -y $package -source $customsource -verbose"
               }
               $processModulePath = split-path -parent ((gmo Process).path)
      
               Invoke-AsAdmin -ArgumentList @("-Command", "
                   try {       
                   `$ex = `$null;              
                   `$env:PSModulePath = `$env:PSModulePath + ';$processModulePath'
                   ipmo Require
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
               ") -wait  
               if ($LASTEXITCODE -ne 0) { write-error "choco upgrade failed" }
   
           }
   
           refresh-modulepath 
           if ($mo -ne $null) { rmo $name }
           ipmo $name -ErrorAction Ignore
       }
   
       
        if (!$found) {
            . "$PSScriptRoot\functions\helpers.ps1";
            
            $verstring = "not found"
            if ($currentversion -ne $null) { $verstring = "is not satisfied by current version=$currentversion" }
			write-warning "module $_ version >= $version $verstring. installing from $source"
            if ($source -eq "choco" -or $source.startswith("choco:")) {
                requestchocopackage -name $_
            }
            if ($source -in "oneget","psget","powershellget","psgallery" -or $source.startswith("psgallery:")) {
                RequestPowershellModule -name $_
            }
            
            $mo = gmo $name -ListAvailable | sort version -Descending
            $found = $mo -ne $null -and $mo.Version[0] -ge $version
        } else {
            if (($matchingvers -ne $null) -and ($matchingvers.count -ge 0)) {
                ipmo $_ -MinimumVersion $version
                $mo = gmo $_
            }
        }

               
        if (!($mo)) {          
            throw "Module $_ not found. `r`nSearched paths: $($env:PSModulePath)"
        }
        if ($original_version -eq "latest") {
            Import-Module $_ -DisableNameChecking -Global -ErrorAction stop
            $mo = gmo $_
            write-host "lastest version of module $_ : $($mo.version)"
        }
        else {
            if ($mo.Version[0] -lt $version) {
                throw "requested module $_ version $version, but found $($mo.Version[0])!"
            }
            Import-Module $_ -DisableNameChecking -MinimumVersion $version -Global -ErrorAction stop
        }

        
    }
}


if ((get-alias Require-Module -ErrorAction ignore) -eq $null) { new-alias Require-Module Request-Module }
if ((get-alias req -ErrorAction ignore) -eq $null) { new-alias req Request-Module }

Export-ModuleMember -Function "Request-Module" -Alias *