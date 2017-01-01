
######## helpers: ###################


function install-chocolatey ($version = $null) {
	if (!(test-choco)) {
			Write-Warning "chocolatey not found, installing"

            #$version = "0.9.8.33"
            $s = (new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1')
            if ($version -ne $null) {
                $s = $s -replace "https://chocolatey.org/api/v2/package/chocolatey","https://chocolatey.org/api/v2/package/chocolatey/$version"
			    $s = $s -replace "https://packages.chocolatey.org/.*\.nupkg","https://chocolatey.org/api/v2/package/chocolatey/$version"
            }
			iex $s
			cmd /c "SET PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
            $env:Path = [System.Environment]::GetEnvironmentVariable("PATH",[System.EnvironmentVariableTarget]::Machine) + ";" + [System.Environment]::GetEnvironmentVariable("PATH",[System.EnvironmentVariableTarget]::User) 
			if (!(test-choco)) {
				write-error "chocolatey still not found! Installation failed?"
			}
            $path = "$env:ChocolateyInstall\chocolateyinstall\chocolatey.config"
            if (test-path $path) {
                write-host "setting chocolatey config 'ksMessage' to 'false'  in config file '$path'"
                $xml = [xml](Get-Content $path)
                $xml.chocolatey.ksMessage = "false"
                $xml.Save($path)
            }
	} 
	else 
	{
		write-host "chocolatey is already installed"       
	}
}

######## chocolatey helpers
$global:installed = $null


function test-command([string] $cmd) {
    return Get-Command $cmd -ErrorAction Ignore
}

function _ensure-choco() {
    if (!( test-command "choco")) {
        install-chocolatey 
    }
}