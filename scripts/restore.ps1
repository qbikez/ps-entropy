install-module require

import-module require
req process
req cache
req publishmap
req pester -version 4.4

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