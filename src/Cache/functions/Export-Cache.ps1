function sanitize-containername([Parameter(Mandatory=$true, ValueFromPipeline=$true)]$container) {
    return $container.Replace("\","_").Replace("/","_").Replace(":","_")
}

function export-cache([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$data, [Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir } 
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir } 
    $container = sanitize-containername $container
    if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir }
    $path = "$cacheDir\$container.json"
    $data | ConvertTo-Json | Out-File $path
}

function import-cache([Parameter(Mandatory=$true)]$container, [Parameter(Mandatory=$false)]$dir = ".cache") {
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir } 
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir } 
    $container = sanitize-containername $container
    if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir }
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
    $container = sanitize-containername $container
    if ((test-path $cacheDir)) { 
        $path = "$cacheDir\$container.json"
        if (test-path $path) {
            remove-item $path
        }
    }
}
