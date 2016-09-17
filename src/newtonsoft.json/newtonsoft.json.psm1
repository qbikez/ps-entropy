$asm = [Reflection.Assembly]::LoadFile("$PSScriptRoot\libs\Newtonsoft.Json.dll")

function ConvertFrom-JObject($obj) {
   if ($obj -is [Newtonsoft.Json.Linq.JArray]) {
        $a = @()
        foreach($entry in $obj.GetEnumerator()) {
            $a += @(convertfrom-jobject $entry)
        }
        return $a
   }
   elseif ($obj -is [Newtonsoft.Json.Linq.JObject]) {
       $h = [ordered]@{}
       foreach($kvp in $obj.GetEnumerator()) {
            $val =  convertfrom-jobject $kvp.value
            if ($kvp.value -is [Newtonsoft.Json.Linq.JArray]) { $val = @($val) }
            $h += @{ "$($kvp.key)" = $val }
       }
       return $h
   }
   elseif ($obj -is [Newtonsoft.Json.Linq.JValue]) {
        return $obj.Value
   }
   else {
    return $obj
   }
}

function ConvertFrom-JsonNewtonsoft([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$string) {
	$obj = [Newtonsoft.Json.JsonConvert]::DeserializeObject($string, [Newtonsoft.Json.Linq.JObject])
    
    return ConvertFrom-JObject $obj
}

function ConvertTo-JsonNewtonsoft([Parameter(Mandatory=$true,ValueFromPipeline=$true)]$obj) {
    return [Newtonsoft.Json.JsonConvert]::SerializeObject($obj, [Newtonsoft.Json.Formatting]::Indented)
}

Export-ModuleMember -Function ConvertFrom-JsonNewtonsoft,ConvertTo-JsonNewtonsoft