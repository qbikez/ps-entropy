
function push {
    param([Parameter(Mandatory=$true,ValueFromPipeline=$true)] $what, $stackname = "default") 

    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    
    if ($stack -eq $null) { $stack = @(); $no = 1 }
    else { $stack = @($stack); $no = $stack.Length + 1 }

    $props = [ordered]@{
        no = $no
        value = $what
        ts = get-date -Format "yyyy-MM-dd HH:mm:ss"
    }
    $item = new-object -type pscustomobject -Property $props
    $stack += @($item)
    export-cache -data $stack -container "stack.$stackname"  -dir (get-syncdir)
    peek -stackname $stackname
}

function pop {
    param($stackname = "default") 
    
    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    if ($stack -eq $null -or $stack.length -eq 0) { return $null }
    else { $stack = @($stack) }
    $item = $stack[$stack.length-1]
    $stack = $stack | select -First ($stack.Length-1)
    if ($stack -eq $null) {
        remove-stack -stackname "$stackname" -Confirm:$false
    } else {
        export-cache -data $stack -container "stack.$stackname" -dir (get-syncdir)
    }
    return $item
}

function peek {
    param($stackname = "default") 

    $stack = @(import-cache -container "stack.$stackname" -dir (get-syncdir))
    if ($stack -eq $null -or $stack.length -eq 0) { return $null }
    $item = $stack[$stack.length-1]
    return $item
}

function get-stack {
    param($stackname = "default") 

    $stack = import-cache -container "stack.$stackname" -dir (get-syncdir)
    return $stack
}


function remove-stack {
    [Cmdletbinding(SupportsShouldProcess=$true)]
    param($stackname = "default") 
    if ($PSCmdlet.ShouldProcess("Will remove stack named '$stackname'")) {
        remove-cache -container "stack.$stackname" -dir (get-syncdir)
    }    
}

function idea {
    [Cmdletbinding(DefaultParameterSetName="list")]
    param(
        [Parameter(mandatory=$true,ParameterSetName="add",Position=1)]
        $idea,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove,
        [Parameter(mandatory=$false)]$stackname = "ideas"
    ) 
    switch($PSCmdlet.ParameterSetName) {
        { $_ -eq "add" -and !$done -and !$remove } {             
            if ($go) {
                if ($idea.gettype() -eq [int]) {
                    $found = idea -search $idea
                    if ($found -eq $null) { return }
                    $idea = $found
                }                 
                else {
                    push $idea -stackname $stackname
                    $idea = peek -stackname $stackname
                }
                push "idea: $($idea.value)"
            } else {
                push $idea -stackname $stackname
            }
        }
        "list" {
            if ($done) {
                stack -stackname "$stackname.done"    
            } else {
                stack -stackname $stackname    
            }
        }
        { $_ -eq "search" `
            -or ($_ -eq "add" -and ($done -or $remove)) } {
            $ideas = stack -stackname $stackname  
            if ($search -eq $null) { $search = $idea } 
            $found = $ideas | ? { (($search.gettype() -eq [int]) -and $_.no -eq $search) -or $_.value -match "$search" }
            if ($found -eq $null) {
                if ($search.gettype() -eq [int]) { write-warning "no idea with id $search found" }
                else { write-warning "no idea matching '$search' found" }
                return
            }
            $found = @($found) 

            if ($_ -eq "search") {
                return $found
            }

            if ($found.Length -gt 1) {
                write-warning "more than one idea matching '$search' found:"
                $found | format-table | out-string | write-host
                return
            }                        
            write-verbose "found matching idea: $found" 
            
            if ($done) {
                push $found[0] -stackname "$stackname.done"
            }
            if ($done -or $remove) {
                $newstack = $ideas | ? { $_.no -ne $found[0].no }
                export-cache -data $newstack -container "stack.$stackname" -dir (get-syncdir)            
            }
        }
    }    
}

function pop-idea {
     pop -stackname "ideas"
}


function todo {
    param(
        [Parameter(mandatory=$true,ParameterSetName="add",Position=1)]
        $idea,                 
        [Parameter(mandatory=$true,ParameterSetName="search")]
        $search,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$go,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [Parameter(mandatory=$false,ParameterSetName="list")]
        [switch][bool]$done,
        [Parameter(mandatory=$false,ParameterSetName="add")]
        [switch][bool]$remove
        )

    idea @PSBoundParameters -stackname "todo"
}

new-alias stack get-stack