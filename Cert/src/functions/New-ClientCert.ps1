function New-ClientCert {
param(
[parameter(mandatory=$true)]
$cn,
[parameter(mandatory=$true)]
$pass,
[switch][bool] $force,
$days = 3650)

    New-Cert -CN $cn -OpenSsl -ClientAuth -ca legimica -pass $pass -force:$force -days $days
}