[![Build status](https://ci.appveyor.com/api/projects/status/0l1cry325718oqst/branch/master?svg=true)](https://ci.appveyor.com/project/qbikez/ps-entropy/branch/master)

Various Powershell modules

## Module: Require

### Installation

    PS> Install-Module require

### usage

    PS> req "myPSModule"
  
This command will look for `myPSModule`, install it from PowershellGallery if it's not found localy and import it.

    PS> req "myPSModule" -version 1.2.4
  
Looks for `myPSModule` with minial version `1.2.4` and installs/updates it if necessary.

## Module: [Newtonsoft.Json](https://github.com/qbikez/ps-entropy/tree/master/src/newtonsoft.json)

