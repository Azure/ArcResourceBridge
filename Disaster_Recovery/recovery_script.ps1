 [CmdletBinding()]
Param(
    [ValidateScript({
        if(-Not ($_ | Test-Path) ){
            throw "File or folder does not exist"
        }
        if(-Not ($_ | Test-Path -PathType Leaf) ){
            throw "The Path argument must be a file. Folder paths are not allowed."
        }
        if($_ -notmatch "(\.yaml)"){
            throw "The config file must be of type 'yaml'"
        }
        return $true 
    })]
    [System.IO.FileInfo]$config,
    [string]$location,
    [string]$applianceSubscriptionId,
    [string]$applianceResourceGroupName,
    [string]$applianceName,
    [string]$customLocationSubscriptionId,
    [string]$customLocationResourceGroupName,
    [string]$customLocationName,
    [string]$vCenterSubscriptionId,
    [string]$vCenterResourceGroupName,
    [string]$vCenterName
)

# Start Region: Set user inputs

if (!$location)
    {$location = Read-Host -Prompt 'Enter region of your current Arc resource bridge'}

if (!$applianceSubscriptionId)
    {$applianceSubscriptionId = Read-Host -Prompt 'Enter the Subscription ID of your Arc resource bridge'}

if (!$applianceResourceGroupName)
    {$applianceResourceGroupName = Read-Host -Prompt 'Enter the Resource Group name of your Arc resource bridge'}

if (!$applianceName)
    {$applianceName = Read-Host -Prompt 'Enter the original name in Azure of your current Arc resource bridge'}

if (!$customLocationSubscriptionId)
    {$customLocationSubscriptionId = Read-Host -Prompt 'Enter the Subscription ID of your custom location'}

if (!$customLocationResourceGroupName)
    {$customLocationResourceGroupName = Read-Host -Prompt 'Enter the Resource Group name of your custom location'}

# TODO: Allow for multiple custom location inputs
if (!$customLocationName)
    {$customLocationName = Read-Host -Prompt 'Enter the current name in Azure of your custom location'}

if (!$vCenterSubscriptionId)
    {$vCenterSubscriptionId = Read-Host -Prompt 'Enter the Subscription ID of your vCenter resource in Azure'}

if (!$vCenterResourceGroupName)
    {$vCenterResourceGroupName = Read-Host -Prompt 'Enter the Resource Group name of your vCenter resource in Azure'}
    
if (!$vCenterName)
    {$vCenterName = Read-Host -Prompt 'Enter the current name of your vCenter resource in Azure'}

# End Region: Set user inputs

function confirmationPrompt($msg) {
    Write-Host $msg
    while ($true) {
        $inp = Read-Host "Yes(y)/No(n)?"
        $inp = $inp.ToLower()
        if ($inp -eq 'y' -or $inp -eq 'yes') {
            return $true
        }
        elseif ($inp -eq 'n' -or $inp -eq 'no') {
            return $false
        }
    }
}

$logFile = "arcvmware-output.log"

function logH1($msg) {
    $pattern = '0-' * 40
    $spaces = ' ' * (40 - $msg.length / 2)
    $nl = [Environment]::NewLine
    $msgFull = "$nl $nl $pattern $nl $spaces $msg $nl $pattern $nl"
    Write-Host -ForegroundColor Green $msgFull
    Write-Output $msgFull >> $logFile
}

function logH2($msg) {
    $msgFull = "==> $msg"
    Write-Host -ForegroundColor Magenta $msgFull
    Write-Output $msgFull >> $logFile
}

function logText($msg) {
    Write-Host "$msg"
    Write-Output "$msg" >> $logFile
}

function createRG($subscriptionId, $rgName) {
    $group = (az group show --subscription $subscriptionId -n $rgName)
    if (!$group) {
        $Error[0] | Out-String >> $logFile
        throw "Resource Group $rgName does not exist in subscription $subscriptionId."

        # TODO: Figure out if we can get the rg name from the appliance ARM ID
    }
}


logH1 "Step 1/5: Setting up the current workstation"

if (!$UseProxy -and (confirmationPrompt -msg "Is the current workstation behind a proxy?")) {
    $UseProxy = $true
}

Write-Host "Setting the TLS Protocol for the current session to TLS 1.2."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$proxyCA = ""

if ($UseProxy) {
    logH2 "Provide proxy details"
    $proxyURL = Read-Host "Proxy URL"
    if ($proxyURL.StartsWith("http") -ne $true) {
        $proxyURL = "http://$proxyURL"
    }

    $noProxy = Read-Host "No Proxy (comma separated)"

    $env:http_proxy = $proxyURL
    $env:HTTP_PROXY = $proxyURL
    $env:https_proxy = $proxyURL
    $env:HTTPS_PROXY = $proxyURL
    $env:no_proxy = $noProxy
    $env:NO_PROXY = $noProxy

    $proxyCA = Read-Host "Proxy CA cert path (Press enter to skip)"
    if ($proxyCA -ne "") {
        $proxyCA = Resolve-Path -Path $proxyCA
    }

    $credential = $null
    $proxyAddr = $proxyURL

    if ($proxyURL.Contains("@")) {
        $x = $proxyURL.Split("//")
        $proto = $x[0]
        $x = $x[2].Split("@")
        $userPass = $x[0]
        $proxyAddr = $proto + "//" + $x[1]
        $x = $userPass.Split(":")
        $proxyUsername = $x[0]
        $proxyPassword = $x[1]
        $password = ConvertTo-SecureString -String $proxyPassword -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $proxyUsername, $password
    }

    [system.net.webrequest]::defaultwebproxy = new-object system.net.webproxy($proxyAddr)
    [system.net.webrequest]::defaultwebproxy.credentials = $credential
    [system.net.webrequest]::defaultwebproxy.BypassProxyOnLocal = $true
}

$ProgressPreference = 'Continue'

try {
    if ($proxyCA -ne "") {
        $env:REQUESTS_CA_BUNDLE = $proxyCA
    }

    logH2 "Logging into azure"

    $azLoginMsg = "Please login to Azure CLI.`n" +
    "`t* If you're running the script for the first time, select yes.`n" +
    "`t* If you've recently logged in to az while running the script, you can select no.`n" +
    "Confirm login to azure cli?"
    if (confirmationPrompt -msg $azLoginMsg) {
        az login --use-device-code -o table
    }

    az account set -s $applianceSubscriptionId
    if ($LASTEXITCODE) {
        $Error[0] | Out-String >> $logFile
        throw "The default subscription for the az cli context could not be set."
    }

    # Add necessary extensions
    az extension add --upgrade --name arcappliance
    az extension add --upgrade --name k8s-extension
    az extension add --upgrade --name customlocation
    az extension add --upgrade --name connectedvmware

    logH1 "Step 1/5: All extensions successfully installed"

    createRG "$applianceSubscriptionId" "$applianceResourceGroupName"

    logH1 "Step 2/5: Deleting and recreating a healthy Arc resource bridge"
    logH2 "Provide vCenter details to deploy Arc resource bridge VM. The credentials will be used by Arc resource bridge to update and scale itself."

    # TODO: Fetch necessary information for all related ARM resources
    # Get appliance name, cluster extension name, custom location names, vCenter name

    # Delete existing resource bridge VM and ARM resource
    logH2 "Cleaning up existing Arc Resource Bridge"
    # Ask if they're sure about deleting
    $deleteWarningMsg = "This will delete the existing Arc resource bridge and deploy a new one with the existing VM template.`n" +
    "`t*Confirm deletion and recreation of Arc resource bridge?"
    if (!(confirmationPrompt -msg $deleteWarningMsg)) {
        $Error[0] | Out-String >> $logFile
        throw "Arc resource bridge recovery process canceled."
    }
    # TODO: Catch exit code
    az arcappliance delete vmware --debug --config-file $config

    # Redeploying new resource bridge VM
    logH2 "Deploying new Arc Resource Bridge"
    az arcappliance deploy vmware --debug --config-file $config

    # Recreating resource bridge ARM resource and connecting new resource bridge VM and Azure 
    logH2 "Connecting new Arc Resource Bridge to Azure"
    az arcappliance create vmware --debug --config-file $config --kubeconfig .\kubeconfig

    $applianceId = (az arcappliance show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name $applianceName --query id -o tsv 2>> $logFile)
    if (!$applianceId) {
        throw "Appliance recreation has failed."
    }
    # TODO: Get every 30 seconds, timeout after 5 minutes
    $applianceStatus = (az resource show --debug --ids "$applianceId" --query 'properties.status' -o tsv 2>> $logFile)
    if ($applianceStatus -ne "Running") {
        throw "Appliance is not in running state. Current state: $applianceStatus."
    }

    logH1 "Step 2/5: Arc resource bridge is back up and running"
    logH1 "Step 3/5: Reinstalling cluster extension"

    az k8s-extension create --debug --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name azure-vmwareoperator --extension-type 'Microsoft.vmware' --scope cluster --cluster-type appliances --cluster-name $applianceName --config Microsoft.CustomLocation.ServiceAccount=azure-vmwareoperator 2>> $logFile

    $clusterExtensionId = (az k8s-extension show --subscription $applianceSubscriptionId --resource-group $applianceResourceGroupName --name azure-vmwareoperator --cluster-type appliances --cluster-name $applianceName --query id -o tsv 2>> $logFile)
    if (!$clusterExtensionId) {
        throw "Cluster extension reinstallation failed."
    }
    $clusterExtensionState = (az resource show --debug --ids "$clusterExtensionId" --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($clusterExtensionState -ne "Succeeded") {
        throw "Provisioning State of cluster extension is not succeeded. Current state: $clusterExtensionState."
    }

    logH1 "Step 3/5: Cluster extension reinstalled successfully"
    logH1 "Step 4/5: Reconnecting custom location"

    createRG "$customLocationSubscriptionId" "$customLocationResourceGroupName"

    $customLocationNamespace = ("$customLocationName".ToLower() -replace '[^a-z0-9-]', '')
    az customlocation create --debug --tags "" --subscription $customLocationSubscriptionId --resource-group $customLocationResourceGroupName --name $customLocationName --location $location --namespace $customLocationNamespace --host-resource-id $applianceId --cluster-extension-ids $clusterExtensionId 2>> $logFile

    $customLocationId = (az customlocation show --subscription $customLocationSubscriptionId --resource-group $customLocationResourceGroupName --name $customLocationName --query id -o tsv 2>> $logFile)
    if (!$customLocationId) {
        throw "Custom location reconnection failed."
    }
    $customLocationState = (az resource show --debug --ids $customLocationId --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($customLocationState -ne "Succeeded") {
        throw "Provisioning State of custom location is not succeeded. Current state: $customLocationState."
    }

    logH1 "Step 4/5: Custom location reconnected successfully"
    logH1 "Step 5/5: Reconnecting to vCenter"

    createRG "$vCenterSubscriptionId" "$vCenterResourceGroupName"

    logH2 "Provide vCenter details"
    logText "`t* These credentials will be used when you perform vCenter operations through Azure."
    logText "`t* You can provide the same credentials that you provided for Arc resource bridge earlier."

    az connectedvmware vcenter connect --debug --tags "" --subscription $vCenterSubscriptionId --resource-group $vCenterResourceGroupName --name $vCenterName --custom-location $customLocationId --location $location --port 443

    $vcenterId = (az connectedvmware vcenter show --subscription $vCenterSubscriptionId --resource-group $vCenterResourceGroupName --name $vCenterName --query id -o tsv 2>> $logFile)
    if (!$vcenterId) {
        throw "Reconnecting to vCenter failed."
    }
    $vcenterState = (az resource show --debug --ids "$vcenterId" --query 'properties.provisioningState' -o tsv 2>> $logFile)
    if ($vcenterState -ne "Succeeded") {
        throw "Provisioning State of vCenter is not succeeded. Current state: $vcenterState."
    }

    logH1 "Step 5/5: vCenter was reconnected successfully"
    logH1 "Your vCenter has been successfully reonboarded to Azure Arc and recovery is completed!"
}
catch {
    $err = $_.Exception | Out-String
    logText -ForegroundColor Red ("Script execution failed: " + $err)
}
finally {
    deactivate
}
