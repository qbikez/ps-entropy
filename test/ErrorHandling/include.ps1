function foo-throw($msg) {
    throw [System.NotImplementedException]$msg
}
function rethrow([ScriptBlock] $sb) {
    try {
        invoke-command $sb
    } catch {
        throw 
    }
}

function throwErrorRecord([ScriptBlock] $sb) {
    try {
        invoke-command $sb
    } catch {
        throw $_
    }
}

function thrownew([ScriptBlock] $sb) {
    try {
        invoke-command $sb
    } catch {
        throw $_.exception
    }
}

function write-errorDetails($_) {
    write-host "====="
    write-host "== ScriptStackTrace:"
    write-host $_.ScriptStackTrace
    write-host ""

    $ex = $_.Exception
    $level = 0
    while ($ex -ne $null) {
        write-host ("".PadLeft($level, ">") + "== Exception.Type:")
        write-host $_.Exception.GetType().FullName
        write-host ""
        write-host ("".PadLeft($level, ">") + "== Exception.Message:")
        write-host $_.Exception.Message
        write-host ""
        write-host ("".PadLeft($level, ">") + "== Exception.StackTrace:")
        write-host $_.Exception.StackTrace
        write-host ""
  
        $ex = $ex.InnerException
    }
    
    

    write-host "== InvocationInfo:"
    Write-host "= ScriptName:      $($_.InvocationInfo.ScriptName)"
    Write-host "= PositionMessage: $($_.InvocationInfo.PositionMessage)"
    Write-host "= LIne:            $($_.InvocationInfo.Line)"
    write-host ""
    write-host "== ERROR:"
    write-error $_.Exception
    write-host "====="
}