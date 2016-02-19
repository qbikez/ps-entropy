function get-dotnetversions() {
    $def = get-content "$psscriptroot\dotnetver.cs" | out-string
    add-type -TypeDefinition $def

    return [DotNetVer]::GetVersionFromRegistry()
}