function Copy-RemoteFile {
    [CmdletBinding()]
    param($source, $target, $tosession, [switch][bool]$recurse, [switch][bool]$force) 
    
    if ((get-item $source).psiscontainer) {
        $recurse = $true    
    }
    if ($recurse -and (get-item $source).psiscontainer) {
        $force = $true
    }
    if (!$recurse -and ($target.EndsWith("/") -or $target.EndsWith("\"))) {
        $target = join-path $target (split-path -leaf $source)
    }
    $hash = $null
    if (!$recurse) { 
        $hash = @(@{
            Hash = (Get-FileHash $source).Hash
            FullName = $source.fullname
            RelativePath = $source
        })
    }
    else {
        $hash = get-childitem $source -Recurse -File | % {
            @{ 
                Hash = (get-filehash $_.FullName).Hash
                FullName = $_.fullname
                RelativePath = Get-PathRelative -from $source -to  $_.FullName
            }
        }
    }
    
    $a = @{}
    if ($tosession -ne $null) { $a.Session = $tosession }
    $srvInfo = icm `
    -ArgumentList @(@{
        FullName = $target
        Hash = $hash
        Recurse = $recurse
    }) `
    -ScriptBlock {
        param($p)
        if ($p.recurse) { $dir = $p.fullname } 
        else { $dir = split-path $p.FullName }
        if (!(test-path $dir)) { $null = mkdir $dir }

        if ($p.hash -ne $null -and (Test-Path $p.fullname)) {
            if ($p.psiscontainer) {                
                return get-childitem $source -Recurse -File | % {
                    @{ 
                        Hash = (get-filehash $_.FullName).Hash
                        FullName = $_.fullname
                        RelativePath = $_.FullName.Replace($dir, "")
                    }
                } 
            }   
            else {         
                $srvHash = Get-FileHash $p.fullname
                return @(@{ 
                    Hash = $srvHash.Hash
                    FullName = $p.fullname
                    RelativePath = $p.FullName.Replace($dir, "")
                })
            }            
            
        }
        return @(@{ 
            Hash = $null
            FullName = $p.fullname
        })
    } `
    -ErrorAction Stop @a
    
    $localfiles = $hash
    $remotefiles = $srvInfo
    foreach($f in $localfiles) {
        $srvInfo = $remotefiles | ? { $_.RelativePath -eq $f.RelativePath }
        if ($srvInfo -ne $null) { $srvHash = $srvInfo.Hash }
        $hash = $f.Hash
        $a = @{}
        if ($tosession -ne $null) { $a.ToSession = $tosession }
        if ($srvHash -eq $null -or $srvHash -ne $hash) {
            $targetDir = (join-path $target (split-path -parent $f.RelativePath))
            write-verbose "file hashes differ: local($hash) != remote($srvhash) for file $source -> $($srvinfo.fullname)"
            if ($targetDir -ne $target) {
                invoke-command -session $tosession -ScriptBlock { if (!(test-path $using:targetDir)) { $null = mkdir $using:targetDir } }
            }
            cp -LiteralPath $f.Fullname -destination $targetDir @a -Recurse:$recurse -Force:$force -Container:$recurse -ErrorAction Stop -Verbose:($VerbosePreference -eq "Continue")
        } else {
            write-verbose "skipping unmodified file $source"
        }
    }
}
