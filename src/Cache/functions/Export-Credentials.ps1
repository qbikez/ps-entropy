
function export-credentials([Parameter(Mandatory=$true)]$container, $cred, [Alias("dir")]$cacheDir = "pscredentials") {
    $pass = $null
    if (![string]::isnullorempty($cred.Password)) { 
        $pass = $cred.Password | ConvertFrom-SecureString
     }
    $result = New-Object -TypeName pscustomobject -Property @{ Password = $pass; Username = $cred.UserName }
    export-cache $result -container $container -dir $cacheDir
}

function import-credentials([Parameter(Mandatory=$true)] $container, [Alias("dir")]$cacheDir = "pscredentials") {
    $lastcred = import-cache $container -dir $cacheDir
    if ($lastcred -ne $null) {
        if (![string]::isnullorempty($lastcred.Password)) {
            $password = $lastcred.Password | ConvertTo-SecureString
            $username = $lastcred.Username
            $cred = New-Object System.Management.Automation.PsCredential $username,$password
        }
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
        if ($global:promptpreference -ne 'SilentlyContinue') {
            $cred = Get-Credential -Message $message
        }
        else {
            return $null
        }
    }
    
    export-credentials $container $cred -dir $cacheDir
    return $cred
}

function Remove-CredentialsCached($container) {
    $cacheDir = "pscredentials"
    remove-cache $container -dir $cacheDir
}