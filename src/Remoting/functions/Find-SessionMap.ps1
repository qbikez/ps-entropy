function Find-SessionMap {
[CmdletBinding()]
param ([switch][bool] $reload = $true) 
     if ($Global:psSessionsMap -eq $null -or $reload) {
        write-verbose "looking for psSessionsMap"
        $searchdirs = "$home\Documents\WindowsPowerShell","$home\Documents","$(_get-syncdir)","$(_get-syncdir)\Documents" | ? { ![string]::IsNullOrEmpty($_) }
        $searchfiles = "pssessionmap.json","sessionmap.config.ps1"
        $searchPaths = $searchfiles | % { $f = $_; $searchdirs | % { join-path $_ $f } }
        foreach($p in $searchPaths) {
            if (test-path $p) {
                write-verbose "found sessionmap at $p"
                if ([System.IO.Path]::GetExtension($p) -eq ".json") {
                    ipmo publishmap -Verbose:$false -ErrorAction Stop
                    $map = get-content $p | convertfrom-json
                    if ($map -isnot [hashtable]) {
                        $map = ConvertTo-Hashtable $map
                        #  ConvertTo-Hashtable -recurse would also convert leaf strings into hashtables
                        $keys = $map.keys | % { $_ }
                        foreach($k in $keys) {
                            $map[$k] = ConvertTo-Hashtable $map[$k]
                        }
                    }
                }
                if ([System.IO.Path]::GetExtension($p) -eq ".ps1") {
                    $map = . $p
                }
                if ($map -ne $null) {
                    $Global:psSessionsMap = $map
                    $Global:psSessionsMapPath = $p
                    break
                }                
            }
        }
    } else {
        write-verbose "global session map exists. NOT looking for sessionmap.ps1"
    }
    
    return $Global:psSessionsMap
}

function find-rdp {
param($name)

$searchPAths = "$home\Documents\WindowsPowerShell\rdp","$home\Documents\rdp","$home\rdp","$(_get-syncdir)\rdp","$(_get-syncdir)\Documents\rdp"
        foreach($p in $searchpaths) {
            $p = join-path $p "$name.rdp"
            if (test-path $p) {
                write-verbose "found rdp file at $p"
                return $p
            }
        }
    
}