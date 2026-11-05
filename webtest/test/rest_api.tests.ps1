BeforeAll {
    . "$PSScriptRoot\includes.ps1"
    req process
}

Describe "rest api" {
    Context "with local sinatra" {
        BeforeAll {
            $kill = $true
            $port = 34567 # the same as in sinatra/server.rb

            write-verbose "starting sinatra server"
            $srv = start-app "ruby.exe" -argumentlist @("$psscriptroot/sinatra/server.rb") -port $port -http -captureOutput:$true -verbose -outfile:"sinatra-out.log" -errorfile:"sinatra-err.log" -timeout 10
        }

        AfterAll {
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

        It "should get simple request" {
            $r = invoke-url "http://localhost:$port"
            $r.StatusCode | Should -Be 200
        }
    }
}