function export-vaultcache([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$data, [Parameter(Mandatory=$true)]$container) {
    invoke vault write $container "value=$data" -showoutput:$false
}

function import-vaultcache([Parameter(Mandatory=$true)]$container) {
    $json = invoke vault read "-format=json" $container -passthru -showoutput:$false | out-string
    $data = ConvertFrom-Json $json
    return $data.data
}