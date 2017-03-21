function foo {
 trap {
    write-host "dupa: $_"   
    continue 
 }
 throw "I'm an exception"
 Write-Error -Exception "written exception" -ErrorAction stop
 
 write-host "after throw"
}

foo

write-host "after foo"

Write-Error "a" -ErrorAction stop