FROM microsoft/iis

SHELL ["powershell"]
RUN Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force;  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
RUN Install-Module Require

RUN Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
RUN choco install -y webpicmd
RUN req Process; invoke webpicmd /Install /Products:WDeploy36 /AcceptEula

ARG admin_pass=FooBar123

RUN net users /add /y admin $env:admin_pass
RUN net localgroup Administrators /add admin

EXPOSE 80