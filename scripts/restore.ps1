install-module process
install-module cache
install-module publishmap

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