. "$PSScriptRoot\includes.ps1"

$kill = $true

req process

Describe "rest api" {
    $port = 34567 # the same as in sinatra/server.rb
    Context "with local sinatra" {
        # start server
        write-verbose "starting sinatra server"
        $srv = start-app "ruby.exe" -argumentlist @("$psscriptroot/sinatra/server.rb") -port $port -http -captureOutput:$true -verbose -outfile:"sinatra-out.log" -errorfile:"sinatra-err.log" -timeout 10
        try {
            It "should get simple request" {
                $r = invoke-url "http://localhost:$port"
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
            if (test-path "sinatra-out.log") { cat "sinatra-out.log" | Write-Indented -mark "sinatra =out= "}
            if (test-path "sinatra-err.log") { cat "sinatra-err.log" | Write-Indented -mark "sinatra =err= " }
        }
    }
}