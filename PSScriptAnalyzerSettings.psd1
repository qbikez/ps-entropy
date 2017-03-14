# PSScriptAnalyzerSettings.psd1
@{
    Severity=@(
        'Error'
        'Warning'
    )
    Rules = @{
        'PSAvoidUsingCmdletAliases' = @{
            'Whitelist' = @('cd','%','select','where','pushd','popd','gi',"ipmo","gmo")
        }
    }
    ExcludeRules=@(
     
    #    'PSAvoidUsingWriteHost'
    )
}