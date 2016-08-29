import-module pester

if (gmo require) { rmo require }
import-module $psscriptroot\..\src\require\require.psm1 -verbose
#import-module "$PSScriptRoot/../third-party/pester"  


Describe "oneliners module test" {
    
    It "Should load properly" {
        { import-module "$psscriptroot\..\src\oneliners\oneliners.psm1" -ErrorAction Stop } | should not throw
        gmo oneliners | should not benullorempty
    }
}

Describe "require module test" {
    It "Should load required module" {
        $module = "publishmap"
        if ((gmo $module) -ne $null) { rmo $module }
        req $module
        $m = gmo $module
        $m | Should Not benullorempty
    }
}


Describe "require module test" {
    It "Should load required module from choco" {
        $module = "pscx"
        $version = "3.2.0"
        $package = " pscx"

        if ((gmo $module) -ne $null) { rmo $module }
        req $module -version $version -source choco -package $package
        $m = gmo $module
        $env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", [System.EnvironmentVariableTarget]::Machine) + ";C:\Program Files (x86)\PowerShell Community Extensions\Pscx3" + ";C:\Program Files\PowerShell Community Extensions\Pscx3"
        $m | Should Not benullorempty
    }
}