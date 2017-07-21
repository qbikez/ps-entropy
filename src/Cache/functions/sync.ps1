
function get-propertynames($obj) {
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



function get-syncdir() {
    if (test-path "HKCU:\Software\Microsoft\OneDrive") 
    {
        $prop = get-itemproperty "HKCU:\Software\Microsoft\OneDrive\" "UserFolder"
        if ($prop -ne $null) {
            $dir = $prop.userfolder
        }        
    }

    if ($dir -ne $null) {
        $syncdir = join-path $dir ".powershell-data"
        if (!(test-path $syncdir)) {
            $null = mkdir $syncdir
        }
        return $syncdir
    }
}


function set-globalpassword {
    Get-CredentialsCached -message "Global settings password" -reset -container "global-key"
}

function _getenckey { 
    [CmdletBinding()]
    param() 
    $pass = get-passwordcached -message "Global settings password" -container "global-key" -allowuserui
    $rfc = new-object System.Security.Cryptography.Rfc2898DeriveBytes $pass,@(1,2,3,4,5,6,7,8),1000            
    $enckey = $rfc.GetBytes(256/8);
    #write-verbose "key=$($enckey | convertto-base64) length=$($enckey.length)"
    return $enckey
} 

function new-credentials(
    [Parameter(Mandatory=$true)]$username, 
    [Parameter(Mandatory=$true)][securestring]$password) {
        return New-Object 'system.management.automation.pscredential' $username,$password
    }

function convertto-plaintext([Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=1)][securestring]$password) {
    return (new-credentials $="dummy" $password).GetNetworkCredential().password
}

function import-settings {
    [CmdletBinding()]
    param ()
    $syncdir = get-syncdir
    if ($syncdir -eq $null) {
        write-warning "couldn't find OneDrive synced folder"
        return
    }
    $settings = import-cache -container "user-settings" -dir $syncdir | convertto-hashtable 
    
    
    if ($settings -eq $null) {
        $settings = @{}
    }

    $decrypted = @{}
    foreach($kvp in $settings.GetEnumerator()) {
        if ($kvp.value.startswith("enc:")) {
            try {
             $enckey = _getenckey
             $encvalue = $kvp.value.substring("enc:".length)
             $secvalue = convertto-securestring $encvalue -Key $enckey -ErrorAction stop
             $decrypted[$kvp.key] = $secvalue
             #$creds = new-object system.management.automation.pscredential ("dummy",$secvalue)
             #$pass = $creds.getnetworkcredential().password 
            } catch {
                write-warning "failed to decode key $($kvp.key): $_"
                $decrypted[$kvp.key] = $kvp.value
            }
        }
        else {
            $decrypted[$kvp.key] = $kvp.value
        }
    }

    $settings = $decrypted
    write-verbose "imported $($settings.Count) settings from '$syncdir'"

    $global:settings = $settings

    return $settings
}

function export-setting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] $key, 
        [Parameter(Mandatory=$true)] $value, 
        [Switch][bool]$force,
        [Alias("secure")][Switch][bool]$encrypt
        ) 
    $syncdir = get-syncdir
    if ($syncdir -eq $null) {
        write-warning "couldn't find OneDrive synced folder"
        return
    }
    $settings = import-cache -container "user-settings" -dir $syncdir | convertto-hashtable
    if ($settings -eq $null) { $settings = @{} }
    if ($settings[$key] -ne $null) {
        if (!$force) {
            write-warning "a setting with key $key already exists. Use -Force to override"
            return
        }
    }
    write-verbose "storing setting $key=$value at '$syncdir'"
    if ($encrypt) {
        $enckey = _getenckey
        $secvalue = convertto-securestring $value -asplaintext -force
        $encvalue = convertfrom-securestring $secvalue -key $enckey
        $settings[$key] = "enc:$encvalue"
    } else {
        $settings[$key] = "$value"
    }
    export-cache -data $settings -container "user-settings" -dir $syncdir
 
    import-settings
}

