function Find-SessionMap {
[CmdletBinding()]
param ([switch][bool] $reload = $true) 
     if ($Global:psSessionsMap -eq $null -or $reload) {
        write-verbose "looking for sessionmap.ps1"
        $searchPAths = "$home\Documents\WindowsPowerShell\sessionmap.config.ps1","$home\Documents\sessionmap.config.ps1","$home\sessionmap.config.ps1","$(_get-syncdir)\sessionmap.config.ps1","$(_get-syncdir)\Documents\sessionmap.config.ps1"
        foreach($p in $searchpaths) {
            if (test-path $p) {
                write-verbose "found sessionmap at $p"
                $map = . $p
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