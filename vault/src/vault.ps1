function Login-VaultAccount {
    param($server = $env:VAULT_ADDR, $credential) 

    if ($credential -eq $null) {
        $credential = get-credential -message "Enter your Active Directory credential"
    }
    
    $username = $credential.username
    $password = $credential.GetNetworkCredential().Password

    $url = "$server/v1/auth/ldap/login/$username"
    
    $body = "{`"password`": `"$password`"}"

    $r = invoke-webrequest -Method Post -Uri $url -UseBasicParsing -Body $body

    $c = $r.Content | convertfrom-json
    $token = $c.auth.client_token
    $env:VAULT_TOKEN = $token
    $env:VAULT_ADDR = $server
    # auth_header = @{'X-Vault-Token'=$Token}
}

function Get-VaultSecret {
    param($path, $token, $server = $null)

    if ($token -eq $null) {
        $token = $env:VAULT_TOKEN
    }
    if ($server -eq $null) {
        $server = $env:VAULT_ADDR
    }
    
    $url = "$server/v1/$path"
    write-verbose "url: $url token: $token" -Verbose
    $r = Invoke-RestMethod -Uri $url -Headers @{'X-Vault-Token'=$token}
    return $r
}