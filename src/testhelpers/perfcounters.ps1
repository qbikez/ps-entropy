$script:perfstack = @()
$fullperfnames = $false


function measure-function([string] $__name, [scriptblock] $__command) {
    $__result = $null
    $__cmd = {
        $__result = Invoke-Command $__command
    }
    if ($script:perfstack -eq $null) {
        $script:perfstack = @() 
    }    
    $__isrecursion = $__name -in $script:perfstack
    $script:perfstack += "$__name"
    try {
        $__r = Measure-Command $__cmd
    
        if ($global:perfcounters -eq $null) {
            $global:perfcounters = @{}
        }
        if ($fullperfnames) {
            $__key = [string]::Join(">",$script:perfstack)
        } else {
            $__key = $__name
        }
        if ($global:perfcounters.ContainsKey($__key)) {
            if (!$__isrecursion) {
                $global:perfcounters[$__key].elapsed += $__r
            }
            $global:perfcounters[$__key].count++
        } else {
            $__props = [ordered]@{ name = "$__key"; elapsed = $__r; count = 1 } 
            $global:perfcounters[$__key] = new-object -type "pscustomobject" -property $__props  
        }
    
        if ($__result -ne $null) {
            return $__result
        }
    } finally {
        $script:perfstack = $script:perfstack | select -First ($script:perfstack.Length - 1)
    }
}

<#
# Usage:
# When you want to measure your functon "Get-Something"
  function Get-Something {
    # i'm doing some heavy loading here
    return $something
  }
# Add Measure-Function like this:
  function Get-Something {
    Measure-function  "$($MyInvocation.MyCommand.Name)" {
      # i'm doing some heavy loading here
      return $something
    }
  }

# then check results in $global:perfcounters hashtable
$global:perfcounters | format-table -AutoSize -Wrap | out-string | write-host
#>