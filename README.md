# About this script
This script streamlines and automates the process of preparing Azure Stack Edge (ASE) for use with Azure Private 5G Core ('AP5GC').
The script supports Azure Stack Edge Pro with 1 or 2 GPU and Azure Stack Edge Pro 2, running ASE software versions 2309 & 2312 only. It supports singleton installations of AP5GC.

## Actions performed by the script
1. Takes in all input parameters (IP's, number of DNN's, subID, tenantID, ASE password, MTU, vlan, interface names etc) in a single Excel file.
2. Sets up the ASE with all the IP commissioning in Advanced Networking (vswitches, vnetworks) and Kubernetes sections.
3. Adds the OID for your subscription to the ASE.
4. Creates the Microsoft K8s cluster (Azure Kubernetes Service).
5. Connects the Kubernetes cluster to Azure via Arc (Azure Kubernetes Arc).
6. Adds the required extensions of networkfunction-operator and packet-core-monitor.
7. Creates a custom location for the ASE.
8. Creates an empty new Resource Group as a placeholder for AP5GC resources.
9. Applies the steps in [Azure Private 5G Core documentation: Commission the AKS cluster][1] via automation.
10. The inputs to be given in excel format & validations of input will be done as part of the script.

## Prerequisites
1. A Windows laptop. You will need Administrator rights over your machine. Make sure that Excel and PowerShell 5 are installed.
2. PowerShell 5. You may already have it installed: run PowerShell from the Start menu and use the `$PSVersionTable` command to verify the version.
3. The ImportExcel and Azure Resources (az.Resources) Powershell modules. To verify, run PowerShell as an Administrator and then execute the following:
   
   ```
   Get-Module -Name Az.Resources -list
   Get-Module -Name ImportExcel  -list
   ```

   If the module is installed, the version will be displayed; otherwise, no output is produced. To install them, run PowerShell as an Administrator and then execute the following, exiting and restarting your PowerShell session afterwards:
   
   ```
   Install-Module -Name Az.Resources -AllowClobber -Scope CurrentUser
   Install-Module -Name ImportExcel  -AllowClobber -Scope CurrentUser
   ```
   
4. Remote execution support between your PC and ASE. Run PowerShell as an Administrator and execute: `winrm quickconfig`. If remote execution support is not already enabled, you will be prompted to enable it. 

   If `winrm` returns errors regarding Public interfaces being used, change them to private: from your Powershell console run:
   ```
   Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
   ```
   Note: after using this script, you can disable remote execution via the commands:
   ```
   Stop-Service winrm
   Set-Service -Name winrm -StartupType Disabled
   ```

5. Install the Azure CLI tools on your PC, following the instructions to [install Azure CLI on Windows][2]. We suggest choosing the 64-bit MSI installation.
6. Azure: You will need access to the subscription used for your Azure Stack Edge device. You must have **Ownership** privileges on this subscription.
7. Your Azure subscription should have been *explicitly authorized* by Microsoft for AP5GC usage, so that you can later deploy AP5GC (outside of scope here).
8. You should create a Resource Group (RG) for the ASE, and ensure your have Owner permissions on it, before using the script.

## Preparing to run the script
1. Clone or download this repo to your laptop.
2. Grant permission to run the script. Run PowerShell as an Administrator, navigate to where the script is present and unblock the script using: 
   ```
   Unblock-File PowerShellBasedConfiguration.psm1
   ```
3. Complete all of the steps mentioned under [Order and set up your Azure Stack Edge Pro device(s)][3].
4. Verify that your laptop has access to the ASE's IP address over the management/OAM port, for example, by pointing a web browser at the IP.
5. Confirm that your ASE has Certificates generated, Activated and in the Kubernetes (Preview) section you have enabled the "an Azure Private MEC solution in your environment" option. 
6. Check that on the Azure portal, under the ASE Resource, you do not have any unresolved prompts or warnings, such as recommendations to upgrade ASE software.

## Running the script
1. Fill in all your parameters in the Excel file: `parameters_file_single_ASE_AP5GC`.
2. Save the file and close Excel.
3. Open PowerShell as an Adminstrator, and navigate to the location of the script.
4. In the same session, run: `az login`. Select the appropriate tenant ID in the browser pop up and sign in.
4. Execute the PowerShell script: 
   ```
   .\one_script_single_ASE.ps1
   ```
   (A browser prompt may request that you log in to your tenant - this is for the Az cmdlet.)

Typically, all the ASE resources should be deployed within 35-45 minutes.


[1]: <https://learn.microsoft.com/azure/private-5g-core/commission-cluster?branch=main&pivots=ase-pro-2>
[2]: <https://learn.microsoft.com/cli/azure/install-azure-cli-windows?tabs=azure-cli#install-or-update>
[3]: <https://learn.microsoft.com/azure/private-5g-core/complete-private-mobile-network-prerequisites?pivots=ase-pro-2#order-and-set-up-your-azure-stack-edge-pro-devices>