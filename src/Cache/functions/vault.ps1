function export-vaultcache([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$data, [Parameter(Mandatory=$true)]$container) {
    invoke vault write $container "value=$data" -showoutput:$false
}

function import-vaultcache([Parameter(Mandatory=$true)]$container) {
    $json = invoke vault read "-format=json" $container -passthru -showoutput:$false -nothrow -passerrorstream | out-string
    if ($lastexitcode -ne 0) {
        throw "vault read failed: $json"
    }
    $data = ConvertFrom-Json $json
    return $data.data
}