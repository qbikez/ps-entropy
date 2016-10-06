
function export-credentials([Parameter(Mandatory=$true)]$container, $cred, [Alias("dir")]$cacheDir) {
    $result = New-Object -TypeName pscustomobject -Property @{ Password = $cred.Password | ConvertFrom-SecureString; Username = $cred.UserName }
    export-cache $result $container -dir $cacheDir
}

function import-credentials($container, [Alias("dir")]$cacheDir) {
    $lastcred = import-cache $container -dir $cacheDir
    if ($lastcred -ne $null) {
        $password = $lastcred.Password | ConvertTo-SecureString
        $username = $lastcred.Username
        $cred = New-Object System.Management.Automation.PsCredential $username,$password
    }

    return $cred
}

function Get-PasswordCached {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$container, $message, [switch][bool] $allowuserUI, [switch][bool]$secure) 
        
    $cacheDir = "pscredentials"
        try {
            $cred = import-credentials $container -dir $cacheDir
            if ($cred -eq $null) { 
                if ($allowuserUI) {
                      $cred = Get-CredentialsCached -container $container -message $message
                } else {
                    return $null 
                }
            }
            if ($secure) {
                return $cred.password
            } else {
                return $cred.GetNetworkCredential().Password
            }
        } catch {            
            throw
            return $null
        }
}

function Get-CredentialsCached {
[CmdletBinding()]
param([Parameter(Mandatory=$true)]$container, $message, [switch][bool]$reset = $false) 

    $cred = $null
    $cacheDir = "pscredentials"
    if (!$reset) {
        try {
        $cred = import-credentials $container -dir $cacheDir
        } catch {
        }
    }
    if ($cred -eq $null) {
        import-module Microsoft.PowerShell.Security
        if ($message -eq $null) {
            $message = "Please provide credentials for '$container'"
        }
        $cred = Get-Credential -Message $message
    }
    
    export-credentials $container $cred -dir $cacheDir
    return $cred
}

function Remove-CredentialsCached($container) {
    $cacheDir = "pscredentials"
    remove-cache $container -dir $cacheDir
}