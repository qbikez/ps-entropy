if (gmo Remoting) {
    rmo Remoting -force
}

ipmo $PSScriptRoot\..\src\Remoting.psd1

Describe "Remoting module tests" {
    It "should copy files recursively" {
        $session = rps localhost -noenter
    }
}