import-module pester
#import-module "$PSScriptRoot/../third-party/pester"  


Describe "oneliners module test" {
    
    It "Should load properly" {
        { import-module "$psscriptroot\..\src\oneliners\oneliners.psm1" -ErrorAction Stop } | should not throw
        gmo oneliners | should not benullorempty
    }
}