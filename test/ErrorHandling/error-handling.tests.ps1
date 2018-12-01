Describe "Error handling" {
    It "thrown exception should be in `$error" {

        $msg = "i'm a lumberjack and I'm ok"
        try {
            throw $msg
        } catch {

        }
        $error[0].Exception.Message | Should -Be $msg
    }
}

