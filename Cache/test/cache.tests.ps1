import-module pester

if (gmo cache) { rmo cache -force }
import-module $psscriptroot\..\src\cache.psm1 -verbose

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
        $container = "test123-noencryption"
        $data = "this is string cache"
        cache\export-setting -key "test1" -value $data -container $container  -force -erroraction stop

        $imported = Cache\import-settings -container $container 

        $imported | Should Not BeNullOrEmpty
        $imported["test1"] | Should Be $data
    }

    It "should get or create global password" {
        $container = "test123-enckey"
        $pass = ConvertTo-SecureString -String "my-secret" -AsPlainText -Force
        cache\Set-GlobalPassword -container $container -password $pass
        $encKey = cache\_getenckey -container $container
        $encKey | Should Not BeNullOrEmpty
    }

    It "should not ask for password if password is provided" {
        $container = "test123"
        $data = "my-secret-value"
        $data = ConvertTo-SecureString -String $data -AsPlainText -Force
        $pass = "my-secret-password"
        $pass = ConvertTo-SecureString -String $pass -AsPlainText -Force

        cache\remove-globalpassword -container $container

        $null = cache\export-setting -key "testsecure" -securevalue $data -password $pass -container $container -force -erroraction stop

        $imported = Cache\import-settings -password $pass -container $container

        $imported | Should Not BeNullOrEmpty
        $value = $imported["testsecure"]
        $value | Should BeOfType [SecureString]

        $plain_expected = ConvertTo-PlainText $data
        $plain_value = ConvertTo-PlainText $value

        $plain_value | Should Be $plain_expected        
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
}

Describe "list cached values" {
    It "should list all exported values" {
        $dir = "test-$([Guid]::NewGuid())"
        Cache\Export-Cache -data "value1" -container "key1" -dir "$dir"
        Cache\Export-Cache -data "value2" -container "key2" -dir "$dir"
        Cache\Export-Cache -data "value3" -container "key3" -dir "$dir"

        $l = Cache\Get-CacheList -dir $dir
        
        $l.Count | Should -Be 3
    }
}