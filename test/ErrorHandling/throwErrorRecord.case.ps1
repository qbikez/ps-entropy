. $PSScriptRoot\include.ps1

$msg = "i'm a lumberjack and I'm ok"

$error.Clear()
try {
    throwErrorRecord { foo-throw $msg }
} catch { 
   Write-Errordetails $_
}

