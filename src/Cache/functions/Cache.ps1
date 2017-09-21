function _SanitizeContainerName([Parameter(Mandatory=$true, ValueFromPipeline=$true)]$container) {
    return $container.Replace("\","_").Replace("/","_").Replace(":","_")
}

function Export-Cache([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$data, [Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
    # check custom providers
    if ($container.Contains(":")) {
        $splits = $container.split(":")
        $provider = $splits[0]
        if ($null -ne (get-command "export-$($provider)cache" -ErrorAction Ignore)) {
            return & "export-$($provider)cache" $data $container.Substring($provider.length + 1)
        }
    }
    # default disk cache provider
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir } 
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir } 
    $container = _SanitizeContainerName $container
    try {
        if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir -erroraction stop }
    } catch {
        throw "could not find or create cache directory '$cachedir'"
    }
    $path = "$cacheDir\$container.json"
    $data | ConvertTo-Json | Out-File $path -Encoding utf8
}

function Import-Cache([Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
    # check custom providers
    if ($container.Contains(":")) {
        $splits = $container.split(":")
        $provider = $splits[0]
        if ($null -ne (get-command "import-$($provider)cache" -ErrorAction Ignore)) {
            return & "import-$($provider)cache" $container.Substring($provider.length + 1)
        }
    }
    # default disk cache provider
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir } 
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir } 
    $container = _SanitizeContainerName $container
    try {
    if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir -erroraction stop }
    } catch {
        throw "could not find or create cache directory '$cachedir'"
    }
    $path = "$cacheDir\$container.json"
    
    $data = $null
    if (test-path $path) {
        $data = Get-Content $path -Encoding UTF8 | out-String | ConvertFrom-Json
    }

    return $data
}

function Remove-Cache([Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir } 
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir } 
    $container = _SanitizeContainerName $container
    if ((test-path $cacheDir)) { 
        $path = "$cacheDir\$container.json"
        if (test-path $path) {
            remove-item $path
        }
    }
}
