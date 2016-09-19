using System;
using Microsoft.Win32;
using System.Collections.Generic;

public class DotNetVer {
    public static List<string> GetVersionFromRegistry() {
        var result = new List<string>(); 
        result.AddRange(GetVersion4FromRegistry());
        result.AddRange(Get45or451FromRegistry());
        
        return result;
    }
    
    private static List<string> GetVersion4FromRegistry()
    {
        var result = new List<string>();
        // Opens the registry key for the .NET Framework entry.
            using (RegistryKey ndpKey = 
                RegistryKey.OpenRemoteBaseKey(RegistryHive.LocalMachine, "").
                OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\"))
            {
                // As an alternative, if you know the computers you will query are running .NET Framework 4.5 
                // or later, you can use:
                // using (RegistryKey ndpKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, 
                // RegistryView.Registry32).OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\"))
            foreach (string versionKeyName in ndpKey.GetSubKeyNames())
            {
                if (versionKeyName.StartsWith("v"))
                {

                    RegistryKey versionKey = ndpKey.OpenSubKey(versionKeyName);
                    string name = (string)versionKey.GetValue("Version", "");
                    string sp = versionKey.GetValue("SP", "").ToString();
                    string install = versionKey.GetValue("Install", "").ToString();
                    
                    var fullname = "";
                    if (install == "") {
                        //no install info, must be later.
                        fullname = versionKeyName + "  " + name;
                    }
                    else
                    {
                        if (sp != "" && install == "1")
                        {
                            fullname = versionKeyName + "  " + name + "  SP" + sp;
                        }
                    }
                    if (name != "")
                    {
                        result.Add(fullname);
                        continue;
                    }
                    foreach (string subKeyName in versionKey.GetSubKeyNames())
                    {
                        RegistryKey subKey = versionKey.OpenSubKey(subKeyName);
                        name = (string)subKey.GetValue("Version", "");
                        if (name != "")
                            sp = subKey.GetValue("SP", "").ToString();
                        install = subKey.GetValue("Install", "").ToString();
                        if (install == "") //no install info, must be later.
                            result.Add(versionKeyName + "  " + name);
                        else
                        {
                            if (sp != "" && install == "1")
                            {
                                result.Add(fullname + "  " + subKeyName + "  " + name + "  SP" + sp);
                            }
                            else if (install == "1")
                            {
                                result.Add(fullname + "  " + subKeyName + "  " + name);
                            }
                        }
                    }
                }
            }
        }
        return result;

    }
    
    
    private static List<string> Get45or451FromRegistry()
    {
        var result = new List<string>(); 
        using (RegistryKey ndpKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32).OpenSubKey("SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full\\")) {
            if (ndpKey != null) {
                if(ndpKey.GetValue("Version") != null) {
                    result.Add(ndpKey.GetValue("Version") + " Full"); 
                }
                else if(ndpKey.GetValue("Release") != null) {
                    result.Add(CheckFor45DotVersion((int) ndpKey.GetValue("Release")));
                }
            } 
        }
        
        using (RegistryKey ndpKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32).OpenSubKey("SOFTWARE\\Microsoft\\NET Framework Setup\\NDP\\v4\\Client\\")) {
            if (ndpKey != null) {
                if(ndpKey.GetValue("Version") != null) {
                    result.Add(ndpKey.GetValue("Version") + "  Client"); 
                }
                else if(ndpKey.GetValue("Release") != null) {
                    result.Add(CheckFor45DotVersion((int) ndpKey.GetValue("Release")) + "  Client");
                }
            } 
        }
        
        return result;
    }
    
        // Checking the version using >= will enable forward compatibility, 
    // however you should always compile your code on newer versions of
    // the framework to ensure your app works the same.
    private static string CheckFor45DotVersion(int releaseKey)
    {
    if (releaseKey >= 393295) {
        return "4.6 or later";
    }
    if ((releaseKey >= 379893)) {
            return "4.5.2 or later";
        }
        if ((releaseKey >= 378675)) {
            return "4.5.1 or later";
        }
        if ((releaseKey >= 378389)) {
            return "4.5 or later";
        }
        // This line should never execute. A non-null release key should mean
        // that 4.5 or later is installed.
        return releaseKey.ToString();
    }
}
