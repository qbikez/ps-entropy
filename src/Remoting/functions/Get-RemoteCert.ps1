function Get-RemoteCert {
[cmdletbinding()]
param
(
[parameter(Mandatory=$true)][string]$computername,
[parameter(Mandatory=$false)]$port = 443,
$outfile,
[switch][bool]$accept,
$certstorelocation
)

	if ($port -in "powershell","rps","winrm") {
		$port = 5986
	}
    write-host "connecting to $computername on port $port"
	$tcpsocket = $null
    try {
	    #Create a TCP Socket to the computer and a port number
	    $tcpsocket = New-Object Net.Sockets.TcpClient($computerName, $port)
    } catch {
        write-error $_
    }

	#test if the socket got connected
	if(!$tcpsocket)
	{
		throw "Error Opening Connection: $port on $computername Unreachable"
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

        
        if ($accept -and $outfile -eq $null) {
            $outfile = "$computername.crt"
        }
        if ($outfile -ne $null) {
            $certinfo | Export-Certificate -FilePath $outfile -Verbose
        }

        if ($accept) {
        if ($certstorelocation -eq $null) {
           $certstorelocation = "Cert:\CurrentUser\Trust"
        }
            Import-Certificate $outfile -CertStoreLocation $certstorelocation
        }

		return $certinfo
	}

}
