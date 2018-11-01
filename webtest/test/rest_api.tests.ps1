. "$PSScriptRoot\includes.ps1"

$kill = $false

req process

Describe "rest api" {
    Context "with local sinatra" {
        # start server
        write-verbose "starting sinatra server"
        $srv = start-app "ruby.exe" -argumentlist @("sinatra/server.rb") -port 4567 -http -captureOutput:$false -verbose
        try {
            It "should get simple request" {
                $r = invoke-url "http://localhost:4567"
                $r.StatusCode | Should Be 200
            }
        }
        finally {
            if ($srv -and $kill) {
                try {
                    $srv.Kill()
                } catch {
                    write-warning $_.Exception.Message
                } 
            }
        }
    }
}