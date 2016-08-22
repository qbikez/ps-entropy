import-module pester
if (gmo require) { rmo require }
import-module require
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