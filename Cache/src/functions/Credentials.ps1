
function Export-Credentials([Parameter(Mandatory=$true)]$container, $cred, [Alias("dir")]$cacheDir = "pscredentials") {
    $pass = $null
    if ($cred.password -eq $null) {
        throw "missing password"
    }
    if ($cred.password -is [SecureString]) {
        $pass = $cred.Password | convertfrom-securestring
    }
    elseif ($cred.password -is [string]) {
        throw "expected password as securestring"
    }
    else {
        throw "don't know how to handle password with type '$($cred.password.gettype().name)'"
    }
    $result = New-Object -TypeName pscustomobject -Property @{ Password = $pass; Username = $cred.UserName }
    export-cache $result -container $container -dir $cacheDir
}

function Import-Credentials([Parameter(Mandatory=$true)] $container, [Alias("dir")]$cacheDir = "pscredentials") {
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
    param([Parameter(Mandatory=$true)]$container, $message, [switch][bool] $allowuserUI, [switch][bool]$secure, [switch][bool]$reset = $false) 
        
        $cacheDir = "pscredentials"
        try {
            $cred = $null
            if (!$reset) {
                $cred = import-credentials $container -dir $cacheDir
            }
            if ($cred -eq $null) { 
                write-verbose "password not found for container '$container'"
                if ($allowuserUI) {
                      $cred = Get-CredentialsCached -container $container -message $message -reset:$reset
                } else {
                    write-verbose "allowuserUI=$allowuserUI. not asking for credentials"
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
param([Parameter(Mandatory=$true)]$container, $message, [switch][bool]$reset = $false, [switch][bool] $noprompt) 

    $cred = $null
    $cacheDir = "pscredentials"
    if ($reset) {
        Remove-CredentialsCached $container
    }
    if (!$reset) {
        try {
            $cred = import-credentials $container -dir $cacheDir
        } catch {
            write-error "failed to import credentials from container '$container': $($_.exception.message)"
        }
    } else {
        write-verbose "resetting credentials in container '$container'"
    }    
    if ($cred -eq $null) {
        write-verbose "cached credentials not found in container '$container'"
        
        if ($message -eq $null) {
            $message = "Please provide credentials for '$container'"
        }
        if ($global:promptpreference -ne 'SilentlyContinue' -and !$noprompt) {
            import-module Microsoft.PowerShell.Security -verbose:$false
            $cred = Microsoft.PowerShell.Security\Get-Credential -Message $message
        }
        else {
            write-verbose "promptpreference=$($global:promptpreference). not asking for credentials"
            return $null
        }

        # store aquired credentials
        export-credentials $container $cred -dir $cacheDir
    }
    return $cred
}

function Remove-CredentialsCached([Parameter(Mandatory=$true)]$container) {
    $cacheDir = "pscredentials"
    remove-cache $container -dir $cacheDir
}