#// Copyright (c) Microsoft Corporation.
#// Licensed under the MIT license.
using module .\PowerShellBasedConfiguration.psm1
Import-Module -Name ImportExcel
$date = Get-date
Write-Host "Info" "Timestamp is $date"
Set-StrictMode -version 1
$ErrorActionPreference = "Stop"
$kubernetesNodeProfile = "Standard_F16s_HPN"
function Write-Log($level, $message) {
    Write-Host $message
}
$ipAddressRegex = "^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$"
function Validate-IpAddress($address) {
    if($address -notmatch $ipAddressRegex)
    {
        Write-Host "Error" "`"$address`" is not a valid IP address"
        Exit 1
    }
}
$subnetMaskRegex = "^(((255\.){3}(255|254|252|248|240|224|192|128|0+))|((255\.){2}(255|254|252|248|240|224|192|128|0+)\.0)|((255\.)(255|254|252|248|240|224|192|128|0+)(\.0+){2})|((255|254|252|248|240|224|192|128|0+)(\.0+){3}))$"
function Validate-SubnetMask($mask) {
    if($mask -notmatch $subnetMaskRegex)
    {
        Write-Host "Error" "`"$mask`" is not a valid subnet mask"
        Exit 1
    }
}
function Validate-IpAddressInSubnet {
    [cmdletbinding()]
    param(
        [string] $address,
        [string] $network,
        [string] $mask
    )
    $ipAddress = $address -as [IPAddress]
    $networkAddress = $network -as [IPAddress]
    $subnetMask = $mask -as [IPAddress]
    $ipAdressBytes = $ipAddress.GetAddressBytes();
    $subnetMaskBytes = $subnetMask.GetAddressBytes();
    $calculatedNetworkAddressBytes = [System.Byte[]]::CreateInstance([System.Byte], $ipAdressBytes.Length);
    for (($i=0); $i -lt $calculatedNetworkAddressBytes.Length; $i++)
    {
        $calculatedNetworkAddressBytes[$i] = ($ipAdressBytes[$i] -band $subnetMaskBytes[$i]);
    }
    $calculatedNetworkAddress = [System.Net.IPAddress]($calculatedNetworkAddressBytes)
    if($calculatedNetworkAddress -ne $networkAddress)
    {
        Write-Host "Error" "`"$address`" is not in the network `"$network`" when using subnet mask `"$mask`""
        Exit 1
    }
}
$ipAddressRangeRegex = "^(?:([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])-(?:([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$"
function Validate-KubernetesNodeIps ($range) {
    if($range -notmatch $ipAddressRangeRegex)
    {
        Write-Host "Error" "$range is not a valid IP address range. The range must be in the format `"<FirstIP>-<LastIP>`""
        Exit 1
    }
    $match = $range | Select-String -Pattern $ipAddressRangeRegex
    if ($match.Matches.Groups[1].Value -ne $match.Matches.Groups[3].Value)
    {
        Write-Host "Error" "`"$range`" must be within a single /24 subnet"
        Exit 1
    }
    if ($match.Matches.Groups[4].Value - $match.Matches.Groups[2].Value -ne 5)
    {
        Write-Host "Error" "`"$range`" must contain 6 contiguous IP addresses"
        Exit 1
    }
}
function Validate-KubernetesServiceIps {
    param(
        [string] $range,
        [string] $kubernetesNodeIps
    )
    if($range -notmatch $ipAddressRangeRegex)
    {
        Write-Host "Error" "`"$range`" is not a valid IP address range"
        Exit 1
    }
    $match = $range | Select-String -Pattern $ipAddressRangeRegex
    if ($match.Matches.Groups[1].Value -ne $match.Matches.Groups[3].Value)
    {
        Write-Host "Error" "`"$range`" must be within a single /24 subnet"
        Exit 1
    }
    $size = $match.Matches.Groups[4].Value - $match.Matches.Groups[2].Value
    if (($size -ne 0) -and ($size -ne 1))
    {
        Write-Host "Error" "`"$range`" must contain 1 or 2 contiguous IP addresses"
        Exit 1
    }
    $kubernetesNodeIpsMatch = $kubernetesNodeIps | Select-String -Pattern $ipAddressRangeRegex
    if ($match.Matches.Groups[1].Value -ne $kubernetesNodeIpsMatch.Matches.Groups[1].Value)
    {
        Write-Host "Error" "`"$range`" and `"$kubernetesNodeIps`" must be in the same /24 subnet"
        Exit 1
    }
}
function Validate-Guid($guidString) {
    $guid = [System.Guid]::New($guidString)
    if($guid -eq [System.Guid]::empty)
    {
        Write-Host "Error" "$guidString is not a valid GUID"
        Exit 1
    }
}
$arcResourceNameRegex = "^[a-zA-Z][a-zA-Z0-9-]*$"
function Validate-ArcResourceName($name) {
    $name
    if($name -notmatch $arcResourceNameRegex)
    {
        Write-Host "Error" "`"$name`" is not a valid resource name. Valid names can contain only alphanumeric characters and dashes. The name must start with a letter."
        Exit 1
    }
}
Import-Excel .\parameters_file_single_ASE_AP5GC.xlsx | Export-Csv -Delimiter ',' -Path .\one_script_csv.csv -NoTypeInformation
$csvfile = import-csv .\one_script_csv.csv -Delimiter ","
    foreach ($row in $csvfile) {
        if($row.Parameter -eq "ASEip")
      {
            Validate-IpAddress($row.value)
            $ASEip = $row.value
      }
        if($row.Parameter -eq "defaultASEPassword")
      {
            $defaultASEPassword = $row.value
      }
        if($row.Parameter -eq "trustSelfSignedCertificate")
      {
            $trustSelfSignedCertificate = $row.value
      }
        if($row.Parameter -eq "oid")
      {
            Validate-Guid($row.value)
            $oid = $row.value
      }
        if($row.Parameter -eq "subscriptionId")
      {
            Validate-Guid($row.value)
            $subscriptionId = $row.value
      }
        if($row.Parameter -eq "ASEresourceGroup")
      {
            $ASEresourceGroup = $row.value
      }
        if($row.Parameter -eq "tenantId")
      {
            Validate-Guid($row.value)
            $tenantId = $row.value
      }
        if($row.Parameter -eq "arcLocation")
      {
            $arcLocation = $row.value
      }
        if($row.Parameter -eq "vSwitchMgmtPortName")
      {
            $vSwitchMgmtPortName = $row.value
      }
        if($row.Parameter -eq "vSwitchMgmtPortAlias")
      {
            $vSwitchMgmtPortAlias = $row.value
      }
        if($row.Parameter -eq "computeKubernetesNodeIps")
      {
            Validate-KubernetesNodeIps $row.value
            $computeKubernetesNodeIps = $row.value
      }
        if($row.Parameter -eq "computeKubernetesServiceIps")
      {
            Validate-KubernetesServiceIps $row.value $computeKubernetesNodeIps
            $computeKubernetesServiceIps = $row.value
      }
        if($row.Parameter -eq "vSwitchACCESSPortName")
      {
            $vSwitchACCESSPortName = $row.value
      }
        if($row.Parameter -eq "vSwitchACCESSPortAlias")
      {
            $vSwitchACCESSPortAlias = $row.value
      }
        if($row.Parameter -eq "vSwitchDATAPortName")
      {
            $vSwitchDATAPortName = $row.value
      }
        if($row.Parameter -eq "vSwitchDATAPortAlias")
      {
            $vSwitchDATAPortAlias = $row.value
      }
        if($row.Parameter -eq "N2vSwitchName")
      {
            $N2vSwitchName = $row.value
      }
        if($row.Parameter -eq "N3vSwitchName")
      {
            $N3vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN1vSwitchName")
      {
            $N6DNN1vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN2vSwitchName")
      {
            $N6DNN2vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN3vSwitchName")
      {
            $N6DNN3vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN4vSwitchName")
      {
            $N6DNN4vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN5vSwitchName")
      {
            $N6DNN5vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN6vSwitchName")
      {
            $N6DNN6vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN7vSwitchName")
      {
            $N6DNN7vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN8vSwitchName")
      {
            $N6DNN8vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN9vSwitchName")
      {
            $N6DNN9vSwitchName = $row.value
      }
        if($row.Parameter -eq "N6DNN10vSwitchName")
      {
            $N6DNN10vSwitchName = $row.value
      }
        if($row.Parameter -eq "n2SubnetMask")
      {
            Validate-SubnetMask($row.value)
            $n2SubnetMask = $row.value
      }
        if($row.Parameter -eq "n2Network")
      {
            Validate-IpAddress($row.value)
            $n2Network = $row.value
      }
        if($row.Parameter -eq "n2Gateway")
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n2Network $n2SubnetMask
            $n2Gateway = $row.value
      }
        if($row.Parameter -eq "n2IP")
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n2Network $n2SubnetMask
            $n2IP = $row.value
      }
        if($row.Parameter -eq "n3SubnetMask")
      {
            Validate-SubnetMask($row.value)
            $n3SubnetMask = $row.value
      }
        if($row.Parameter -eq "n3Network")
      {
            Validate-IpAddress($row.value)
            $n3Network = $row.value
      }
        if($row.Parameter -eq "n3Gateway")
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n3Network $n3SubnetMask
            $n3Gateway = $row.value
      }
        if($row.Parameter -eq "n3IP")
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n3Network $n3SubnetMask
            $n3IP = $row.value
      }
        if($row.Parameter -eq "numberofDNNs")
      {
            $numberofDNNs = $row.value -as [int]
            if(($numberofDNNs -lt 1) -or ($numberofDNNs -gt 10))
            {
                Write-Host "Error" "Number of DNNs $numberofDNNs must be between 1 and 10"
                Exit 1
            }
      }
        if($row.Parameter -eq "customLocationName")
      {
            Validate-ArcResourceName($row.value)
            $customLocationName = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN1" -and $numberofDNNs -gt 0)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN1 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN2" -and $numberofDNNs -gt 1)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN2 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN3" -and $numberofDNNs -gt 2)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN3 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN4" -and $numberofDNNs -gt 3)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN4 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN5" -and $numberofDNNs -gt 4)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN5 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN6" -and $numberofDNNs -gt 5)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN6 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN7" -and $numberofDNNs -gt 6)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN7 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN8" -and $numberofDNNs -gt 7)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN8 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN9" -and $numberofDNNs -gt 8)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN9 = $row.value
      }
        if($row.Parameter -eq "n6SubnetMaskDNN10" -and $numberofDNNs -gt 9)
      {
            Validate-SubnetMask($row.value)
            $n6SubnetMaskDNN10 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN1" -and $numberofDNNs -gt 0)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN1 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN2" -and $numberofDNNs -gt 1)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN2 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN3" -and $numberofDNNs -gt 2)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN3 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN4" -and $numberofDNNs -gt 3)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN4 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN5" -and $numberofDNNs -gt 4)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN5 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN6" -and $numberofDNNs -gt 5)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN6 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN7" -and $numberofDNNs -gt 6)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN7 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN8" -and $numberofDNNs -gt 7)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN8 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN9" -and $numberofDNNs -gt 8)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN9 = $row.value
      }
        if($row.Parameter -eq "n6NetworkDNN10" -and $numberofDNNs -gt 9)
      {
            Validate-IpAddress($row.value)
            $n6NetworkDNN10 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN1" -and $numberofDNNs -gt 0)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN1 $n6SubnetMaskDNN1
            $n6GatewayDNN1 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN2" -and $numberofDNNs -gt 1)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN2 $n6SubnetMaskDNN2
            $n6GatewayDNN2 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN3" -and $numberofDNNs -gt 2)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN3 $n6SubnetMaskDNN3
            $n6GatewayDNN3 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN4" -and $numberofDNNs -gt 3)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN4 $n6SubnetMaskDNN4
            $n6GatewayDNN4 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN5" -and $numberofDNNs -gt 4)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN5 $n6SubnetMaskDNN5
            $n6GatewayDNN5 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN6" -and $numberofDNNs -gt 5)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN6 $n6SubnetMaskDNN6
            $n6GatewayDNN6 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN7" -and $numberofDNNs -gt 6)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN7 $n6SubnetMaskDNN7
            $n6GatewayDNN7 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN8" -and $numberofDNNs -gt 7)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN8 $n6SubnetMaskDNN8
            $n6GatewayDNN8 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN9" -and $numberofDNNs -gt 8)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN9 $n6SubnetMaskDNN9
            $n6GatewayDNN9 = $row.value
      }
        if($row.Parameter -eq "n6GatewayDNN10" -and $numberofDNNs -gt 9)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN10 $n6SubnetMaskDNN10
            $n6GatewayDNN10 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN1" -and $numberofDNNs -gt 0)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN1 $n6SubnetMaskDNN1
            $n6IPDNN1 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN2" -and $numberofDNNs -gt 1)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN2 $n6SubnetMaskDNN2
            $n6IPDNN2 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN3" -and $numberofDNNs -gt 2)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN3 $n6SubnetMaskDNN3
            $n6IPDNN3 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN4" -and $numberofDNNs -gt 3)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN4 $n6SubnetMaskDNN4
            $n6IPDNN4 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN5" -and $numberofDNNs -gt 4)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN5 $n6SubnetMaskDNN5
            $n6IPDNN5 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN6" -and $numberofDNNs -gt 5)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN6 $n6SubnetMaskDNN6
            $n6IPDNN6 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN7" -and $numberofDNNs -gt 6)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN7 $n6SubnetMaskDNN7
            $n6IPDNN7 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN8" -and $numberofDNNs -gt 7)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN8 $n6SubnetMaskDNN8
            $n6IPDNN8 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN9" -and $numberofDNNs -gt 8)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN9 $n6SubnetMaskDNN9
            $n6IPDNN9 = $row.value
      }
        if($row.Parameter -eq "n6IPDNN10" -and $numberofDNNs -gt 9)
      {
            Validate-IpAddress($row.value)
            Validate-IpAddressInSubnet $row.value $n6NetworkDNN10 $n6SubnetMaskDNN10
            $n6IPDNN10 = $row.value
      }
        if($row.Parameter -eq "N2vlanId")
      {
            $N2vlanId = $row.value
      }
        if($row.Parameter -eq "N3vlanId")
      {
            $N3vlanId = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN1")
      {
            $N6vlanIdDNN1 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN2")
      {
            $N6vlanIdDNN2 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN3")
      {
            $N6vlanIdDNN3 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN4")
      {
            $N6vlanIdDNN4 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN5")
      {
            $N6vlanIdDNN5 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN6")
      {
            $N6vlanIdDNN6 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN7")
      {
            $N6vlanIdDNN7 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN8")
      {
            $N6vlanIdDNN8 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN9")
      {
            $N6vlanIdDNN9 = $row.value
      }
        if($row.Parameter -eq "N6vlanIdDNN10")
      {
            $N6vlanIdDNN10 = $row.value
      }
        if($row.Parameter -eq "mtuASE")
      {
            $mtuASE = $row.value
      }
        if($row.Parameter -eq "arcClusterName")
      {
            Validate-ArcResourceName($row.value)
            $arcClusterName = $row.value
      }
        if($row.Parameter -eq "mobileNetworkRGName")
      {
            $mobileNetworkRGName = $row.value
      }
        if($row.Parameter -eq "location")
      {
            $location = $row.value
      }
        if($row.Parameter -eq "mobileNetworkName")
      {
            $mobileNetworkName = $row.value
      }
        if($row.Parameter -eq "mobileNetworkRGNameLocation")
      {
            $mobileNetworkRGNameLocation = $row.value
      }
        if($row.Parameter -eq "mobileCountryCode")
      {
            $mobileCountryCode = $row.value
      }
        if($row.Parameter -eq "mobileNetworkCode")
      {
            $mobileNetworkCode = $row.value
      }
        if($row.Parameter -eq "siteName")
      {
            $siteName = $row.value
      }
        if($row.Parameter -eq "serviceName")
      {
            $serviceName = $row.value
      }
        if($row.Parameter -eq "simPolicyName")
      {
            $simPolicyName = $row.value
      }
        if($row.Parameter -eq "sliceName")
      {
            $sliceName = $row.value
      }
        if($row.Parameter -eq "simGroupName")
      {
            $simGroupName = $row.value
      }
        if($row.Parameter -eq "azureStackEdgeDevice")
      {
            $azureStackEdgeDevice = $row.value
      }
        if($row.Parameter -eq "userPlaneDataInterfaceName")
      {
            $userPlaneDataInterfaceName = $row.value
      }
        if($row.Parameter -eq "userEquipmentAddressPoolPrefix")
      {
            $userEquipmentAddressPoolPrefix = $row.value
      }
        if($row.Parameter -eq "userEquipmentStaticAddressPoolPrefix")
      {
            $userEquipmentStaticAddressPoolPrefix = $row.value
      }
        if($row.Parameter -eq "dataNetworkName")
      {
            $dataNetworkName = $row.value
      }
        if($row.Parameter -eq "coreNetworkTechnology")
      {
            $coreNetworkTechnology = $row.value
      }
        if($row.Parameter -eq "naptEnabled")
      {
            $naptEnabled = $row.value
      }
        if($row.Parameter -eq "dnsAddresses")
      {
            $dnsAddresses = $row.value
      }
    }
Write-Host "Info" "Number of DNNs is $numberofDNNs"
$json = @"
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "ASEip": {
            "value": "$ASEip"
        },
        "defaultASEPassword": {
            "value": "$defaultASEPassword"
        },
        "trustSelfSignedCertificate": {
            "value": "$trustSelfSignedCertificate"
        },
        "oid": {
            "value": "$oid"
        },
        "KubernetesNodeProfile": {
            "value": "$kubernetesNodeProfile"
        },
        "subscriptionId": {
            "value": "$subscriptionId"
        },
        "ASEresourceGroup": {
            "value": "$ASEresourceGroup"
        },
        "ASEname": {
            "value": "$azureStackEdgeDevice"
        },
        "tenantId": {
            "value": "$tenantId"
        },
        "arcLocation": {
            "value": "$arcLocation"
        },
        "vSwitchMgmtPortName": {
            "value": "$vSwitchMgmtPortName"
        },
        "vSwitchMgmtPortAlias": {
            "value": "$vSwitchMgmtPortAlias"
        },
        "computeKubernetesNodeIps": {
            "value": "$computeKubernetesNodeIps"
        },
        "computeKubernetesServiceIps": {
            "value": "$computeKubernetesServiceIps"
        },
        "vSwitchACCESSPortName": {
            "value": "$vSwitchACCESSPortName"
        },
        "vSwitchACCESSPortAlias": {
            "value": "$vSwitchACCESSPortAlias"
        },
        "vSwitchDATAPortName": {
            "value": "$vSwitchDATAPortName"
        },
        "vSwitchDATAPortAlias": {
            "value": "$vSwitchDATAPortAlias"
        },
        "N2vSwitchName": {
            "value": "$N2vSwitchName"
        },
        "N3vSwitchName": {
            "value": "$N3vSwitchName"
        },
        "N6DNN1vSwitchName": {
            "value": "$N6DNN1vSwitchName"
        },
        "N6DNN2vSwitchName": {
            "value": "$N6DNN2vSwitchName"
        },
        "N6DNN3vSwitchName": {
            "value": "$N6DNN3vSwitchName"
        },
        "N6DNN4vSwitchName": {
            "value": "$N6DNN4vSwitchName"
        },
        "N6DNN5vSwitchName": {
            "value": "$N6DNN5vSwitchName"
        },
        "N6DNN6vSwitchName": {
            "value": "$N6DNN6vSwitchName"
        },
        "N6DNN7vSwitchName": {
            "value": "$N6DNN7vSwitchName"
        },
        "N6DNN8vSwitchName": {
            "value": "$N6DNN8vSwitchName"
        },
        "N6DNN9vSwitchName": {
            "value": "$N6DNN9vSwitchName"
        },
        "N6DNN10vSwitchName": {
            "value": "$N6DNN10vSwitchName"
        },
        "mtuASE": {
            "value": "$mtuASE"
        },
        "n2SubnetMask": {
            "value": "$n2SubnetMask"
        },
        "n2Gateway": {
            "value": "$n2Gateway"
        },
        "n2Network": {
            "value": "$n2Network"
        },
        "n3SubnetMask": {
            "value": "$n3SubnetMask"
        },
        "n3Gateway": {
            "value": "$n3Gateway"
        },
        "n3Network": {
            "value": "$n3Network"
        },
        "n2IP": {
            "value": "$n2IP-$n2IP"
        },
        "n3IP": {
            "value": "$n3IP-$n3IP"
        },
        "n6IPDNN1": {
            "value": "$n6IPDNN1-$n6IPDNN1"
        },
        "n6IPDNN2": {
            "value": "$n6IPDNN2-$n6IPDNN2"
        },
        "n6IPDNN3": {
            "value": "$n6IPDNN3-$n6IPDNN3"
        },
        "n6IPDNN4": {
            "value": "$n6IPDNN4-$n6IPDNN4"
        },
        "n6IPDNN5": {
            "value": "$n6IPDNN5-$n6IPDNN5"
        },
        "n6IPDNN6": {
            "value": "$n6IPDNN6-$n6IPDNN6"
        },
        "n6IPDNN7": {
            "value": "$n6IPDNN7-$n6IPDNN7"
        },
        "n6IPDNN8": {
            "value": "$n6IPDNN8-$n6IPDNN8"
        },
        "n6IPDNN9": {
            "value": "$n6IPDNN9-$n6IPDNN9"
        },
        "n6IPDNN10": {
            "value": "$n6IPDNN10-$n6IPDNN10"
        },
        "customLocationName": {
            "value": "$customLocationName"
        },
        "N2vlanId": {
            "value": "$N2vlanId"
        },
        "N3vlanId": {
            "value": "$N3vlanId"
        },
        "N6vlanIdDNN1": {
            "value": "$N6vlanIdDNN1"
        },
        "N6vlanIdDNN2": {
            "value": "$N6vlanIdDNN2"
        },
        "N6vlanIdDNN3": {
            "value": "$N6vlanIdDNN3"
        },
        "N6vlanIdDNN4": {
            "value": "$N6vlanIdDNN4"
        },
        "N6vlanIdDNN5": {
            "value": "$N6vlanIdDNN5"
        },
        "N6vlanIdDNN6": {
            "value": "$N6vlanIdDNN6"
        },
        "N6vlanIdDNN7": {
            "value": "$N6vlanIdDNN7"
        },
        "N6vlanIdDNN8": {
            "value": "$N6vlanIdDNN8"
        },
        "N6vlanIdDNN9": {
            "value": "$N6vlanIdDNN9"
        },
        "N6vlanIdDNN10": {
            "value": "$N6vlanIdDNN10"
        },
        "n6SubnetMaskDNN1": {
            "value": "$n6SubnetMaskDNN1"
        },
        "n6SubnetMaskDNN2": {
            "value": "$n6SubnetMaskDNN2"
        },
        "n6SubnetMaskDNN3": {
            "value": "$n6SubnetMaskDNN3"
        },
        "n6SubnetMaskDNN4": {
            "value": "$n6SubnetMaskDNN4"
        },
        "n6SubnetMaskDNN5": {
            "value": "$n6SubnetMaskDNN5"
        },
        "n6SubnetMaskDNN6": {
            "value": "$n6SubnetMaskDNN6"
        },
        "n6SubnetMaskDNN7": {
            "value": "$n6SubnetMaskDNN7"
        },
        "n6SubnetMaskDNN8": {
            "value": "$n6SubnetMaskDNN8"
        },
        "n6SubnetMaskDNN9": {
            "value": "$n6SubnetMaskDNN9"
        },
        "n6SubnetMaskDNN10": {
            "value": "$n6SubnetMaskDNN10"
        },
        "n6GatewayDNN1": {
            "value": "$n6GatewayDNN1"
        },
        "n6GatewayDNN2": {
            "value": "$n6GatewayDNN2"
        },
        "n6GatewayDNN3": {
            "value": "$n6GatewayDNN3"
        },
        "n6GatewayDNN4": {
            "value": "$n6GatewayDNN4"
        },
        "n6GatewayDNN5": {
            "value": "$n6GatewayDNN5"
        },
        "n6GatewayDNN6": {
            "value": "$n6GatewayDNN6"
        },
        "n6GatewayDNN7": {
            "value": "$n6GatewayDNN7"
        },
        "n6GatewayDNN8": {
            "value": "$n6GatewayDNN8"
        },
        "n6GatewayDNN9": {
            "value": "$n6GatewayDNN9"
        },
        "n6GatewayDNN10": {
            "value": "$n6GatewayDNN10"
        },
        "n6NetworkDNN1": {
            "value": "$n6NetworkDNN1"
        },
        "n6NetworkDNN2": {
            "value": "$n6NetworkDNN2"
        },
        "n6NetworkDNN3": {
            "value": "$n6NetworkDNN3"
        },
        "n6NetworkDNN4": {
            "value": "$n6NetworkDNN4"
        },
        "n6NetworkDNN5": {
            "value": "$n6NetworkDNN5"
        },
        "n6NetworkDNN6": {
            "value": "$n6NetworkDNN6"
        },
        "n6NetworkDNN7": {
            "value": "$n6NetworkDNN7"
        },
        "n6NetworkDNN8": {
            "value": "$n6NetworkDNN8"
        },
        "n6NetworkDNN9": {
            "value": "$n6NetworkDNN9"
        },
        "n6NetworkDNN10": {
            "value": "$n6NetworkDNN10"
        },
        "arcClusterName": {
            "value": "$arcClusterName"
        },
        "mobileNetworkRGName": {
            "value": "$mobileNetworkRGName"
        },
        "mobileNetworkRGNameLocation": {
            "value": "$mobileNetworkRGNameLocation"
        }
    }
}
"@
$json | out-file "$($PSScriptRoot)/csv_in_json1.json"
(Get-Content "$($PSScriptRoot)/csv_in_json1.json").replace('"": "https://schema', '"$schema": "https://schema') | Set-Content "$($PSScriptRoot)/csv_in_jsonASE.json"
$json = @"
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": {
            "value": "$location"
        },
        "mobileNetworkName": {
            "value": "$mobileNetworkName"
        },
        "mobileCountryCode": {
            "value": "$mobileCountryCode"
        },
        "mobileNetworkCode": {
            "value": "$mobileNetworkCode"
        },
        "siteName": {
            "value": "$siteName"
        },
        "serviceName": {
            "value": "$serviceName"
        },
        "simPolicyName": {
            "value": "$simPolicyName"
        },
        "sliceName": {
            "value": "$sliceName"
        },
        "simGroupName": {
            "value": "$simGroupName"
        },
        "simResources": {
            "value": []
        },
        "azureStackEdgeDevice": {
            "value": "/subscriptions/$subscriptionId/resourcegroups/$ASEresourceGroup/providers/Microsoft.DataBoxEdge/dataBoxEdgeDevices/$azureStackEdgeDevice"
        },
        "controlPlaneAccessInterfaceName": {
            "value": "$N2vSwitchName"
        },
        "controlPlaneAccessIpAddress": {
            "value": "$n2IP"
        },
        "userPlaneAccessInterfaceName": {
            "value": "$N3vSwitchName"
        },
        "userPlaneDataInterfaceName": {
            "value": "$userPlaneDataInterfaceName"
        },
        "userEquipmentAddressPoolPrefix": {
            "value": "$userEquipmentAddressPoolPrefix"
        },
        "userEquipmentStaticAddressPoolPrefix": {
            "value": "$userEquipmentStaticAddressPoolPrefix"
        },
        "dataNetworkName": {
            "value": "$dataNetworkName"
        },
        "coreNetworkTechnology": {
            "value": "$coreNetworkTechnology"
        },
        "naptEnabled": {
            "value": "$naptEnabled"
        },
        "dnsAddresses": {
            "value": ["$dnsAddresses"]
        },
        "customLocation": {
            "value": "/subscriptions/$subscriptionId/resourcegroups/$ASEresourceGroup/providers/microsoft.extendedlocation/customlocations/$customLocationName"
        }
    }
}
"@
$json | out-file "$($PSScriptRoot)/csv_in_json2.json"
(Get-Content "$($PSScriptRoot)/csv_in_json2.json").replace('"": "https://schema', '"$schema": "https://schema') | Set-Content "$($PSScriptRoot)/csv_in_jsonMN.json"
#### REST OF THE SCRIPT #####
function InitializeAP5GC
{
    $a = Get-Content -Raw "$($PSScriptRoot)/csv_in_jsonASE.json" | ConvertFrom-Json
    $subscriptionId = $a.parameters.subscriptionId.value
    $tenantId = $a.parameters.tenantId.value
    $ASEname = $a.parameters.ASEname.value
    $ASEresourceGroup = $a.parameters.ASEresourceGroup.value
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Running Connect-AzAccount for tenant id: $tenantId and sub id: $subscriptionId"
    Connect-AzAccount -Tenant $tenantId -SubscriptionId $subscriptionId
    Write-Host "Info" "Running Set-AzAccount for sub id: $subscriptionId"
    Set-AzContext -Subscription $a.parameters.subscriptionId.value
    Write-Host "Info" "Using the following input parameters to setup ASE $($a | ConvertTo-Json -Depth 6)"
#>
# Enable AKS for AP5GC on ASE #
    $ASEip = $a.parameters.ASEip.value
    $username = "~\EdgeUser"
    $secPassword = ConvertTo-SecureString $a.parameters.defaultASEPassword.value -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($username, $secPassword)
    $sessopt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $minishellSession = New-PSSession -ComputerName $ASEip -ConfigurationName "Minishell" -Credential $cred -UseSSL -SessionOption $sessopt
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Enable AKS for AP5GC on ASE"
    Invoke-Command -Session $minishellSession -ScriptBlock {Set-HcsKubernetesWorkloadProfile -Type "AP5GC"}
    Start-Sleep -Seconds 30
    Write-Host "Info" "Adding all Networking, Advanced Networking, compute port and Kubernetes information to the ASE"
    Write-Host "Info" "Setting login to ASE https://$ASEip"
    Set-Login "https://$ASEip" $a.parameters.defaultASEPassword.value $a.parameters.defaultASEPassword.value $a.parameters.trustSelfSignedCertificate.value
# Get appliance info and check that the version is supported
$applianceInfo = Invoke-Command -Session $minishellSession -ScriptBlock {Get-HcsApplianceInfo}
Write-Host "Appliance info: $($applianceInfo | ConvertTo-Json -Depth 6)"
Write-Host "Sofware version: $($applianceInfo.FriendlySoftwareVersionNumber)"
if (($applianceInfo.FriendlySoftwareVersionNumber -ne "2312") -and ($applianceInfo.FriendlySoftwareVersionNumber -ne "2309"))
{
    Write-Host "Error" "Sofware version `"$($applianceInfo.FriendlySoftwareVersionNumber)`" is not supported. Supported versions are 2312 and 2309"
    Exit 1
}
# Add the delta vswitches, vnetwork, k8s IP's and enable compute
$oldDeviceConfig = Get-DeviceConfiguration
Write-Host "Info" "Current running config on this ASE: $($oldDeviceConfig | ConvertTo-Json -Depth 6)g"
Write-Host "Current device config: $($oldDeviceConfig | ConvertTo-Json -Depth 6)"
$vSwitches = $(if ($applianceInfo.FriendlySoftwareVersionNumber -eq "2312") {@(
    @{
        "name" = $a.parameters.vSwitchMgmtPortName.value
        "interfaces" = @(
            $a.parameters.vSwitchMgmtPortAlias.value
        )
        "enabledForCompute" = $true
        "enabledForStorage" = $false
        "enabledForMgmt" = $false
        "supportsAcceleratedNetworking" = $false
        "enableEmbeddedTeaming" = $false
        "ipAddressPools" = @(
            @{
                "name" = "KubernetesNodeIPs"
                "ipAddressRange" = $a.parameters.computeKubernetesNodeIps.value
            },
            @{
                "name" = "KubernetesServiceIPs"
                "ipAddressRange" = $a.parameters.computeKubernetesServiceIps.value
            }
        )
        "mtu"= $a.parameters.mtuASE.value
    }
    @{
        "name" = $a.parameters.vSwitchACCESSPortName.value
        "interfaces" = @(
            $a.parameters.vSwitchACCESSPortAlias.value
        )
        "enabledForCompute" = $false
        "enabledForStorage" = $false
        "enabledForMgmt" = $false
        "supportsAcceleratedNetworking" = $true
        "enableEmbeddedTeaming" = $false
        "ipAddressPools" = @()
    }
    @{
        "name" = $a.parameters.vSwitchDATAPortName.value
        "interfaces" = @(
            $a.parameters.vSwitchDATAPortAlias.value
        )
        "enabledForCompute" = $false
        "enabledForStorage" = $false
        "enabledForMgmt" = $false
        "supportsAcceleratedNetworking" = $true
        "enableEmbeddedTeaming" = $false
        "ipAddressPools" = @()
    })}
    elseif ($applianceInfo.FriendlySoftwareVersionNumber -eq "2309") {@(
    @{
        "name" = $a.parameters.vSwitchMgmtPortName.value
        "interfaceName" = $a.parameters.vSwitchMgmtPortAlias.value
        "enabledForCompute" = $true
        "enabledForStorage" = $false
        "enabledForMgmt" = $false
        "supportsAcceleratedNetworking" = $false
        "enableEmbeddedTeaming" = $false
        "ipAddressPools" = @(
            @{
                "name" = "KubernetesNodeIPs"
                "ipAddressRange" = $a.parameters.computeKubernetesNodeIps.value
            },
            @{
                "name" = "KubernetesServiceIPs"
                "ipAddressRange" = $a.parameters.computeKubernetesServiceIps.value
            }
        )
        "mtu"= $a.parameters.mtuASE.value
    }
    @{
        "name" = $a.parameters.vSwitchACCESSPortName.value
        "interfaceName" = $a.parameters.vSwitchACCESSPortAlias.value
        "enabledForCompute" = $false
        "enabledForStorage" = $false
        "enabledForMgmt" = $false
        "supportsAcceleratedNetworking" = $true
        "enableEmbeddedTeaming" = $false
        "ipAddressPools" = @()
    }
    @{
        "name" = $a.parameters.vSwitchDATAPortName.value
        "interfaceName" = $a.parameters.vSwitchDATAPortAlias.value
        "enabledForCompute" = $false
        "enabledForStorage" = $false
        "enabledForMgmt" = $false
        "supportsAcceleratedNetworking" = $true
        "enableEmbeddedTeaming" = $false
        "ipAddressPools" = @()
    })}
)
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (1 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (2 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (3 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (4 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (5 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN5vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN5.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN5.value
                            "gateway" = $a.parameters.n6GatewayDNN5.value
                            "network" = $a.parameters.n6NetworkDNN5.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN5.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (6 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN5vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN5.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN5.value
                            "gateway" = $a.parameters.n6GatewayDNN5.value
                            "network" = $a.parameters.n6NetworkDNN5.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN5.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN6vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN6.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN6.value
                            "gateway" = $a.parameters.n6GatewayDNN6.value
                            "network" = $a.parameters.n6NetworkDNN6.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN6.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (7 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN5vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN5.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN5.value
                            "gateway" = $a.parameters.n6GatewayDNN5.value
                            "network" = $a.parameters.n6NetworkDNN5.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN5.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN6vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN6.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN6.value
                            "gateway" = $a.parameters.n6GatewayDNN6.value
                            "network" = $a.parameters.n6NetworkDNN6.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN6.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN7vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN7.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN7.value
                            "gateway" = $a.parameters.n6GatewayDNN7.value
                            "network" = $a.parameters.n6NetworkDNN7.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN7.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (8 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN5vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN5.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN5.value
                            "gateway" = $a.parameters.n6GatewayDNN5.value
                            "network" = $a.parameters.n6NetworkDNN5.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN5.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN6vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN6.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN6.value
                            "gateway" = $a.parameters.n6GatewayDNN6.value
                            "network" = $a.parameters.n6NetworkDNN6.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN6.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN7vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN7.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN7.value
                            "gateway" = $a.parameters.n6GatewayDNN7.value
                            "network" = $a.parameters.n6NetworkDNN7.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN7.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN8vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN8.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN8.value
                            "gateway" = $a.parameters.n6GatewayDNN8.value
                            "network" = $a.parameters.n6NetworkDNN8.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN8.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (9 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN5vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN5.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN5.value
                            "gateway" = $a.parameters.n6GatewayDNN5.value
                            "network" = $a.parameters.n6NetworkDNN5.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN5.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN6vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN6.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN6.value
                            "gateway" = $a.parameters.n6GatewayDNN6.value
                            "network" = $a.parameters.n6NetworkDNN6.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN6.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN7vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN7.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN7.value
                            "gateway" = $a.parameters.n6GatewayDNN7.value
                            "network" = $a.parameters.n6NetworkDNN7.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN7.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN8vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN8.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN8.value
                            "gateway" = $a.parameters.n6GatewayDNN8.value
                            "network" = $a.parameters.n6NetworkDNN8.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN8.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN9vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN9.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN9.value
                            "gateway" = $a.parameters.n6GatewayDNN9.value
                            "network" = $a.parameters.n6NetworkDNN9.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN9.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
        # Add the delta vswitches, vnetwork, k8s IP's and enable compute
        if (10 -eq $numberofDNNs) {$newDeviceConfig = @{
            "device" = @{
                "network" = @{
                    "dhcpPolicy" = $oldDeviceConfig.device.network.dhcpPolicy
                    "interfaces" = $oldDeviceConfig.device.network.interfaces
                    "vSwitches" = $vSwitches
                    "virtualNetworks" = @(
                        @{
                            "name" = $a.parameters.N2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N2vlanId.value
                            "subnetMask" = $a.parameters.n2SubnetMask.value
                            "gateway" = $a.parameters.n2Gateway.value
                            "network" = $a.parameters.n2Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n2IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" =  $a.parameters.N3vlanId.value
                            "subnetMask" = $a.parameters.n3SubnetMask.value
                            "gateway" = $a.parameters.n3Gateway.value
                            "network" = $a.parameters.n3Network.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n3IP.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN1vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN1.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN1.value
                            "gateway" = $a.parameters.n6GatewayDNN1.value
                            "network" = $a.parameters.n6NetworkDNN1.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN1.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN2vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN2.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN2.value
                            "gateway" = $a.parameters.n6GatewayDNN2.value
                            "network" = $a.parameters.n6NetworkDNN2.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN2.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN3vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN3.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN3.value
                            "gateway" = $a.parameters.n6GatewayDNN3.value
                            "network" = $a.parameters.n6NetworkDNN3.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN3.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN4vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN4.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN4.value
                            "gateway" = $a.parameters.n6GatewayDNN4.value
                            "network" = $a.parameters.n6NetworkDNN4.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN4.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN5vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN5.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN5.value
                            "gateway" = $a.parameters.n6GatewayDNN5.value
                            "network" = $a.parameters.n6NetworkDNN5.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN5.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN6vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchDATAPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN6.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN6.value
                            "gateway" = $a.parameters.n6GatewayDNN6.value
                            "network" = $a.parameters.n6NetworkDNN6.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN6.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN7vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN7.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN7.value
                            "gateway" = $a.parameters.n6GatewayDNN7.value
                            "network" = $a.parameters.n6NetworkDNN7.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN7.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN8vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN8.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN8.value
                            "gateway" = $a.parameters.n6GatewayDNN8.value
                            "network" = $a.parameters.n6NetworkDNN8.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN8.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN9vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN9.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN9.value
                            "gateway" = $a.parameters.n6GatewayDNN9.value
                            "network" = $a.parameters.n6NetworkDNN9.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN9.value
                                }
                            )
                        }
                        @{
                            "name" = $a.parameters.N6DNN10vSwitchName.value
                            "vSwitchName" = $a.parameters.vSwitchACCESSPortName.value
                            "vlanId" = $a.parameters.N6vlanIdDNN10.value
                            "subnetMask" = $a.parameters.n6SubnetMaskDNN10.value
                            "gateway" = $a.parameters.n6GatewayDNN10.value
                            "network" = $a.parameters.n6NetworkDNN10.value
                            "enabledForKubernetes" = $true
                            "ipAddressPools" = @(
                                @{
                                    "name" = "VirtualMachineIPs"
                                    "ipAddressRange" = $a.parameters.n6IPDNN10.value
                                }
                            )
                        }
                    )
                }
            }
        }
        }
    Write-Host "Info" "New config: $($newDeviceConfig | ConvertTo-Json -Depth 6)"
    Set-DeviceConfiguration -desiredDeviceConfig $newDeviceConfig
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Applied the ASE config, now waiting for it to succeed"
    $script:maxRetries = 3
    $script:retryWaitDurationInSec = 5
    Function GetDeviceConfigurationStatus()
    {
        $retry = 0
        while($true)
        {
            try
            {
                Write-Host "Fetching device configuration status"
                $status = Get-DeviceConfigurationStatus
                break
            }
            catch
            {
                Write-Host "Failed GetDeviceConfigurationStatus - Caught '$_' on retry - $retry"
                if($retry -lt $script:maxRetries)
                {
                    $retry++
                    Write-Host "GetDeviceConfigurationStatus - Will retry after '$script:retryWaitDurationInSec' seconds"
                    Start-Sleep -Seconds $script:retryWaitDurationInSec
                }
                else
                {
                    Write-Host "GetDeviceConfigurationStatus - We have exhausted max retries"
                    throw "Get-DeviceConfigurationStatus failed"
                }
            }
        }
        return $status
    }
    Function ValidateDeviceConfigurationStatus()
    {
        Param(
            [Parameter()] [string[]] $excludeElements,
            [Parameter()] [int] $retryCount = 20,
            [Parameter()] [int] $sleepInSec = 30
        )
        $deviceConfigStatus = GetDeviceConfigurationStatus
        Write-Host "Waiting for device configuration status to complete"
        while($true)
        {
            Write-Host "Checking if device configuration status is complete or not"
            if($deviceConfigStatus.deviceConfiguration.status -eq "Complete")
            {
                break;
            }
            if($retryCount -lt 0)
            {
                throw "Timeout: DeviceConfiguration did not complete"
            }
            else
            {
                Write-Host "Sleeping for $sleepInSec seconds before retrying"
                $retryCount--
                Start-Sleep -Seconds $sleepInSec
            }
            $deviceConfigStatus = GetDeviceConfigurationStatus
        }
        $deviceConfigStatus = GetDeviceConfigurationStatus
        Write-Host "Checking Get-DeviceConfigurationStatus response"
        Write-Host "Get-DeviceConfigurationStatus response: $($deviceConfigStatus | ConvertTo-Json -Depth 6)"
        $results = $deviceConfigStatus.deviceConfiguration.results
        Write-Host "Device Configuration Results: $($results | ConvertTo-Json -Depth 6)"
        $results | % {
            $element = $_.declarationName
            $resultCode = $_.resultCode
            if($excludeElements -Contains $element)
            {
                if($resultCode -ieq "Failed")
                {
                    Write-Host "Skipped element: $element with resultcode: $resultCode"
                }
                else
                {
                    throw "Unexpected resultcode for $element and $resultCode"
                }
            }
            else
            {
                if($resultCode -ieq "Success")
                {
                    Write-Host "Validated element: $element with resultcode: $resultCode"
                }
                else
                {
                    throw "Unexpected resultcode for $element and $resultCode"
                }
            }
        }
        return $deviceConfigStatus
    }
ValidateDeviceConfigurationStatus
# Add OID #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    $oid = $a.parameters.oid.value
    Write-Host "Info" "Sleeping for 5 sec before adding OID"
    Start-Sleep -Seconds 5
    Write-Host "Info" "Adding OID"
    Invoke-Command -Session $minishellSession -ScriptBlock {Set-HcsKubeClusterArcInfo -CustomLocationsObjectId $Using:oid}
    $currentOID = Invoke-Command -Session $minishellSession -ScriptBlock {Get-HcsKubeClusterArcInfo}
    Write-Host "Info" "Result: $($currentOID.CustomLocationsObjectId)"
# Create Kubernetes cluster #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Creating Kubernetes cluster using $kubernetesNodeProfile (this may take up to 20 minutes)"
    Invoke-Command -Session $minishellSession -ScriptBlock {Add-AzureDataBoxEdgeKubernetesRole -Name kubernetes -VMProfile $Using:kubernetesNodeProfile}
    # Add "Kubernetes Cluster - Azure Arc Onboarding" role assignment to the ASE System-Assigned MI #
    $aseUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ASEresourceGroup/providers/Microsoft.DataBoxEdge/DataBoxEdgeDevices/${ASEname}?api-version=2022-04-01-preview"
    $aseOutput = Invoke-AzRestMethod -Method GET -Uri $aseUri
    $aseJsonOutput = $aseOutput.Content | ConvertFrom-Json
    $aseObjectId = $aseJsonOutput.identity.principalId
    $existingRole = Get-AzRoleAssignment -ObjectId $aseObjectId -RoleDefinitionId "34e09817-6cbe-4d01-b1a2-e0eac5743d41"
    if([string]::IsNullOrWhitespace($existingRole))
    {
        Write-Host "Info" "Adding role `"Kubernetes Cluster - Azure Arc Onboarding`" to ASE MSI $aseObjectId"
        New-AzRoleAssignment -ObjectId $aseObjectId -RoleDefinitionId "34e09817-6cbe-4d01-b1a2-e0eac5743d41" -Scope "/subscriptions/$subscriptionId/resourcegroups/$ASEresourceGroup"
    }
    # Create Arc Addon #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "TO ENABLE Arc for Kubernetes Addon"
    az account set --subscription $subscriptionId
    # TO ENABLE Arc for Kubernetes Addon
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ASEresourceGroup/providers/Microsoft.DataBoxEdge/DataBoxEdgeDevices/$ASEname/roles/kubernetes/addons/arcConfiguration?api-version=2022-04-01-preview"
    Write-Host "Info" "URI = $uri"
    $uri
    $arcName = $a.parameters.arcClusterName.value
    $arcLocation = $a.parameters.arcLocation.value
    Write-Host "Info" "arcName is $arcname"
    Write-Host "Info" "arcLocation is $arcLocation"
    $body = "{`"id`":`"/subscriptions/$subscriptionId/resourceGroups/$ASEresourceGroup/providers/Microsoft.DataBoxEdge/DataBoxEdgeDevices/$ASEname/roles/kubernetes/addons/arcConfiguration`",`"name`":`"arcConfiguration`",`"type`":`"Microsoft.DataBoxEdge/dataBoxEdgeDevices/roles/addons`",`"properties`":{`"subscriptionId`":`"$subscriptionId`",`"resourceGroupName`":`"$ASEresourceGroup`",`"resourceName`":`"$arcName`",`"resourceLocation`":`"$arcLocation`",`"provisioningState`":null},`"kind`":`"ArcForKubernetes`"}"
    Write-Host "Info" "body is $body"
    $output = Invoke-AzRestMethod -Method PUT -Uri $uri -Payload $body
    $output
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    $counter = 0
    while ($true)
    {
        $counter++
        Start-Sleep -Seconds 60

        # Check the status of Arc setup
        $arcConfigurationOutput = Invoke-AzRestMethod -Method GET -Uri $uri
        $arcConfigurationJsonOutput = $arcConfigurationOutput.Content | ConvertFrom-Json
        $arcConfigurationJsonOutput
        $arcConfigurationProvisioningState = $arcConfigurationJsonOutput.properties.provisioningState
        if ($arcConfigurationProvisioningState -eq "Created")
        {
            Write-Host "Info" "Arc cluster created successfully"
            break
        }

        if ($counter -gt 29)
        {
            Write-Host "Error" "Arc cluster still creating after 30 minutes - exiting"
            Exit 1
        }

        Write-Host "Info" "Arc cluster still creating - wait for another minute"
    }
# Move to az CLI, set subscription #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "logging in to the right subscription ID $($a.parameters.subscriptionId.value | ConvertTo-Json -Depth 6)"
    az account set --subscription $a.parameters.subscriptionId.value
# Update extensions #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Updating the k8s and customlocation extensions"
    az config set extension.use_dynamic_install=yes_without_prompt
    az extension add -n k8s-extension
    az extension add -n customlocation
    az extension update --name k8s-extension
    az extension update --name customlocation
# Register NFM location #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Registering NFM"
    $nrmResult = az k8s-extension create --name networkfunction-operator --cluster-name $a.parameters.arcClusterName.value --resource-group $a.parameters.ASEresourceGroup.value --cluster-type connectedClusters --extension-type "Microsoft.Azure.HybridNetwork" --auto-upgrade-minor-version "true" --scope cluster --release-namespace azurehybridnetwork --release-train preview --config-settings-file "$($PSScriptRoot)/a4ONfmConfiguration"
    Write-Host "Info" "Result: $($nrmResult)"
# Create the Packet Core Monitor Kubernetes extension #
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Create the Packet Core Monitor Kubernetes extension"
    $pkmResult = az k8s-extension create --name packet-core-monitor --cluster-name $a.parameters.arcClusterName.value --resource-group $a.parameters.ASEresourceGroup.value --cluster-type connectedClusters --extension-type "Microsoft.Azure.MobileNetwork.PacketCoreMonitor" --release-train stable --auto-upgrade "true"
    Write-Host "Info" "Result: $($pkmResult)"
# Create custom location
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Creating custom location for the ASE $($a.parameters.customLocationName.value | ConvertTo-Json -Depth 6)"
    $customLocationResult = az customlocation create --name $a.parameters.customLocationName.value --resource-group $a.parameters.ASEresourceGroup.value --location $a.parameters.arcLocation.value --namespace azurehybridnetwork --host-resource-id "/subscriptions/$($a.parameters.subscriptionId.value)/resourceGroups/$($a.parameters.ASEresourceGroup.value)/providers/Microsoft.Kubernetes/connectedClusters/$($a.parameters.arcClusterName.value)" --cluster-extension-ids "/subscriptions/$($a.parameters.subscriptionId.value)/resourceGroups/$($a.parameters.ASEresourceGroup.value)/providers/Microsoft.Kubernetes/connectedClusters/$($a.parameters.arcClusterName.value)/providers/Microsoft.KubernetesConfiguration/extensions/networkfunction-operator"
    Write-Host "Info" "Result: $($customLocationResult)"
## Moving to AP5GC deployment
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    $b = Get-Content -Raw "$($PSScriptRoot)/csv_in_jsonMN.json" | ConvertFrom-Json
    Write-Host "Info" "Using the following input parameters to setup AP5GC $($b | ConvertTo-Json -Depth 6)"
    Write-Host "Info" "Creating a Resource Group in Azure for the Mobile Network $($a.parameters.mobileNetworkRGName.value | ConvertTo-Json -Depth 6) in location $($a.parameters.mobileNetworkRGNameLocation.value | ConvertTo-Json -Depth 6)"
    az group create --name $a.parameters.mobileNetworkRGName.value --location $a.parameters.mobileNetworkRGNameLocation.value
# Deploy AP5GC in the Mobile Network Resource Group
<#
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
    Write-Host "Info" "Deploy AP5GC in the Mobile Network Resource Group $($a.parameters.mobileNetworkRGName.value | ConvertTo-Json -Depth 6)"
    Set-AzContext -subscription $a.parameters.subscriptionId.value
    $mobileNetworkRGName = $a.parameters.mobileNetworkRGName.value
    $AP5GCdeploymentResult = New-AzResourceGroupDeployment -Whatif -ResourceGroupName $mobileNetworkRGName -TemplateFile "$($PSScriptRoot)/microsoft.mobilenetwork/mobilenetwork-create-full-5gc-deployment/main.bicep" -TemplateParameterFile "$($PSScriptRoot)/csv_in_jsonMN.json"
    $AP5GCdeploymentResult = New-AzResourceGroupDeployment -ResourceGroupName $mobileNetworkRGName -TemplateFile "$($PSScriptRoot)/microsoft.mobilenetwork/mobilenetwork-create-full-5gc-deployment/main.bicep" -TemplateParameterFile "$($PSScriptRoot)/csv_in_jsonMN.json"
    Write-Host "Info" "Result: $AP5GCdeploymentResult"
    $AP5GCdeploymentResult
    $date = Get-date
    Write-Host "Info" "Timestamp is $date"
#>
}
InitializeAP5GC