function Export-Cache(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]$data,
    [Parameter(Mandatory = $true)]$container,
    [Parameter(Mandatory = $false)]$dir = ".cache"
) {
    # try custom providers
    if (_IsCustomProvider $container) {
        return _InvokeCustomProviderCommand -command "export" -container $container -data $data
    }
    else {
        # default disk cache provider
        $container = _SanitizeContainerName $container

        if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir }
        else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir }

        try {
            if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir -erroraction stop }
        }
        catch {
            throw "could not find or create cache directory '$cachedir'"
        }
        $path = "$cacheDir\$container.json"
        $data | ConvertTo-Json | Out-File $path -Encoding utf8
    }
}

function Import-Cache {
    param (
        [Parameter(Mandatory = $true)]$container,
        [Parameter(Mandatory = $false)]$dir = ".cache"
    )
    if ([string]::IsNullOrEmpty($container)) { throw "container cannot be null or empty" }
    # try custom providers
    if (_IsCustomProvider $container) {
        return _InvokeCustomProviderCommand -command "export" -container $container
    }
    else {
        # default disk cache provider
        if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir }
        else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir }

        $container = _SanitizeContainerName $container
        try {
            if (!(test-path $cacheDir)) { $null = new-item -ItemType directory $cacheDir -erroraction stop }
        }
        catch {
            throw "could not find or create cache directory '$cachedir'"
        }
        $path = "$cacheDir\$container.json"

        $data = $null
        if (test-path $path) {
            $data = Get-Content $path -Encoding UTF8 | out-String | ConvertFrom-Json
        }

        return $data
    }
}

function Get-CacheList {
    param (
        [Parameter(Mandatory = $false)]$dir = ".cache"
    )

    if ([string]::IsNullOrEmpty($dir)) { throw "container cannot be null or empty" }
    # try custom providers
    if (_IsCustomProvider $drir) {
        return _InvokeCustomProviderCommand -command "list" -dir $dir
    }
    else {
        # default disk cache provider
        if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir }
        else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir }

        if (!(test-path $cacheDir)) { return @{} }

        $result = @{}
        $containers = Get-ChildItem $cacheDir -Filter "*.json"
        
        foreach($container in $containers) {
            $key = [System.IO.Path]::GetFileNameWithoutExtension($container.name)
            $value = Get-Content $container.fullname | out-string
            $result[$key] = $value
        }

        return $result
    }
}

function Remove-Cache {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]$container,
        [Parameter(Mandatory = $false)]$dir = ".cache"
    )
    if ([System.IO.Path]::IsPathRooted($dir)) { $cacheDir = $dir }
    else { $cacheDir = Join-Path "$home\Documents\windowspowershell" $dir }
    $container = _SanitizeContainerName $container
    if ((test-path $cacheDir)) {
        $path = "$cacheDir\$container.json"
        if (test-path $path) {
            if ($PSCmdlet.ShouldProcess("Remove cache container", "Remove $path")) {
                remove-item $path
            }
        }
    }
}

function _IsCustomProvider($container) {
    return $container -ne $null -and $container.Contains(":")
}

function _InvokeCustomProviderCommand($command, $container, $dir, $data) {
    $splits = $container.split(":")
    $provider = $splits[0]
    $providerPath = $splits[1]
    if ($null -ne (get-command "export-$($provider)cache" -ErrorAction Ignore)) {
        $p = @{
            container = $providerPath
        }
        if ($data -ne $null) {
            $p.data = $data
        }

        return (& "$command-$($provider)cache" @p)
    }
}

function _SanitizeContainerName([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$container) {
    return $container.Replace("\", "_").Replace("/", "_").Replace(":", "_").Replace("?", "_")
}