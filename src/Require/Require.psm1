                        
function Request-Module(
    [Parameter(Mandatory=$true)]
    $modules, 
    $version = $null,
    $package = $null,
    [switch][bool] $reload,
    $source = "oneget",
    [switch][bool] $wait = $false,
    [Parameter()]
    [ValidateSet("AllUsers","CurrentUser","Auto")]
    [string] $scope = "Auto"

) {
    import-module process -Global
    if ($scope -eq "Auto") {
        $scope = "CurrentUser"
        if (test-IsAdmin) { $scope = "AllUsers" }
    }

    foreach($_ in $modules)
    { 
        $currentversion = $null
        $mo = gmo $_
        $loaded = $mo -ne $null
        $found = $loaded
        if ($loaded) { $currentversion = $mo.Version[0] }
        if ($loaded -and !$reload -and ($mo.Version[0] -ge $version -or $version -eq $null)) { return }

        if (!$loaded) {
            try {
                ipmo $_ -ErrorAction SilentlyContinue -Global
                $mo = gmo $_
                $loaded = $mo -ne $null
                $found = $loaded
            } catch {
            }
        }

        if(!$found) {
            $mo = gmo $_ -ListAvailable
        }
        $found = $mo -ne $null -and $mo.Version[0] -ge $version
    

        if(!$found -and $mo -ne $null) {
            $available = @(gmo $_ -ListAvailable)
            $mo = $available
            $matchingVers = @($available | ? { $_.Version -ge $version })
            $found = ($matchingVers.Length -gt 0)
        }
    
        if ($reload -or ($version -ne $null -and $mo -ne $null -and $mo.Version[0] -lt $version)) {
            if (gmo $_) { rmo $_ }            
        }

        if (!$found) {
            . "$PSScriptRoot\functions\helpers.ps1";

            if ($currentversion -ne $null) { write-host "current version of module $_ is $currentversion" }
			write-warning "module $_ version >= $version not found. installing from $source"
            if ($source -eq "choco" -or $source.startswith("choco:")) {
                if ($mo -eq $null) {
					$cmd = "Process\invoke choco install -y $package -verbose"
					if ($source.startswith("choco:")) {
						$customsource = $source.substring("choco:".length)
						$cmd = "Process\invoke choco install -y $package -source $customsource -verbose"
					}
                    $processModulePath = split-path -parent (gmo Process).path
                    # ensure choco is installed, then install package
                    run-AsAdmin -ArgumentList @("-Command", "
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
                    refresh-modulepath 
                    $mo = gmo $_ -ListAvailable
                    # throw "Module $_ not found. `r`nSearched paths: $($env:PSModulePath)"
                }
                elseif ($mo.Version[0] -lt $version) {
                    write-warning "requested module $_ version $version, but found $($mo.Version[0])!"
                    # ensure choco is installed, then upgrade package
                    $cmd = "Process\invoke choco upgrade -y $package -verbose"
                    if ($source.startswith("choco:")) {
						$customsource = $source.substring("choco:".length)
						$cmd = "Process\invoke choco upgrade -y $package -source $customsource -verbose"
					}
                    $processModulePath = split-path -parent ((gmo Process).path)
           
                    run-AsAdmin -ArgumentList @("-Command", "
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

                    refresh-modulepath 
                    $mo = gmo $_ -ListAvailable
                }
            }
            if ($source -in "oneget","psget","powershellget","psgallery" -or $source.startswith("psgallery:")) {
                $psrepository = $null
                if ($source.startswith("psgallery:")) {
                    $psrepository = $source.substring("psgallery:".Length)
                }
                write-warning "trying powershellget package manager repository='$psrepository'"
                if ((get-command Install-PackageProvider -module PackageManagement -ErrorAction Ignore) -ne $null) {
                    import-module PackageManagement
                    $nuget = get-packageprovider -Name Nuget -force -forcebootstrap
                    if ($nuget -eq $null) {
                        write-host "installing nuget package provider"
                        # this isn't availalbe in the current official release of oneget (?)
                        install-packageprovider -Name NuGet -Force -MinimumVersion 2.8.5.201 -verbose
                    } 
                }
                import-module powershellget
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                
                if ($mo -eq $null) {
                    $p = @{
                        Name = $_
                        Verbose = $true
                        Scope = $scope
                        ErrorAction = "Stop"
                    }
                    if (((get-command install-module).Parameters.AllowClobber) -ne $null) {
                        $p += @{ AllowClobber = $true }  
                    } 
                    if ($psrepository -ne $null) {
                        $p += @{ Repository = $psrepository }
                    }
                    $cmd = "install-module"
                    write-warning "$cmd"                    
                    foreach($kvp in $p.GetEnumerator()) {
                        $val = $kvp.value
                        if ($val -eq $true) { $val = "`$true" }
                        $cmd += " -$($kvp.key):$($val)"
                    }
                    if ($scope -eq "CurrentUser") {                       
                        install-module @p
                    } else {
                        run-AsAdmin -ArgumentList @("-Command", $cmd) -wait       
                        if ($LASTEXITCODE -ne 0) { write-error "install-module failed" }                 
                    }
                }            
                else {
                    # remove module to avoid loading multiple versions                    
                    rmo $_ -erroraction Ignore
                    $toupdate = $_
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
                    write-warning "$cmd"                    
                    if ($scope -eq "CurrentUser") {
                        try {   
                            update-module @p                                      
                        } catch {
                            write-warning "need to update module as admin"
                            # if module was installed as Admin, try to update as admin
                            run-AsAdmin -ArgumentList @("-Command", $cmd) -wait    
                            if ($LASTEXITCODE -ne 0) { write-error "update-module failed" }
                        }
                    } else {
                        run-AsAdmin -ArgumentList @("-Command", $cmd) -wait
                        if ($LASTEXITCODE -ne 0) { write-error "update-module failed" }

                    }
                }
                $mo = gmo $_ -ListAvailable | select -first 1   
                
                if ($mo -ne $null -and $mo.Version[0] -lt $version) {
                    # ups, update-module did not succeed?
                    # if module is already installed, oneget will try to update from same repositoty
                    # if the repository has changed, we need to force install 

                    write-warning "requested module $_ version $version, but found $($mo.Version[0])!"
                    $p = @{
                        Name = $_
                        Verbose = $true
                        Scope = $scope
                        ErrorAction = "Stop"
                        Force = $true
                    }
                    if (((get-command install-module).Parameters.AllowClobber) -ne $null) {
                        $p += @{ AllowClobber = $true }  
                    } 
                    if ($psrepository -ne $null) {
                        $p += @{ Repository = $psrepository }
                    }
                    $cmd = "install-module"
                    write-warning "trying again: $cmd"
              
                    foreach($kvp in $p.GetEnumerator()) {
                        $val = $kvp.value
                        if ($val -eq $true) { $val = "`$true" }
                        $cmd += " -$($kvp.key):$($val)"
                    }
                    if ($scope -eq "CurrentUser") {                       
                        install-module @p
                    } else {                      
                        run-AsAdmin -ArgumentList @("-Command", $cmd) -wait    
                        if ($LASTEXITCODE -ne 0) { write-error "update-module failed" }                    
                    }
                    $mo = gmo $_ -ListAvailable    
                }

                if ($mo -eq $null) { 
                    Write-Warning "failed to install module $_ through oneget"
                    Write-Warning "available modules:"
                    $list = find-module $_
                    $list
                } elseif ($mo.Version[0] -lt $version) {
                    Write-Warning "modules found:"
                    $m = find-module $_
                    $m | Format-Table | Out-String | Write-Warning                    
                    Write-Warning "sources:"
                    $s = Get-PackageSource
                    $s | Format-Table | Out-String | Write-Warning
                }   
            }
        
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
        if ($mo.Version[0] -lt $version) {
            throw "requested module $_ version $version, but found $($mo.Version[0])!"
        }

        Import-Module $_ -DisableNameChecking -MinimumVersion $version -Global -ErrorAction stop
        }
}


if ((get-alias Require-Module -ErrorAction ignore) -eq $null) { new-alias Require-Module Request-Module }
if ((get-alias req -ErrorAction ignore) -eq $null) { new-alias req Request-Module }

Export-ModuleMember -Function "Request-Module" -Alias *