. $PSScriptRoot\include.ps1

$msg = "i'm a lumberjack and I'm ok"

$error.Clear()
try {
    thrownew { foo-throw $msg }
} catch { 
   Write-Errordetails $_
}

