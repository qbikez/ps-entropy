function Get-RemoteCert {
[CmdletBinding()]
param (
[parameter(Mandatory=$true)][string]$computername,
[parameter(Mandatory=$false)]$port = 443,
[switch][bool] $accept = $false
)

    if ($port -in "powershell","rps","winrm") {
        $port = 5986
    }

    function Get-RemoteCert
    (
    [parameter(Mandatory=$true)][string]$computername,
    [parameter(Mandatory=$false)][int]$port = 443
    )
    {
    #Create a TCP Socket to the computer and a port number
    $tcpsocket = New-Object Net.Sockets.TcpClient($computerName, $port)

    #test if the socket got connected
    if(!$tcpsocket)
    {
        Write-Error "Error Opening Connection: $port on $computername Unreachable"
        exit 1
    }
    else
    {
        #Socket Got connected get the tcp stream ready to read the certificate
        write-host "Successfully Connected to $computername on $port" -ForegroundColor Green -BackgroundColor Black
        $tcpstream = $tcpsocket.GetStream()
        Write-host "Reading SSL Certificate...." -ForegroundColor Yellow -BackgroundColor Black
        #Create an SSL Connection
        $sslStream = New-Object System.Net.Security.SslStream($tcpstream,$false, {
            param($sender, $certificate, $chain, $sslPolicyErrors) 
            return $true
        })
        #Force the SSL Connection to send us the certificate
        $sslStream.AuthenticateAsClient($computerName)

        #Read the certificate
        $certinfo = New-Object system.security.cryptography.x509certificates.x509certificate2($sslStream.RemoteCertificate)
        return $certinfo
    }
    }

    $cert = Get-RemoteCert $computername $port

    if ($accept) {
        $cert | Export-Certificate -FilePath "tmp.cer"
        Import-Certificate -FilePath "tmp.cer" -CertStoreLocation Cert:\CurrentUser\Root
    }

    return $cert

}