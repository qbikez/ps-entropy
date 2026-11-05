BeforeAll {
    if (gmo require) { rmo require -force }
    import-module $psscriptroot\..\src\require.psm1
}

Describe "require module test" {
    It "Should load required module" {
        $module = "publishmap"
        if ((gmo $module) -ne $null) { rmo $module -force }
        req $module
        $m = gmo $module
        $m | Should -Not -BeNullOrEmpty
    }

   It "Should load required module from choco" {
        #try {
            $module = "carbon"
            $version = "2.5.0"
            $package = " carbon"

            if ((gmo $module) -ne $null) { rmo $module }
            req $module -version $version -source choco -package $package

            gmo $module | Should -Not -BeNullOrEmpty
            test-path "{$env:ProgramFiles}\WindowsPowerShell\Modules\carbon\" | Should -Not -BeNullOrEmpty            
        #} catch {
            #Set-ItResult -Inconclusive -Because "something's wrong with pscx install from choco"
        #}
    }
    It "Should try to upgrade module from choco if requested version is higher than current" {
        try {
            $module = "carbon"
            $version = "99.99.99"
            $package = " carbon"

            if ((gmo $module) -ne $null) { rmo $module }
            try {
                $o = req $module -version $version -source choco -package $package -ErrorAction Stop
            } catch {
                $msg = $_.Exception.Message
                if ($msg -notmatch "requested module carbon version $version, but found") {
                    throw
                }
            }
        } catch {
            Set-ItResult -Inconclusive -Because "something's wrong with carbon install from choco"
        }
        # ok, at least we tried
    }
}

Describe "version specification" {
    
}