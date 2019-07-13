install-module Require -Force -Confirm:$false

$initScripts = get-childitem "$psscriptroot/.." -directory -Exclude "scripts" | % { get-childitem $_ -Filter "init.ps1" }

foreach($init in $initScripts) {
    pushd 
    try {
        write-host $init.fullname
        cd (split-path -parent $init.fullname)
        & $init.fullname
    } finally {
        popd
    }
}