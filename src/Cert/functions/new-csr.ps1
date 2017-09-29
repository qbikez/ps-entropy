function New-CSR {
param(
    [Parameter(Mandatory=$true)]$name = "orange.legimi.com", 
    [Parameter(Mandatory=$true)]$organization_name = "orange.legimi.com", 
    [Parameter(Mandatory=$true)]$email = "legimi@legimi.com", 
    [switch][bool]$force
)

function Import-INIFile {
    [CmdletBinding()]Param(
        [Parameter(Mandatory,Position=0)]
        [ValidateScript({Test-Path $_})]
        [String]
        $Path
    )
 
    $resultINI = @{}
     
    try {
        switch -regex -file $Path {
            '^#'        {
                continue 
            }
 
            '^\[(.+)\]$' {
                $header = $matches[1]
                $resultINI.Add($header,@{})
            }
 
            '(.+)=(.+)'   {
                $key = $matches[1].trim()
                $value = $matches[2].trim()
                $resultINI[$header].Add($key,$value)
            }
        }
    }
    catch {
        Write-Error -ErrorAction STOP -Message ('Unable to open INI file {0}: {1}' -f $Path,$_.exception.message)
    }
 
 
    Write-Output $resultINI

}


push-location
try 
{
    
    cd $PSScriptRoot

    $dirname = $name -replace "\*","wildcard"
    

    $key =  ".\cert\$dirname\$dirname.key"
    $csr =  ".\cert\$dirname\$dirname.csr"
    $cfgtemplate = "newcert.default.config"
    #$(Import-IniFile -File $cfgtemplate | out-string)
    $cfg = get-content $cfgtemplate
    $cfg = $cfg | % {
        $l = $_ -replace "\{name\}",$name -replace "\{email\}",$email -replace "\{organization_name\}",$organization_name
        return $l
    }
    
    $cfgfile = ".\cert\$dirname\$dirname.cert.config"

    if (test-path $cfgfile) {
        remove-item $cfgfile
    }

     if (!(test-path (split-path -parent $key))) {
        new-item -type directory (split-path -parent $key)
    }

    $enc = (New-Object System.Text.UTF8Encoding($False))
    $path = join-path $PSScriptRoot $cfgfile
    [System.IO.File]::WriteAllLines($path, $cfg, $enc)

    $cfg = $(Import-IniFile $cfgfile | out-string)


   
    if (!(test-path $key) -or $force) {
        if ((test-path $key)) {
            remove-item $key
        }
        write-host "Generating key file: $key"
        openssl genrsa -out $key 2048
    }
    write-host "Generating CSR: $csr"
    write-host "Using config: $cfgfile"
    if ((test-path $csr)) {
            remove-item $csr
        }
    openssl req -new -sha256 -key $key -out $csr -config $cfgfile
} 
finally {
    pop-location
}
}