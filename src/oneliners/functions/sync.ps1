
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

function convertto-plaintext([Parameter(Mandatory=$true)][securestring]$password) {
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