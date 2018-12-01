$msdeploy = "$env:ProgramFiles\IIS\Microsoft Web Deploy V3\msdeploy.exe"
Import-Module process

#region public

function Test-MsDeploy($server, $credential) {
    $cmd = { 
        write-host "Im user '$env:username' on server '$env:hostname'!" 
    }

    if ($credential -eq $null) {
        req cache
        $credential = get-credentialscached $server
    }

    # $url = get-msdeployComputername $server
    # $enc = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($credential.username):$($credential.getnetworkcredential().password)"))
    # $h = @{ Authorization = "Basic $enc" }
    
    # Invoke-WebRequest $url -Headers $h -UseBasicParsing -ErrorAction stop

    run-msdeploycommand -server $server `
                -command $cmd `
                -scriptMode -waitInterval 1000 -waitAttempts 600 -credential $credential 
}

function Copy-MsDeployFile {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        $server, 
        [Parameter(Mandatory=$true)]
        $source, 
        [Parameter(Mandatory=$true)]
        [Alias("destination")]
        $targetpath, 
        [switch][bool]$deleteObsoleteItems, 
        $credential
    ) 

    foreach($f in @($source)) {
        $filename = [System.IO.Path]::GetFileName($f)        
        $srcIsDir = [System.IO.Directory]::Exists($f) -or $filename -eq "*"
        $dstIsDir = $targetpath.EndsWith("\") -or $targetpath.EndsWith("/") 

        if ($srcIsDir) {
            if (!$dstIsDir) {
                throw "cannot copy directory to file"
            }
            $fullTargetPath = $targetpath 
            $fullSourcePath = [System.IO.Path]::GetDirectoryName($f)
        } else {
            if ($dstIsDir) {
                $fullTargetPath = [System.IO.Path]::Combine($targetpath, $filename)
            }
            else {
                $fullTargetPath = $targetpath
            }
            
            $fullSourcePath = $f
        }

        $fullSourcePath = (get-item $fullSourcePath).FullName
        
        $l = msdeploy -verb sync `
            -source:(get-msdeploypath -provider contentPath -path $fullSourcePath) `
            -dest (get-msdeploypath -provider contentPath -server $server -path $fullTargetPath -credential $credential) `
            -skip:(get-skiprules $deleteObsoleteItems) `
            -useChecksum `
            -showOutput
    }
}

function Get-MsDeployFile
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($server, $source, [Parameter(Mandatory=$true)]$outputDir, [switch][bool]$deleteObsoleteItems, $credential) 
    
    $path = $source
    if (!(test-path $outputdir)) {
        $null = mkdir $outputdir
    }
    #$provider = "file"
    $provider = "contentPath"
    if ($iisapp -ne $null) {
        $root = get-msdeployphysicalPath -server $server -iisapp $iisapp -credential $credential
        $path = [System.IO.Path]::Combine($root, $path)
    }

    $dstIsDir = $true#[System.IO.Directory]::Exists($f) -or $filename -eq "*"
    
    foreach($f in @($path)) {
        $srcIsDir = $path.EndsWith("\") -or $path.EndsWith("/") 
        $filename = [System.IO.Path]::GetFileName($f)

        $targetPath = (get-item $outputdir).FullName 
        if (!$srcIsDir -or $true) {
            $targetPath = (join-path (get-item $outputdir).FullName $filename)
        }
        
        $l = msdeploy -verb sync `
            -source:(get-msdeploypath -provider $provider -server $server -path $f -credential $credential) `
            -dest (get-msdeploypath -provider $provider -path $targetPath) `
            -skip:(get-skiprules $deleteObsoleteItems) `
            -useChecksum `
            -showOutput
        write-output $targetPath
    }
}

function Invoke-MsDeployCommand($command, $server, $credential, [switch][bool]$scriptMode, $waitInterval = 60000, $waitAttempts = 10) {
    if ($scriptMode) {
        $tempDir = "c:\TEMP\"

        $guid = [system.guid]::newGuid()
        $null = mkdir "$env:Temp/$guid"
        $tmp = "$env:Temp/$guid/$guid.ps1"
        $tmpfile = "$tempDir\$guid.ps1"
        $command = "try { `$ErrorActionPreference = `"Stop`";`r`n" + $command + "`r`n } finally { rm '$tmpfile' }"
        $command | out-file $tmp -encoding UTF8
        #$tmp = "$env:Temp/$guid/$guid.bat"
        #"powershell -NonInteractive -NoProfile -File $tempDir\$guid.ps1" | out-file $tmp -encoding UTF8
        #$command = "$tempDir\$guid.bat"
        $command = "powershell -NonInteractive -NoProfile -File $tmpfile"

        Upload-MsDeployFile -server $server -source "$env:Temp\$guid\" -targetPath $tempDir 
    }
    
    $additionalDestArgs=@()
    if ($waitInterval -ne $null) {
        $additionalDestArgs += "waitInterval=$waitInterval"
    }
    if ($waitAttempts -ne $null) {
        $additionalDestArgs += "waitAttempts=$waitAttempts"
    }
    #$command = "`'$command`'"
    $r = msdeploy -verb sync `
        -source runCommand `
        -dest (get-msdeploypath -provider runCommand -server $server -path $command -credential $credential -additionalArgs $additionalDestArgs) `
        -skip:(get-skipRules) `
        -showoutput `
        -verbose
    
    $lastLines = $r | select -Last 2
    $exitCode = $lastLines | % { if ($_ -match "code '([0-9A-Fx]+)'") { $Matches[1] } }
    if ($exitCode -ne "0x0") {
        throw "remote Command failed: exitcode='$exitCode'"
    }
}

function Get-MsDeployFiles($server, $path, $credential) {
    $l = msdeploy -verb dump `
        -source:(get-msdeploypath -provider contentPath -server $server -path $path -credential $credential)
    return $l
}

function Invoke-MsDeploy {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        $verb, 
        $source, $dest, 
        $skip,
        [switch][bool] $useChecksum, 
        [switch][bool] $showOutput
    )
    $a = @()
    if ($verb -ne $null) {
        $a += "-verb:$verb" 
    }
    if ($source -ne $null) {
        $a += "-source:$source"
    }
    if ($dest -ne $null) {
        $a += "-dest:$dest"
    }
    if ($useChecksum) {
        $a += "-usechecksum"
    }
    if ($skip -eq $null) {
        # don't delete remote files by default
        $skip = get-skipRules
    }
    if ($skip -ne $null) {
        @($skip) | % { $a += "-skip:$_" }
        
    }
    
    # ignore invalid https certificates
    $a += "-allowUntrusted"
    $verbose = $true
    $r = invoke $msdeploy $a -passthru -showoutput:$showOutput -nothrow -Verbose:$verbose
    if ($LASTEXITCODE -ne 0) {
        if ($r -ne $null) {
            $r | % { write-warning $_ }
        }
        throw "msdeploy failed with EXITCODE=$lastExitCode"
    }

    return $r
}

#endregion

#region private

function get-skipRules([switch][bool]$deleteObsoleteItems = $false) {
    $skip = @()
    if (!$deleteObsoleteItems) {
        $skip += @("skipaction=Delete,objectname=dirPath", "skipaction=Delete,objectname=filePath")
    }

    return $skip
}

function get-msdeployComputername($server,[int]$port=80) {
    return "http://$($server):$port/MSDEPLOYAGENTSERVICE"
}

function get-msdeploypath($provider, $path, $server, $additionalArgs, $credential) {
    $a = @()
    $a += "$provider=`"$path`""

    if ($server -ne $null) {
        if ($credential -eq $null -and (gmo cache -erroraction Ignore)) {
            $credential = Get-CredentialsCached "$server"
        }
        if ($credential -eq $null) {
            throw "missing credentials"
        }
        $a += "computername=" + (get-msdeployComputername $server)
    }

    if ($credential -ne $null) {
        if ($credential -is "String") {
            $a += $credential
        }
        else {
            $username = $credential.username
            $password = $credential.GetNetworkCredential().Password
            $a += "username=$username"
            $a += "password=$password"
            #$a += "AuthType='Basic'"
        }
    }

    if ($additionalArgs -ne $null) {
        $a += @($additionalArgs)
    }

    return [string]::Join(",", $a)

}



function get-msdeployphysicalPath($server, $iisapp, $credential) {
    $r = msdeploy -verb dump -source (get-msdeploypath -provider appHostConfig -path "$iisapp/" -server $server -credential $credential) -credential $credential

    $found = $false
    foreach($line in @($r)) {
        if ($found) {
            return $line
        }
        if ($line.Contains("application[@path='/']/virtualDirectory[@path='/']")) {
            $found = $true
            # the next line will contains physical path value
            continue
        }
    }

    throw "Could not determine physical path"
} 

function add-ext($f, $suffix) {
    $filename = [System.IO.Path]::GetFileNameWithoutExtension($f)
    $ext = [System.IO.Path]::GetExtension($f)
    $newname = "$filename$suffix$ext"
    $dir = split-path -parent $f

    return join-path $dir $newname

}

#endregion

#region aliases

new-alias msdeploy Invoke-MsDeploy -force
new-alias Download-MsDeployFile Get-MsDeployFile -force
new-alias Upload-MsDeployFile Copy-MsDeployFile -force
new-alias List-MsDeployFiles Get-MsDeployFiles -force
#endregion