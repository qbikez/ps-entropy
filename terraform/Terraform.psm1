$helpersPath = (Split-Path -parent $MyInvocation.MyCommand.Definition)

get-childitem $psscriptroot -filter "*.ps1" | 
    ? { -not ($_.name.Contains(".Tests.")) } |
    ? { -not (($_.name).StartsWith("_")) } |
    % { . $_.fullname }

Export-ModuleMember -Function * -Alias *
