[CmdletBinding()]
param($buildNo, [switch]$force)

$repoRoot = "$psscriptroot\.."

pushd $repoRoot
try {

    $lastReleaseTag = git describe --match "release*" --abbrev=0 HEAD --tags

    if ($lastReleaseTag -notmatch "release-[v]{0,1}([0-9]+)") {
        throw "last release tag $lastReleaseTag does not contain a numeric version"
    }
    $lastReleaseNo = [int]::Parse($Matches[1])
    write-host "last release: $lastReleaseTag (No=$lastReleaseNo)"

    $toRelease = @()

    $diff = git diff --name-only $lastReleaseTag HEAD
    foreach($diffFile in $diff) {
        $splits = $diffFile.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        $parentDir = $splits[0]
        if (!$toRelease.Contains($parentDir)) {
            $toRelease += $parentDir
        }
    }

    $toRelease = $toRelease | % {
        Get-ChildItem $_ -Recurse -Filter "*.psd1" | ? { $_ -notmatch "test" } | select -ExpandProperty FullName
    }

    if ($force) {
        $toRelease = Get-ChildItem . -Recurse -Filter "*.psd1" | ? { $_ -notmatch "test" } | select -ExpandProperty FullName 
    }

    $toRelease = $toRelease | ? {
        $_ -notmatch "PSScriptAnalyzer"
    }

    if ($null -eq $toRelease) {
        Write-Warning "Nothing to release"
        return
    }

    write-host "Will Release modules: $ToRelease"
    
    $status = @{}
    foreach($module in $toRelease) {
        try {
            write-host "pushing module $module"
            if ($buildNo -eq $null) {
                scripts/lib/push.ps1 $module -newbuild
            } else {
                scripts/lib/push.ps1 $module -buildno $buildNo
            }
            $status[$module] = "success"
            git add $module
        } catch {
            write-error $_
            $status[$module] = $_
        }
    }

    $success = $status.Values | ? { $_ -eq "success" }
    if ($success) {
        $newReleaseNo = $lastReleaseNo + 1
        git commit -m "release $newReleaseNo"
        git tag -a "release-$newReleaseNo" -m "release $newReleaseNo"
    }

} finally {
    popd
}