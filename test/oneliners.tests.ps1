import-module $psscriptroot\..\src\oneliners\oneliners.psm1 -verbose

Describe "stack unit tests" {
    It "pushed item should be on top of the stack" {
        $it1 = "item 1"
        $it2 = "item 2"
        remove-stack -stackname "test" -confirm:$false
        
        push $it1 -stackname "test"
        
        $head = peek -stackname "test"
        $head.value | Should Be $it1
        $head.no | should be 1

        push $it2 -stackname "test"
        
        $head = peek -stackname "test"
        $head.value | Should Be $it2
        $head.no | should be 2
    }

    It "pop item should remove top item" {
        $it1 = "item 1"
        $it2 = "item 2"
        $it3 = "item 3"
        remove-stack -stackname "test" -confirm:$false
        
        push $it1 -stackname "test"
        push $it2 -stackname "test"
        push $it3 -stackname "test"
        pop -stackname "test"
        $s = stack -stackname "test"
        
        $s.count | should be 2
        $s[0].value | should be $it1
        $s[1].value | should be $it2
    }

     It "push-pop-push" {
        $it1 = "item 1"
        $it2 = "item 2"
        $it3 = "item 3"
        remove-stack -stackname "test" -confirm:$false
        
        push $it1 -stackname "test"
        
        $s = stack -stackname "test"
        @($s).Length | should be 1
        $s[0].value | should be $it1

        pop -stackname "test"
        
        $s = stack -stackname "test"
        $s | should BeNullOrEmpty

        push $it3 -stackname "test"        
        
        $s = stack -stackname "test"        
        @($s).count | should be 1
        $s[0].value | should be $it3
        $s[0].no | should be 1
    }
}

Describe "stack command" {
    It "'stack' should show stack" {       
        remove-stack -stackname "test" -confirm:$false
        push "item1" -stackname "test"
        push "item2" -stackname "test"

        $s = stack -stackname "test"

        $s | should not BeNullOrEmpty
        $s.length | should be 2
    }
    It "'stack item' should push" {       
        remove-stack -stackname "test" -confirm:$false
        stack "item1" -stackname "test"
        stack "item2" -stackname "test"

        $s = stack -stackname "test"

        $s | should not BeNullOrEmpty
        $s.length | should be 2
    }

    It "'stack psuh item' should push" {       
        remove-stack -stackname "test" -confirm:$false
        stack push "item1" -stackname "test"
        stack push "item2" -stackname "test"

        $s = stack -stackname "test"

        $s | should not BeNullOrEmpty
        $s.length | should be 2
    }

    It "'stack pop' should pop" {       
        remove-stack -stackname "test" -confirm:$false
        push "item1" -stackname "test"
        push "item2" -stackname "test"
        push "item3" -stackname "test"

        $pop = stack pop -stackname "test"

        $s = stack -stackname "test"
        $s | should not BeNullOrEmpty
        $s.length | should be 2
    }
    It "'stack search' should find items" {       
        remove-stack -stackname "test" -confirm:$false
        push "itemA 1" -stackname "test"
        push "itemB 2" -stackname "test"
        push "itemA 3" -stackname "test"

        $f = stack -search "itemA" -stackname "test"

        $f | should not BeNullOrEmpty
        $f.length | should be 2

        $f2 = stack -search "itemA" -stackname "test"
        $f2.length | should be 2
    }
}