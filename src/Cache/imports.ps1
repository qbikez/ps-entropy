# grab functions from files
get-childitem $psscriptroot\functions\ -filter "*.ps1" | 
    ? { -not ($_.name.Contains(".Tests.")) } |
    ? { -not (($_.name).StartsWith("_")) } |
    % { . $_.fullname }

