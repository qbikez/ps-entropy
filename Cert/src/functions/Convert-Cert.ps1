function Convert-Cert {
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $certName,
    [Parameter(Mandatory=$false)][string] $pass = "",
    [Parameter(Mandatory=$false)] $newpass = $null,
    [switch][bool] $public,
    [switch][bool] $priv,
    [Alias("outformat")]
    [ValidateSet("der","pem")]
    $format = "der"
)
    ipmo require
    req process

    $verbose = $VerbosePreference -eq "Continue"

    if ($public -eq $false -and $priv -eq $false) {
        write-warning "please choose one switch: -priv or -public"
        return
    }

    if ($certName.endswith(".key")) {
        $certName = $certName -replace ".key", ""
    }
    if ($certName.endswith(".pem")) {
        $certName = $certName -replace ".pem", ""
    }
    if ($certName.endswith(".pfx")) {
        $certName = $certName -replace ".pfx", ""
    }
    if ($certName.endswith(".cer")) {
        $certName = $certName -replace ".cer", ""
    }
    if ($newpass -eq $null) {
        write-verbose "new pass same as old one"
        $newpass = $pass
    }

    $der = "der"
    if (!(test-path "$certName.$der") -and (test-path "$certName.cer")) { $der = "cer" }
    if ($format -eq "der") {
        if ($public) {
            write-host "converting PUBLIC cert '$certName.pem' to '$certName.$der'"
            invoke openssl x509 -outform der "-in" "$certName.pem" "-out" "$certName.$der" -verbose:$verbose
        }
        elseif ($priv) {
            write-host "converting PRIVATE cert '$certName.pem' to '$certName.pfx', using private key from '$certName.key'"
            invoke openssl pkcs12 -nodes -export "-out" "$certName.pfx" -inkey "$certName.key" "-in" "$certName.pem" -password "pass:$newpass"  -passin "pass:$pass" -verbose:$verbose 
            write-host "converting PRIVATE cert '$certName.pem' to '$certName.pvk"
            invoke openssl rsa "-in" "$certName.key" -outform PVK -pvk-strong "-out" "$certName.pvk" -passout "pass:$newpass" -passin "pass:$pass" -verbose:$verbose
        }
    } elseif ($format -eq "pem") {
        if ($public) {
            write-host "converting PUBLIC cert '$certName.$der' to '$certName.pem'"
            invoke openssl x509 "-inform" der "-in" "$certName.$der" "-out" "$certName.pem" -verbose:$verbose
        }
         elseif ($priv) {
            write-host "converting PRIVATE cert '$certName.pfx' to '$certName.key' and '$certname.pem'"
            invoke openssl pkcs12 "-in" "$certname.pfx" "-out" "$certname.key" -nodes -password "pass:$newpass" -passin "pass:$pass" -verbose:$verbose
            invoke openssl pkcs12 "-in" "$certname.pfx" -nokeys "-out" "$certname.pem" -passin "pass:$pass" -verbose:$verbose
        }
    }
    else {
        throw "unrecognized format '$format'. try 'pem' or 'der'"
    }
 
}