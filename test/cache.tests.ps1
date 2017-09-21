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

    It "updating password should not destroy encrypted values" {
        $data = "my-secret-value"
        $container = "test2"
        $data = ConvertTo-SecureString -String $data -AsPlainText -Force
        $pass = ConvertTo-SecureString -String "my-secret-password" -AsPlainText -Force
        
        cache\Set-GlobalPassword -container $container -password $pass

        $null = cache\export-setting -container  $container -key "testsecure" -securevalue $data -force -erroraction stop

        $pass = ConvertTo-SecureString -String "my-new-password" -AsPlainText -Force
        cache\Update-GlobalPassword -container  $container -password $pass

        $imported = Cache\import-settings  -container  $container

        $imported | Should Not BeNullOrEmpty
        $value = $imported["testsecure"]
        $value | Should BeOfType [SecureString]

        $plain_expected = ConvertTo-PlainText $data
        $plain_value = ConvertTo-PlainText $value

        $plain_value | Should Be $plain_expected        
    }

    It "should recall exported settings" {
        $data = "this is string cache"
        cache\export-setting -key "test1" -value $data -force -erroraction stop

        $imported = Cache\import-settings

        $imported | Should Not BeNullOrEmpty
        $imported["test1"] | Should Be $data
    }
    It "should get or create global password" {
        $encKey = cache\_getenckey
    }

    It "should recall exported secure settings" {
        $data = "my-secret-value"
        $data = ConvertTo-SecureString -String $data -AsPlainText -Force
        $pass = "my-secret-password"
        $pass = ConvertTo-SecureString -String $pass -AsPlainText -Force
        $null = cache\export-setting -key "testsecure" -securevalue $data -password $pass -container "test" -force -erroraction stop

        $imported = Cache\import-settings -password $pass -container "test"

        $imported | Should Not BeNullOrEmpty
        $value = $imported["testsecure"]
        $value | Should BeOfType [SecureString]

        $plain_expected = ConvertTo-PlainText $data
        $plain_value = ConvertTo-PlainText $value

        $plain_value | Should Be $plain_expected        
    }

    
   
}