function get-dotnetversions() {
    $def = get-content "$psscriptroot\dotnetver.cs" | out-string
    add-type -TypeDefinition $def
    write-host ""
    write-host "Available .Net frameworks:"
    write-host ""
    $r = [DotNetVer]::GetVersionFromRegistry()
    $r | write-host

    write-host ""
    write-host "Available .Net framework SDKs:"
    write-host ""
    if (test-path hklm:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\FRAMEWORKSDK) {
        $sdk = get-item HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\SxS\FrameworkSDK
        $sdk.Property | out-string | write-host
    }
    if (test-path hklm:\SOFTWARE\Microsoft\VisualStudio\SxS\FRAMEWORKSDK) {
        $sdk = get-item HKLM:\SOFTWARE\Microsoft\VisualStudio\SxS\FrameworkSDK
        $sdk.Property | out-string | write-host
    }
    write-host ""
}