
function Get-PropertyNames($obj) {
  #  Measure-function "$($MyInvocation.MyCommand.Name)" {    
        if ($obj -is [System.Collections.IDictionary]) {
            return $obj.keys
        }
        return $obj.psobject.Properties | select -ExpandProperty name
 #   }
}

function ConvertTo-Hashtable([Parameter(ValueFromPipeline=$true)]$obj, [switch][bool]$recurse) {
 #   Measure-function  "$($MyInvocation.MyCommand.Name)" {

        $object =$obj
        if (!$recurse -and ($object -is [System.Collections.IDictionary] -or $object -is [array])) {
            return $object
        }
 
        if($object -is [array]) {
            if ($recurse) {
                for($i = 0; $i -lt $object.Length; $i++) {
                    $object[$i] = ConvertTo-Hashtable $object[$i] -recurse:$recurse
                }
            }
            return $object
        } 
        elseif ($object -is [System.Collections.IDictionary] -or  $object -is [System.Management.Automation.PSCustomObject] -or $true) {
            $h = @{}
            $props = get-propertynames $object
            foreach ($p in $props) {
                if ($recurse) {
                    $h[$p] = ConvertTo-Hashtable $object.$p -recurse:$recurse
                } else {
                    $h[$p] = $object.$p
                }
            }
            return $h
        } else {
            throw "could not convert object to hashtable"
            #return $object
        }
 #   }
	
}


function Get-SyncDir {
    param($type = $null)

    if ($type -eq "onedrive") {
        if (test-path "HKCU:\Software\Microsoft\OneDrive") 
        {
            $prop = get-itemproperty "HKCU:\Software\Microsoft\OneDrive\" "UserFolder"
            if ($prop -ne $null) {
                $dir = $prop.userfolder
            }        
        }
    }
    elseif ($type -eq "local") {
        $dir = $env:USERPROFILE
    }
    elseif ($type -eq $null) {
        # try default locations. onedrive then local
        $syncdir = get-syncdir -type onedrive
        if ($syncdir -eq $null) {
            write-warning "couldn't find OneDrive synced folder. Using local storage - settings will not be synced across devices."
            $syncdir = get-syncdir -type local
        }
        return $syncdir
    }
    else {
        throw "unrecognized sync dir type: '$type'"
    }

    if ($dir -ne $null) {
        $syncdir = join-path $dir ".powershell-data"
        if (!(test-path $syncdir)) {
            $null = mkdir $syncdir
        }
        return $syncdir
    }
}


function Set-GlobalPassword {
    [CmdletBinding()]
    param(
        $container = "user-settings",
        [SecureString] $password = $null
    )

    if ($container -eq "user-settings") { $container = "global-key" }
    else { $container = "global-key-" + $container }
    if ($password -eq $null) {
        # TODO: hash password before storing it - make sure noone can retrieve plaintext password
        $c = Get-CredentialsCached -message "Global settings password" -reset -container $container
    } else {
        $c = new-credentials -username "any" -password $password
        Export-Credentials -container $container -cred $c
    }
}
function Remove-GlobalPassword {
    param($container = "user-settings")   
 
    if ($container -eq "user-settings") { $container = "global-key" }
    else { $container = "global-key-" + $container }

    Remove-CredentialsCached -container $container
}

function Update-GlobalPassword {
    [CmdletBinding()]
    param(
        $container = "user-settings",
        [SecureString] $password
        )

    $newpass = $password
    if ($newpass -eq $null) {
        import-module Microsoft.PowerShell.Security -verbose:$false
        $c = Microsoft.PowerShell.Security\Get-Credential -message "Global settings password" 
        $newpass = $c.password
    }
    # make sure current password is correct - stop on any warning
    $settings = Import-Settings -container $container -ErrorAction stop
    
    # reencrypt everything
    foreach($kvp in $settings.GetEnumerator()) {
        $key = $kvp.key
        if ($kvp.value -is [securestring]) {
            Export-Setting -container $container -key $key -securevalue $kvp.value -password $newpass -force        
        }         
    }

    Set-GlobalPassword -container $container -password $newpass
    $null = Import-Settings -container $container
}

function _getenckey { 
    [CmdletBinding()]
    param(
        [SecureString]$password,
        $container = "user-settings"
    ) 
    $pass = $password
    if ($container -eq "user-settings") { $container = "global-key" }
    else { $container = "global-key-" + $container }
    if ($pass -eq $null) {
        $pass = get-passwordcached -message "Global settings password" -container $container -allowuserui
    } 
    if ($pass -is [SecureString]) {$pass = ConvertTo-PlainText $pass }
    $rfc = new-object System.Security.Cryptography.Rfc2898DeriveBytes $pass,@(1,2,3,4,5,6,7,8),1000            
    $enckey = $rfc.GetBytes(256/8);
    #write-verbose "key=$($enckey | convertto-base64) length=$($enckey.length)"
    return $enckey
} 

function New-Credentials(
    [Parameter(Mandatory=$true)]$username, 
    [Parameter(Mandatory=$true)][SecureString]$password) {
        return New-Object 'system.management.automation.pscredential' $username,$password
    }

function ConvertTo-PlainText {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)][securestring]$password
    )
    return (new-credentials $="dummy" $password).GetNetworkCredential().password
}

function Import-Settings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)] $enckey = $null,
        [Parameter(Mandatory=$false)][SecureString] $password = $null,
        $container = "user-settings"
    )
    $syncdir = get-syncdir
    if ($syncdir -eq $null) { throw "couldn't determine settings home directory" } 
    
    $settings = import-cache -container $container -dir $syncdir | convertto-hashtable 
    
    
    if ($settings -eq $null) {
        $settings = @{}
    }

    $decrypted = @{}
    
    foreach($kvp in $settings.GetEnumerator()) {
        if ($kvp.value -eq $null) {
            # just skip nulls
            continue
        }
        if ($kvp.value.startswith("enc:")) {
            if ($enckey -eq $null) { $enckey = _getenckey -password $password -container $container }
            try {                
             $encvalue = $kvp.value.substring("enc:".length)
             $secvalue = convertto-securestring $encvalue -Key $enckey -ErrorAction stop
             $decrypted[$kvp.key] = $secvalue
             #$creds = new-object system.management.automation.pscredential ("dummy",$secvalue)
             #$pass = $creds.getnetworkcredential().password 
            } catch {
                write-Error "failed to decode key $($kvp.key): $_"
                $decrypted[$kvp.key] = $kvp.value
            }
        }
        else {
            $decrypted[$kvp.key] = $kvp.value
        }
    }

    $settings = $decrypted
    write-verbose "imported $($settings.Count) settings from '$syncdir'"

    if ($container -eq "user-settings") {
        $global:settings = $settings
    }

    return $settings
}

function Export-Settings {
    [CmdletBinding(DefaultParameterSetName="plaintext")]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] $settings, 
        $container = "user-settings"
    )
    $syncdir = get-syncdir
    export-cache -data $settings -container $container -dir $syncdir
}

function Export-Setting {
    [CmdletBinding(DefaultParameterSetName="plaintext")]
    param(
        [Parameter(Mandatory=$true)] $key, 
        [Parameter(Mandatory=$true,ParameterSetName="plaintext")] $value, 
        [Alias("secure")]
        [Parameter(Mandatory=$true,ParameterSetName="encrypted")][securestring] $securevalue, 
        [Parameter(Mandatory=$false,ParameterSetName="encrypted")] $enckey = $null,
        [Parameter(Mandatory=$false,ParameterSetName="encrypted")][SecureString] $password = $null,
        $container = "user-settings",
        [Switch][bool]$force
        ) 
    $syncdir = get-syncdir
    if ($syncdir -eq $null) { throw "couldn't determine settings home directory" } 
        
    $settings = import-cache -container $container -dir $syncdir | convertto-hashtable
    if ($settings -eq $null) { $settings = @{} }
    if ($settings[$key] -ne $null) {
        if (!$force) {
            write-warning "a setting with key $key already exists. Use -Force to override"
            return
        }
    }
    $encrypt = $securevalue -ne $null
    write-verbose "storing setting $key=$value at '$syncdir'"
    if ($encrypt) {
        if ($enckey -eq $null) { $enckey = _getenckey -password $password -container $container }
        $secvalue = $securevalue
        $encvalue = convertfrom-securestring $secvalue -key $enckey
        $settings[$key] = "enc:$encvalue"
    } else {
        $settings[$key] = "$value"
    }
    export-cache -data $settings -container $container -dir $syncdir
 
    if ($container -eq "user-settings") {
        # make sure settings are imported into global variable
        $null = import-settings -container $container -password $password 
    }
}

