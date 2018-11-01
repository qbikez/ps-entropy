if (gmo Remoting) {
    rmo Remoting -force
}

ipmo $PSScriptRoot\..\src\Remoting.psd1
$server = "docker/iis"

Describe "Remoting module tests" {
    $target = "c:\test\"
    It "should copy files recursively" -Pending {
        $session = rps $server -noenter
        invoke-command -Session $session -scriptBlock { if (test-path $using:target) { rmdir $using:target -Recurse -force } }

        Copy-RemoteFile -source "$PSScriptRoot/input" -target "$target" -tosession $session -Verbose

        $listing = invoke-command -Session $session -scriptBlock { ls $using:target -Recurse }
        $listing | format-table | out-string | write-host

        $listing.count | Should -Be 3
    }
}