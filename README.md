**What this script does**:
This single script performs the following tasks:
1. Takes in all input parameters (IP's, number of DNN's, subID, tenantID, ASE password, MTU, vlan, interface names etc) in a single excel file.
2. Sets up the ASE with all the IP commissioning in Advanced Networking (vswitches, vnetworks) and Kubernetes sections.
3. Adds the OID for your subscription to the ASE.
4. Creates the Microsoft K8s cluster (Azure Kubernetes Service).
5. Connects the Kubernetes cluster to Azure via Arc (Azure Kubernetes Arc).
6. Adds the required extensions of networkfunction-operator and packet-core-monitor.
7. Creates a custom location for the ASE.
8. Creates an empty new Resource Group as a placeholder for AP5GC resources.
9. "https://review.learn.microsoft.com/en-us/azure/private-5g-core/commission-cluster?branch=main&pivots=ase-pro-2" these steps are automated.
10. The inputs to be given in excel format & validations of input will be done as part of the script.
11. Supports ASE 2309 & 2312.

**Pre-Req**:
1. This scrit is supported only on PowerShell 5. You need to have Powershell 5 installed* on your system, accessing it as an 'Adminstrator' and have Az cmdlet + ImportExcel module installed. Also az CLI should be up to date.
2. For Az cmdlet run this command on your PowerShell console: `Install-Module -Name Az.Resources -AllowClobber -Scope CurrentUser`
3. Restart your PowerShell.
4. You should have Ownership priveleges on the Subscription you are using for ASE and AP5GC.
5. Your subscription should have been authorized for AP5GC usage.
6. ASE RG needs to be created as part of prerequisite steps & owner permission on RG is needed. 

*You can use the default PowerShell 5 already installed on your Windows laptop

**Procedure**:
1.	Clone the repo to your laptop, or download the repo to your laptop.
2.  Ensure your PowerShell (as **Administrator**) is working (winrm **Private interface**)
3.  You have access to the ASE IP over a management/OAM port.
4.  All of the steps mentioned under under "**Order and set up your Azure Stack Edge Pro device(s)**" in "https://review.learn.microsoft.com/en-us/azure/private-5g-core/complete-private-mobile-network-prerequisites?branch=main&pivots=ase-pro-gpu" needs to be done manully before running the script.
5. Confirm that as part of steps in 4. above, your ASE has Certificates generated, Activated and in the Kubernetes (Preview) section you have enabled `an Azure Private MEC solution in your environment` option. Check that on the Azure portal, under the ASE Resource, you do not have any further ASE software upgrade prompts.
6.  Fill in all your parameters in the Excel file: `parameters_file_ASE_AP5GC_v1.0`
7.  Save the file and close the file/Excel.
8.  Open PowerShell as Admin and run `az login` (Select your right tenantID in the browser pop up and signin)
9.	Execute the script in your PowerShell console, `.\one_script_ASE_v1.0.ps1` (initially you will be prompted on a browser window to sign in to your right tenant - this is for Az cmdlet)

Ideally all the ASE resources should be deployed within 45 minutes.


1. **From your Powershell console run `winrm quickconfig` and ensure it does not throw any errors
2. *** If you have errors regarding Public interfaces being used, change them to private. From your Powershell console run `Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private`

