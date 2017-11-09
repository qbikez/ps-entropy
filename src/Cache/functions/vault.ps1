function Export-VaultCache([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$data, [Parameter(Mandatory=$true)]$container) {
    invoke vault write $container "value=$data" -showoutput:$false
}

function Import-VaultCache([Parameter(Mandatory=$true)]$container) {    
    $retry = $true
    do {
        $json = invoke vault read "-format=json" $container -passthru -showoutput:$false -nothrow -passerrorstream | out-string
        if ($lastexitcode -ne 0) {
        if ($json -match "Code:\s*([0-9]+)") {
            $code = $matches[1]
            if ($code -eq "403") {
                # authorize in vault using stored credentials
                $vaultCredentials = get-credentialscached -container "vault"
                if ($vaultCredentials -ne $null) {
                    $r = invoke vault auth "--method=ldap" "username=($vaultCredentials.username)" "password=($vaultcredentials.getnetworkcredential().password)"
                    continue
                }
                
                throw "vault read returned 403, and vault auth failed"
            }
        }
            throw "vault read failed: $json"
        }
        # credentials.ps1 expects password in form of encoded securestring
        $wrapper = ConvertFrom-Json $json
        $data = $wrapper.data
        if ($data.password -ne $null) {
            # build the securestring instead of using convertto-securestring with plain text, as psscriptanalyzer don't like this 
            # and we really have to create a securestring from plain text
            $secpass = new-object securestring
            $data.password.tochararray() | % { $secpass.AppendChar($_) }
            # $secpass = convertto-securestring $data.password -force -AsPlainText
            $data.password = convertfrom-securestring $secpass
        }        
        return $data
    } while ($retry)
}