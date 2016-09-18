function _SanitizeContainerName([Parameter(Mandatory=$true, ValueFromPipeline=$true)]$container) {
    return $container.Replace("\","_").Replace("/","_").Replace(":","_")
}

function export-cache([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$data, [Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir } 
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir } 
    $container = _SanitizeContainerName $container
    try {
        if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir -erroraction stop }
    } catch {
        throw "could not find or create cache directory '$cachedir'"
    }
    $path = "$cacheDir\$container.json"
    $data | ConvertTo-Json | Out-File $path
}

function import-cache([Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
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
        $data = Get-Content $path | out-String | ConvertFrom-Json
    }

    return $data
}

function remove-cache([Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
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
