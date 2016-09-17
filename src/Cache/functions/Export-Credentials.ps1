
function export-credentials($cacheDir, $contaier, $cred) {
    $result = New-Object -TypeName pscustomobject -Property @{ Password = $cred.Password | ConvertFrom-SecureString; Username = $cred.UserName }
    export-cache $cacheDir $container $result
}

function import-credentials($cacheDir, $contaier) {
    $lastcred = import-cache $cacheDir $container
    if ($lastcred -ne $null) {
        $password = $lastcred.Password | ConvertTo-SecureString
        $username = $lastcred.Username
        $cred = New-Object System.Management.Automation.PsCredential $username,$password
    }

    return $cred
}

function Get-PasswordCached {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$container, $message, [switch][bool] $allowuserUI) 
        
    $cacheDir = "pscredentials"
        try {
            $cred = import-credentials $cacheDir $container
            if ($cred -eq $null) { 
                if ($allowuserUI) {
                      $cred = Get-CredentialsCached -container $container -message $message
                } else {
                    return $null 
                }
            }
            return $cred.GetNetworkCredential().Password
        } catch {            
            throw
            return $null
        }
}

function Get-CredentialsCached {
[CmdletBinding()]
param([Parameter(Mandatory=$true)]$container, $message, $reset = $false) 

    $cred = $null
    $cacheDir = "pscredentials"
    if (!$reset) {
        try {
        $cred = import-credentials $cacheDir $container
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
    
    export-credentials $cacheDir $container $cred
    return $cred
}

function Remove-CredentialsCached($container) {
    $cacheDir = "pscredentials"
    remove-cache $cacheDir $container
}