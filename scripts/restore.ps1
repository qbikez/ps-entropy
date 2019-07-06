install-module require

import-module require
req process
req cache
req publishmap

Install-Module Pester -MinimumVersion 4.4 -Force # TODO: switch back to req when it supports '-Force'

$restoreScripts = get-childitem "$psscriptroot/.." -directory -Exclude "scripts" | % { get-childitem $_ -Filter "restore.ps1" }

foreach($script in $restoreScripts) {
    pushd 
    try {
        write-host $script.fullname
        cd (split-path -parent $script.fullname)
        & $script.fullname
    } finally {
        popd
    }
}