import-module pester

if (gmo require) { rmo require }
import-module $psscriptroot\..\src\require\require.psm1 -verbose

if (gmo cache) { rmo cache }
import-module $psscriptroot\..\src\cache\cache.psm1 -verbose

Describe "import/export cache" {
    It "should recall exported cache as string" {
        $data = "this is string cache"
        Cache\export-cache -data $data -container "test"

        $imported = Cache\import-cache -container "test"
        $imported | Should Be $data
    }
}

Describe "import/export settings" {
    It "should recall exported settings" {
        $data = "this is string cache"
        cache\export-setting -key "test1" -value $data

        $imported = Cache\import-settings

        $imported["test1"] | Should Be $data
    }

    It "should recall exported secure settings" {
        $data = "my-secret-value"
        $data = ConvertTo-SecureString -String $data -AsPlainText -Force
        $null = cache\export-setting -key "testsecure" -securevalue $data

        $imported = Cache\import-settings

        $value = $imported["testsecure"]
        $value | Should BeOfType [SecureString]

        $plain_expected = ConvertTo-PlainText $data
        $plain_value = ConvertTo-PlainText $value

        $plain_value | Should Be $plain_expected        
    }
}