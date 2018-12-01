. $PSScriptRoot\include.ps1

$msg = "i'm a lumberjack and I'm ok"

$error.Clear()
try {
    rethrow { foo-throw $msg }
} catch { 
    write-errorDetails $_
    #throw
}