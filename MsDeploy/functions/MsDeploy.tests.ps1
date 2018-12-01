if (get-module MsDeploy) { remove-module MsDeploy -Force }
import-module "$PSScriptRoot\..\MsDeploy.psd1"

InModuleScope -ModuleName MsDeploy {
    Describe "Msdeploy test" {
        It "should skip files and dirs by default" {
            $expectedSkipActions = @("skipaction=Delete,objectname=filePath","skipaction=Delete,objectname=dirPath")
            
            Mock msdeploy {}
            Mock msdeploy {} -Verifiable -ParameterFilter { (Compare-Object $skip $expectedSkipActions) -eq $null }
            
            In "testdrive:/" {
                echo "test" > "test.txt"
                Copy-MsDeployFile -server "test" -source "test.txt" -targetpath "target.txt" -credential "abc:def"
            }

            Assert-VerifiableMock
        }
    }
}