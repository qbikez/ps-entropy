BeforeAll {
    if (get-module MsDeploy) { remove-module MsDeploy -Force }
    import-module "$PSScriptRoot\..\MsDeploy.psd1"

    # msdeploy.exe may not be installed; give Mock a command to replace
    InModuleScope MsDeploy {
        function script:msdeploy { param($verb, $source, $dest, $skip, [Parameter(ValueFromRemainingArguments)]$rest) }
    }
}

Describe "Msdeploy test" {
    It "should skip files and dirs by default" {
        InModuleScope MsDeploy {
            $expectedSkipActions = @("skipaction=Delete,objectname=filePath","skipaction=Delete,objectname=dirPath")

            Mock msdeploy {}
            Mock msdeploy {} -Verifiable -ParameterFilter { $null -eq (Compare-Object $skip $expectedSkipActions) }

            Push-Location "TestDrive:\"
            try {
                "test" > "test.txt"
                Copy-MsDeployFile -server "test" -source "test.txt" -targetpath "target.txt" -credential "abc:def"
            } finally {
                Pop-Location
            }

            Should -InvokeVerifiable
        }
    }
}