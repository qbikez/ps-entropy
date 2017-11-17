<#

.SYNOPSIS
.DESCRIPTION
.PARAMETER CN 
CommonName for the new certificate
.PARAMETER OpenSsl
Use OpenSSL to generate certificates (usefull for custom extensions)
.PARAMETER SelfSigned
Generate a self-signed certificate
.PARAMETER ClientAuth (default = true)
Use this certificate for Client-side authentication
.PARAMETER ServerAuth
Use this certificate for Server-side authentication
.PARAMETER ca
The name of Certificate Authority that will sign this certificate (reqires a private key file)
.PARAMETER pass
Use this password to protect the new certificate
.EXAMPLE
.\New-Cert.ps1 my-apiclient -ca legimiCA -ClientAuth
.NOTES
XXX
#>
function New-Cert {
param(
[parameter(mandatory=$true)]
[string] $CN,
[switch]
[bool] $OpenSsl = $false,
[switch]
[bool] $selfSigned = $false,
[switch][bool] $ClientAuth = $true,
[switch][bool] $RootAuth = $false,
[switch][bool] $ServerAuth = $false,
[string] $ca = $null,
[string] $pass = "",
[switch]
[bool] $force,
$days = 365
)

    ipmo require
    req process

    $basedir = "${env:ProgramFiles(x86)}\Windows Kits\8.1\bin\x64"
    $env:Path = "$env:Path;$basedir"


    $useOpenssl = $OpenSsl

    $certName = $CN.Replace("*", "wildcard")

    $clientAuth = !$ServerAuth


    $EKUServerAuth = "1.3.6.1.5.5.7.3.1"
    $EKUClientAuthentication = "1.3.6.1.5.5.7.3.2"

    $EKU = $EKUClientAuthentication
    $openssl_eku = "clientAuth"
    $openssl_ext = "usr_cert"
    if ($ServerAuth) { 
        $EKU = $EKUServerAuth
        $openssl_eku = ""
        $openssl_ext = "server"
    }

    if ([string]::IsNullOrEmpty($ca)) {
        if (!$selfSigned -and !$rootauth) {
            throw "no ca name given. If you wat to generate a self-signed certificate, use -SelfSigned switch. otherwise, use -CA to pass ca name"
        }
    }

    if (!$useOpenssl) {
        if ([string]::IsNullOrEmpty($ca)) {
            if (!$selfSigned) {
            }
            if ($RootAuth) {
                write-host ">>> makecert root self-signed"
                makecert -r -pe -n "CN=$CN" -cy authority -sv "$certName.pvk" "$certName.cer" 
            } else {
                write-host ">>> makecert self-signed"
                makecert -r -pe -n "CN=$CN" -eku "$EKU" -sky exchange -sv "$certName.pvk" "$certName.cer" 
            }
        }
        else {  
            if (!(test-path "$ca.cer") -or !(test-path "$ca.pvk")) {
                throw "Certificate Authirity key files ($ca.cer or $ca.pvk) not found!"
            }
            write-host ">>> makecert sign with $ca.pvk"
            $r = invoke makecert.exe "-pe" "-n" "CN=$CN" "-a" sha1 -sky exchange -eku $EKU -ic "$ca.cer" -iv "$ca.pvk" `
                -b 01/01/1970 "-sp" "Microsoft RSA SChannel Cryptographic Provider" -sy 12 `
                -sv "$certName.pvk" "$certName.cer" -passthru -verbose -is my
        if ($LASTEXITCODE -ne 0 -or $r -contains "error") {
                throw $r
        }
        }

        $args = @{ }
        if ([string]::IsNullOrEmpty($pass)) {
            pvk2pfx -pvk "$certName.pvk" -spc "$certName.cer"  -pfx "$certName.pfx"
        }
        else {
            pvk2pfx -pvk "$certName.pvk" -spc "$certName.cer" -pfx "$certName.pfx" -po $pass
        }
    }
    else {    

        if (test-path "openssl.config") { remove-item "openssl.config" }
        copy "$psscriptroot\_openssl.config" openssl.config -ErrorAction stop
        $lines = (get-content "openssl.config") 
        $lines = $lines | % { $_ -replace "\{cn\}", "$CN" }          
        $lines = $lines | % { $_ -replace "\{openssl_eku\}", "$openssl_eku" }
        [System.IO.File]::WriteAllLines((Get-Item "openssl.config").FullName, $lines, (New-Object System.Text.UTF8Encoding($False)))

        if ($RootAuth) {
            if (!(test-path "$cn.key") -or $force) {
                write-host ">>> genrsa"
                $a = @()
                if (![string]::IsNullOrEmpty($pass)) {
                    $a += "-aes256"
                }
                invoke openssl genrsa "-out" "$cn.key" 4096
            }
            write-host ">>> self-sign CA"
            invoke openssl req -new -x509 -days 365 -key "$cn.key" -sha256 "-out" "$cn.pem" -config .\openssl.config
            return
        }

        
        if (!(test-path "$cn.key") -or $force) {
        write-host ">>> genrsa"
        if ([string]::IsNullOrEmpty($pass)) {
                $pass = "123"
                try {
                    invoke openssl genrsa -des3 "-out" "$certName.key" -passout "pass:$pass" 2048
                    invoke openssl rsa "-in" "$certName.key" "-out" "$certName.key" -passin "pass:$pass"
                } finally {
                    $pass = ""
                }
            } else 
            {
                invoke openssl genrsa -des3 "-out" "$certName.key" -passout "pass:$pass" 2048 
            }
        }

        write-host ">>> newreq"
        invoke openssl req -new -newkey rsa:2048 -key "$certName.key" "-out" "$certName.csr" -config .\openssl.config -passin "pass:$pass"  -extensions $openssl_ext

        write-host ">>> x509 sign"
        if ($selfSigned) {    
            invoke openssl req -x509 -newkey rsa:2048 -key "$certName.key" "-out" "$certName.pem" -days 365  -extensions $openssl_ext -config .\openssl.config
        }
        else {            
            $a = @()
            if (![string]::IsNullOrEmpty($pass)) {
                $a += "-passin","$pass"
            }
            if ($serverauth) {
                $a += "-CAcreateserial"
            }
            invoke openssl x509 -req "-in" "$certName.csr" -CA "$ca.pem" -CAkey "$ca.key"  "-out" "$certName.pem" -trustout -extfile .\openssl.config -extensions $openssl_Ext -days $days $a #-extfile .\openssl.config 
        }
        #openssl ca -in "$certName.csr" -keyfile "legimica.key" -out "$certName.pem"  -cert "legimica.pem"  
        #-CAcreateserial 
        write-host ">>> x509 pem -> der"
        invoke openssl x509 -outform der "-in" "$certName.pem" "-out" "$certName.der" 
        write-host ">>> pkcs12 pem + key -> pfx"
        invoke openssl pkcs12 -export "-out" "$certName.pfx" -inkey "$certName.key" "-in" "$certName.pem" -password "pass:$pass" -passin "pass:$pass"   
    }


    # https://www.ssllabs.com/ssltest/analyze.html?d=legimi.pl&hideResults=on
    # https://www.sslshopper.com/article-how-to-disable-ssl-2.0-in-iis-7.html
}