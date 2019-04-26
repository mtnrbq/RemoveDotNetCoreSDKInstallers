# Removes .net core SDKs, leaving only the latest based on Major.Minor
# Main starts at line 164


Function Get-Software {
  # Original version by Boe Prox at https://mcpmag.com/articles/2017/07/27/gathering-installed-software-using-powershell.aspx
  # Boe Prox - blog: http://learn-powershell.net
  # Adapted by mtnrbq
  [OutputType('System.Software.Inventory')]
  [Cmdletbinding()] 
  Param( 
    [Parameter(ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)] 
    [String[]]$Computername = $env:COMPUTERNAME,
    #mtnrbq - move exclusions to a default parameter
    [String]$Notmatch = '^Update  for|rollup|^Security Update|^Service Pack|^HotFix',
    #mtnrbq - add explicti match parameter
    [String]$Match = '.*'
  )         
  Begin {
  }
  Process {     
    ForEach ($Computer in  $Computername) { 
      If (Test-Connection -ComputerName  $Computer -Count  1 -Quiet) {
        $Paths = @("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "SOFTWARE\\Wow6432node\\Microsoft\\Windows\\CurrentVersion\\Uninstall")         
        ForEach ($Path in $Paths) { 
          Write-Verbose  "Checking Path: $Path"
          #  Create an instance of the Registry Object and open the HKLM base key 
          Try { 
            $reg = [microsoft.win32.registrykey]::OpenRemoteBaseKey('LocalMachine', $Computer, 'Registry64') 
          }
          Catch { 
            Write-Error $_ 
            Continue 
          } 
          #  Drill down into the Uninstall key using the OpenSubKey Method 
          Try {
            $regkey = $reg.OpenSubKey($Path)  
            # Retrieve an array of string that contain all the subkey names 
            $subkeys = $regkey.GetSubKeyNames()      
            # Open each Subkey and use GetValue Method to return the required  values for each 
            ForEach ($key in $subkeys) {   
              Write-Verbose "Key: $Key"
              $thisKey = $Path + "\\" + $key 
              Try {  
                $thisSubKey = $reg.OpenSubKey($thisKey)   
                # Prevent Objects with empty DisplayName , and discard and include based on NotMatch and Macth parameters
                $DisplayName = $thisSubKey.getValue("DisplayName")
                If ($DisplayName  `
                    -AND $DisplayName -notmatch $NotMatch `
                    -AND $DisplayName -match $Match) {

                  #Retrieve any named captures used in the match expression
                  $NamedCaptures = $Matches.GetEnumerator() | Where-Object{ $_.key.GetType().FullName -eq "System.String" }

                  $Date = $thisSubKey.GetValue('InstallDate')
                  If ($Date) {
                    Try {
                      $Date = [datetime]::ParseExact($Date, 'yyyyMMdd', $Null)
                    }
                    Catch {
                      Write-Warning "$($Computer): $_ <$($Date)>"
                      $Date = $Null
                    }
                  } 
                  # Create New Object with empty Properties 
                  $Publisher = Try {
                    $thisSubKey.GetValue('Publisher').Trim()
                  } 
                  Catch {
                    $thisSubKey.GetValue('Publisher')
                  }
                  $Version = Try {
                    #Some weirdness with trailing [char]0 on some strings
                    $thisSubKey.GetValue('DisplayVersion').TrimEnd(([char[]](32, 0)))
                  } 
                  Catch {
                    $thisSubKey.GetValue('DisplayVersion')
                  }
                  $UninstallString = Try {
                    $thisSubKey.GetValue('UninstallString').Trim()
                  } 
                  Catch {
                    $thisSubKey.GetValue('UninstallString')
                  }
                  $InstallLocation = Try {
                    $thisSubKey.GetValue('InstallLocation').Trim()
                  } 
                  Catch {
                    $thisSubKey.GetValue('InstallLocation')
                  }
                  $InstallSource = Try {
                    $thisSubKey.GetValue('InstallSource').Trim()
                  } 
                  Catch {
                    $thisSubKey.GetValue('InstallSource')
                  }
                  $HelpLink = Try {
                    $thisSubKey.GetValue('HelpLink').Trim()
                  } 
                  Catch {
                    $thisSubKey.GetValue('HelpLink')
                  }
                  $Object = [pscustomobject]@{
                    Computername    = $Computer
                    Key             = $key
                    DisplayName     = $DisplayName
                    Version         = $Version
                    InstallDate     = $Date
                    Publisher       = $Publisher
                    UninstallString = $UninstallString
                    InstallLocation = $InstallLocation
                    InstallSource   = $InstallSource
                    HelpLink        = $HelpLink
                    EstimatedSizeMB = [decimal]([math]::Round(($thisSubKey.GetValue('EstimatedSize') * 1024) / 1MB, 2))
                  }
                  ForEach($capture in $NamedCaptures){
                    $Object | Add-Member -MemberType NoteProperty -Name $capture.Name -Value $capture.Value
                  }
                  $Object.pstypenames.insert(0, 'System.Software.Inventory')
                  Write-Output $Object
                }
              }
              Catch {
                Write-Warning "$Key : $_"
              }   
            }
          }
          Catch { }   
          $reg.Close() 
        }                  
      }
      Else {
        Write-Error  "$($Computer): unable to reach remote system!"
      }
    } 
  } 
}  

Function Remove-Software {
  [Cmdletbinding()] 
  Param( 
    [Parameter(ValueFromPipeline = $True, Mandatory = $True)] 
    [Object[]]$SoftwareToBeRemoved
  )         
  Begin {
  }
  Process {
    ForEach ($SoftwareInstall in  $SoftwareToBeRemoved) {
      try {
        $uninstallExe = ($SoftwareInstall.UninstallString.Split('/')[0]).Replace('"','').Trim()
        $uninstallArguments = ("/quiet /" + ($SoftwareInstall.UninstallString.Split('/')[1]).Replace(@('{','}'),'').Trim()) 
        Write-Output  ("Starting uninstall of " + $SoftwareInstall.DisplayName + "...")
        Start-Process $uninstallExe -wait -ArgumentList $uninstallArguments
        Write-Output  ("Uninstalled " + $SoftwareInstall.DisplayName + ".")
      }
      catch {
        Write-Error  "Error trying to uninstall " $SoftwareInstall.DisplayName
        Write-Error  "UninstallString: " $SoftwareInstall.UninstallString
      }
    }
  } 
}

$sh=Get-Software -Match '^Microsoft .NET Core SDK.*(?<dnv>(?<dnvMajorMinor>\d\.\d)\.(?<dnvPatch>\d+)).*'
$uninstallable = $sh | Where-Object UninstallString -match "(.*\/x{|\/uninstall)"
$latestByMajorMinor = $uninstallable | Group-Object dnvMajorMinor | ForEach-Object { $_.Group | Sort-Object Version -Descending | Select-Object dnv -First 1}
$shouldBeUninstalled = $uninstallable | Where-Object { (($latestByMajorMinor).dnv) -NotContains $_.dnv}
if ($shouldBeUninstalled) {
  
}  Remove-Software $shouldBeUninstalled