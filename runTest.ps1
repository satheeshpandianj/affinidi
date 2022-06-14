#!usr/bin/env powershell
Import-Module '.\env.ps1'

########################## GETTING ENVIRONMENTAL VARIABLES ########################
$resourceGroup=$env:RESOURCEGROUP
$location=$env:LOCATION
$storageAccountName=$env:STORAGEACCOUNTNAME
$shareName=$env:FILESHARE
$containerGroupName=$env:CONTAINERNAME

################## MAIN SCRIPT STARTS ######################

######################### READING ARGUMENTS FROM USER INPUT ########################
$script_name = $args[0]
$virtual_users = $args[1]
if ( $virtual_users -eq $null ) {
    $virtual_users = $env:VUS
}
 
$test_duration = $args[2]
if ( $test_duration -eq $null ) {
    $test_duration = $env:TESTDURATION
}
 
$sla_limit = $args[3]
if ( $sla_limit -lt 1000 ) {
    $sla = $sla_limit
}
else{
    $sla = 1000
}
 
if ( ($virtual_users -eq $null) -or ($test_duration -eq $null))
{
    Write-Host "*************************************************************************************************************"
    Write-Host "Virtual users/Test Duration value is empty. Please provide value in either env file or in NPM command as args"
    Write-Host "*************************************************************************************************************"
    Exit 1
}
 
Write-Host "************************************************************************************************************"
Write-Host "The test will be executed with $virtual_users users for $test_duration seconds using the script $script_name"
Write-Host "************************************************************************************************************"
# Write-Host "sla: $sla"

########################## LOGIN IN TO AZURE SUBSCRIPTION ########################
function azureLogin {
    Write-Host "Logging into Subscription"      
    $azureSP = $(az login --service-principal --username $env:CLIENTID --password $env:CLIENTSECRET --tenant $env:TENANTID)
    $azureSubs = $(az account set --subscription $env:SUBSCRIPTIONID)
    if(  $azureSP -ne $null -and $azureSubs -eq $null){
        Write-Host "**********************"
        Write-Host "Logged in successfully"
        Write-Host "**********************"
    }
    else{
        Write-Host "*************************************************"
        Write-Host "Login failed. Please check your azure credentials"
        Write-Host "*************************************************"
        Exit 1
    }
}
########################## CREATING RESOURCE GROUP UNDER AZURE SUBSCRIPTION ########################
function resourceGroupCreate {
    Write-Host "Creating Resource Group"
    $azureRG = $(az group create -l $location -n $resourceGroup)
    if ($azureRG -ne $null) {
        Write-Host "************************************************"
        Write-Host "Resource Group created successfully in $location"
        Write-Host "************************************************"
    }
    else{
        Write-Host "*****************************"
        Write-Host "Resource Group is not created"
        Write-Host "*****************************"
        Exit 1
    }
    Start-Sleep -s 5
}

# #########################
# CREATING STORAGE ACCOUNT UNDER RESOURCE GROUP IN AZURE SUBSCRIPTION ########################
function createStorageAccount {
    Write-Host "Creating Storage account"
    $azureSA = $(az storage account create -n $storageAccountName -g $resourceGroup --default-action Allow --sku Standard_LRS)
    if ($azureSA -ne $null) {
        Write-Host "*************************************************"
        Write-Host "Storage Account created successfully in $location"
        Write-Host "*************************************************"
    }
    else{
        Write-Host "*******************************************"
        Write-Host "Storage Account is not created successfully"
        Write-Host "*******************************************"
        deleteResources
        Exit 1
    }
}

function getStorageAccountConnectionString {
    $storageConnectionString = $(az storage account show-connection-string -n $storageAccountName -g $resourceGroup --query connectionString -o tsv)
    if($storageConnectionString -ne $null ) {
        Write-Host "****************************************************"
        Write-Host "Storage Connection string : $storageConnectionString"
        Write-Host "****************************************************"
        $env:AZURE_STORAGE_CONNECTION_STRING = $storageConnectionString
    }
    else{
        Write-Host "*****************************************************"
        Write-Host "Storage Connection string is not available to proceed"
        Write-Host "*****************************************************"
        Exit 1
    }
}


# ################## CREATING FILE SHARE UNDER STORAGE ACCOUNT AT RESOURCE GROUP IN AZURE SUBSCRIPTION ######################
function createFileShare {
    Write-Host "Creating Fileshare"
    $azureFS = $(az storage share create -n $shareName)
    Write-Host "$azureFS"
    if ($azureFS -ne $null) {
        Write-Host "*******************************"
        Write-Host "File share created successfully"
        Write-Host "*******************************"
    }
    else{
        Write-Host "**************************************"
        Write-Host "File share is not created successfully"
        Write-Host "**************************************"
        deleteResources
        Exit 1
    }
}
################## COPY TEST SCRIPT TO FILE SHARE IN STORAGE ACCOUNT ######################
function copyFilesToFileshare {
    Write-Host "Test Files are uploading into fileshare"
    $filename = $script_name
    $localFile = "${PWD}\src\$filename"

    $azuredataFolderStatus = $(az storage directory create --name data `
                            --share-name $shareName `
                            --account-key $storageKey `
                            --account-name $storageAccountName)

    Write-Host "azuredataFolderStatus : $azuredataFolderStatus"

    if ($azuredataFolderStatus -eq $null) {
        Write-Host "************************************"
        Write-Host "Data Folder is not created properly"
        Write-Host "************************************"
        deleteResources
        Exit 1
    }

    $azureDataFUStatus = $(az storage file upload-batch --destination $shareName\data `
                             --source "${PWD}\data" `
                             --account-key $storageKey `
                             --account-name $storageAccountName)

    Write-Host "azureDataFUStatus : $azureDataFUStatus"

    $azuresrcFolderStatus = $(az storage directory create --name src `
                            --share-name $shareName `
                            --account-key $storageKey `
                            --account-name $storageAccountName)

    Write-Host "azuresrcFolderStatus : $azuresrcFolderStatus"

    if ($azuresrcFolderStatus -eq $null) {
        Write-Host "************************************"
        Write-Host "Src Folder is not created properly"
        Write-Host "************************************"
        deleteResources
        Exit 1
    }

    $azureSrcFUStatus = $(az storage file upload-batch --destination $shareName\src `
                             --source "${PWD}\src" `
                             --account-key $storageKey `
                             --account-name $storageAccountName)

    Write-Host "azureSrcFUStatus : $azureSrcFUStatus"


    # $azureFU = $(az storage file upload -s $shareName --account-name $storageAccountName --account-key $storageKey --source "$localFile")
    # Write-Host "azureFU : $azureFU"
     if (($azureSrcFUStatus -ne $null) -and ($azureDataFUStatus -ne $null)) {
         Write-Host "************************************"
         Write-Host "Test Files are uploaded successfully"
         Write-Host "************************************"
     }
     else{
         Write-Host "***************************"
         Write-Host "Test Files are not uploaded"
         Write-Host "***************************"
         deleteResources
         Exit 1
     }
}


################## TEST EXECUTION ######################
function testExecution {
    $Date = Get-Date
    Write-Host "$Date - Test is Started!"
    do {
        $countRunning = 0;
        if ($(az container show -g $resourceGroup -n "$containerGroupName" --query "containers[0].instanceView.currentState.state" -o tsv) -eq "Running") {
                $countRunning += 1
        }
        if ($countRunning -gt 0) {
            Write-Host "Load test still running with $countRunning containers"
        }
        Start-Sleep -s 5
    }while ($countRunning -gt 0)
    $Date = Get-Date
    Write-Host " $Date - Test is Finished!"
}

################## SHOW TEST EXECUTION LOGS ######################
function showContainerLogs {
     Write-Host "Displaying Container Logs"
    #  $azureContainerLogStatus = $(az container logs --resource-group $resourceGroup --name $containerGroupName)
    az container logs --resource-group $resourceGroup --name $containerGroupName
     Write-Host "$azureContainerLogStatus"
}


################## CREATING CONTAINER UNDER RESOURCE GROUP IN AZURE SUBSCRIPTION ######################
function createContainer {
    Write-Host "Create Container"
    $azureCC = $(az container create -g $resourceGroup `
                                    -n $containerGroupName `
                                    --image loadimpact/k6 `
                                    --cpu 1 `
                                    --memory 1 `
                                    --restart-policy never `
                                    --azure-file-volume-account-name $storageAccountName `
                                    --azure-file-volume-account-key $storageKey `
                                    --azure-file-volume-share-name $shareName `
                                    --azure-file-volume-mount-path "/mnt/azfile/" `
                                    --command-line $commandLine)

    # Write-Host "azureCC : $azureCC"
    
    if($azureCC -ne $null) {
        Write-Host "******************************"
        Write-Host "Container created successfully"
        Write-Host "******************************"
        testExecution
        showContainerLogs
    }
    else{
        Write-Host "*********************************************************************"
        Write-Host "Container is not created. Please check the container creation command"
        Write-Host "*********************************************************************"
        deleteResources
        Exit 1
    }
}



################## SHOW ALL THE FILES IN FILESHARE UNDER STORAGE ACCOUNT ######################
function listFiles {
    Write-Host "Listing all the files availbale in Fileshare"
    $azureListStatus = $(az storage file list -s $shareName --account-name $storageAccountName --account-key $storageKey -o table)
    Write-Host "$azureListStatus"
    if($azureListStatus -ne $null) {
        Write-Host "****************************"
        Write-Host "Files are shown successfully"
        Write-Host "****************************"
    }
    else{
        Write-Host "************************************************"
        Write-Host "Some issues showing files available in Fileshare"
        Write-Host "************************************************"
        deleteResources
        Exit 1
    }
}

################## DOWNLOAD ALL THE FILES (JSON & HTML) TO LOCAL LAPTOP UNDER REPORTS FOLDER ######################
function downloadReports {
    $downloadPath="${PWD}\perfReports"
    if($(az storage file exists --account-name $storageAccountName --account-key $storageKey --path ${script_name}_alldata.json --share-name $shareName)) {
        az storage file download --account-name $storageAccountName --account-key $storageKey -s $shareName -p ${script_name}_alldata.json --dest $downloadPath
    }
    if($(az storage file exists --account-name $storageAccountName --account-key $storageKey --path ${script_name}_summary.json --share-name $shareName)) {
        az storage file download  --account-name $storageAccountName --account-key $storageKey -s $shareName -p ${script_name}_summary.json --dest $downloadPath
    }
    if($(az storage file exists --account-name $storageAccountName --account-key $storageKey --path summary.html --share-name $shareName)) {
        az storage file download  --account-name $storageAccountName --account-key $storageKey -s $shareName -p summary.html --dest $downloadPath
    }
    else {
        Write-Host "HTML Report file is not found"
    }
}


################## DELETE ALL RESOURCES CREATED UNDER RESOURCE GROUP IN AZURE SUBSCRIPTION ######################
 function deleteResources {
     Write-Host "Delete all resources created in resource group"

     $azureDelete = az group delete -g $resourceGroup -y
      if ($azureDelete -eq $null) {
         Write-Host "***********************************"
         Write-Host "Resource Group deleted successfully"
         Write-Host "***********************************"
     }
     else{
         Write-Host "******************************"
         Write-Host "Resource Group is not deleted."
         Write-Host "******************************"
         Exit 1
     }
 }


########################## CALL THE FUNCTIONS IN PROPER ORDER ########################
azureLogin
resourceGroupCreate
createStorageAccount
getStorageAccountConnectionString
$storageKey = $(az storage account keys list --resource-group $resourceGroup --account-name $storageAccountName --query "[0].value" --output tsv)
Write-Host "storageKey: $storageKey"
createFileShare
copyFilesToFileshare

############### WITHOUT PUSHING METRICS TO INFLUXDB #################################
$commandLine = "k6 run --vus $virtual_users --duration ${test_duration}s -e SCRIPT=${script_name} /mnt/azfile/src/${script_name} --summary-export /mnt/azfile/${script_name}_summary.json --out json=/mnt/azfile/${script_name}_alldata.json"

############### PUSHING METRICS TO INFLUXDB ###############################
# $commandLine = "k6 run --vus $virtual_users --duration ${test_duration}s -e SCRIPT=${script_name} -e SLA=$sla --out influxdb=http://51.120.5.231:8086/Volvo /mnt/azfile/src/${script_name} --summary-export /mnt/azfile/${script_name}_summary.json --out json=/mnt/azfile/${script_name}_alldata.json"
Write-Host "commandLine: $commandLine"
createContainer
listFiles
downloadReports
deleteResources
################## MAIN SCRIPT ENDS ######################