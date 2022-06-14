#!/bin/bash

export $(grep -v '^#' .env | xargs -0)
# echo $(env)
# echo "SUBSCRIPTIONID: $SUBSCRIPTIONID"
# echo "CLIENTSECRET: $CLIENTSECRET"
# echo "TENANTID: $TENANTID"
# echo "CLIENTID: $CLIENTID"

########################## GETTING ENVIRONMENTAL VARIABLES ########################

resourceGroup=$RESOURCEGROUP
location=$LOCATION
storageAccountName=$STORAGEACCOUNTNAME
shareName=$FILESHARE
containerGroupName=$CONTAINERNAME

########################## CTRL + C TO KILL SHELL SCRIPT EXECUTION ########################
# this function is called when Ctrl-C is sent
function trap_ctrlc ()
{
    # perform cleanup here
    echo "Ctrl-C caught...Performing clean up"
    destroyResource=$(az group exists -n $resourceGroup)
    
    if [ "$destroyResource" = true ]; then
        deleteResources
    fi
    echo "Cleanup completed"
    # exit shell script with error code 2
    # if omitted, shell script will continue execution
    exit 2
}
 
# initialise trap to call trap_ctrlc function
# when signal 2 (SIGINT) is received
trap "trap_ctrlc" 2

########################## READING ARGUMENTS FROM USER INPUT ########################

script_name=$1
virtual_users=$2
test_duration=$3
sla_limit=$4
sla=${sla_limit:-1000}

if [ -z "$virtual_users" ]; then
    virtual_users=$VUS
fi
if [ -z "$test_duration" ]; then
    test_duration=$TESTDURATION
fi

if [ -z "$test_duration" ] || [ -z "$virtual_users" ]; then
    echo "*************************************************************************************************************"
    echo "Virtual users/Test Duration value is empty. Please provide value in either env file or in NPM command as args"
    echo "*************************************************************************************************************"
    exit 1
fi

echo "************************************************************************************************************"
echo "The test will be executed with $virtual_users users for $test_duration seconds using the script $script_name"
echo "************************************************************************************************************"

########################## LOGIN IN TO AZURE SUBSCRIPTION ########################
azureLogin() {
    echo "Logging into Subscription"
    azureSP=$(az login --service-principal --username $CLIENTID --password $CLIENTSECRET --tenant $TENANTID)
    azureLoginStatus=$?
    azureSubs=$(az account set --subscription $SUBSCRIPTIONID)
    azureSubscriptionStatus=$?
    # echo "$azureLoginStatus && $azureSubscriptionStatus"
    if [ $azureLoginStatus -eq 0 ] && [ $azureSubscriptionStatus -eq 0 ]; then
        echo "************************"
        echo "Logged in successfully."
        echo "************************"
    else
        echo "*************************************************"
        echo "Login failed. Please check your azure credentials"
        echo "*************************************************"
        exit 1
    fi

}

########################## CREATING RESOURCE GROUP UNDER AZURE SUBSCRIPTION ########################
resourceGroupCreate() {
    echo "Creating Resource Group"

    azureRG=$(az group create -l $location -n $resourceGroup)
    azureResourceStatus=$?
    if [ $azureResourceStatus -eq 0 ]; then
        echo "************************************************"
        echo "Resource Group created successfully in $location"
        echo "************************************************"
    else
        echo "******************************"
        echo "Resource Group is not created."
        echo "******************************"    
        exit 1
    fi
}

sleep 5


# ########################## CREATING STORAGE ACCOUNT UNDER RESOURCE GROUP IN AZURE SUBSCRIPTION ########################

createStorageAccount() {
    echo "Creating Storage account"
    azureSA=$(az storage account create -n $storageAccountName -g $resourceGroup --default-action Allow --sku Standard_LRS)
    azureStorageStatus=$?
    if [ $azureStorageStatus -eq 0 ]; then
        echo "*************************************************"
        echo "Storage Account created successfully in $location"
        echo "*************************************************"
    else
        echo "*******************************************"
        echo "Storage Account is not created successfully"
        echo "*******************************************"
        deleteResources
        exit 1
    fi
}

sleep 5

getStorageAccountKey() {
    storageAccountKey=$(az storage account keys list --resource-group $resourceGroup --account-name $storageAccountName --query "[0].value" --output tsv)
    azureStorageKeyStatus=$?
    if [ $azureStorageKeyStatus -eq 0 ]; then
        echo "****************************************"
        echo "storage Account Key : $storageAccountKey"
        echo "****************************************"
    else
        echo "***********************************************"
        echo "Storage Account Key is not available to proceed"
        echo "***********************************************"
        deleteResources
        exit 1
    fi
}
sleep 5

# ################## CREATING FILE SHARE UNDER STORAGE ACCOUNT AT RESOURCE GROUP IN AZURE SUBSCRIPTION ######################

createFileShare() {
    
    echo "Creating Fileshare"

    azureFS=$(az storage share create --name $shareName --account-name $storageAccountName --account-key $storageAccountKey --quota 5)
    azureFileshareStatus=$?
    if [ $azureFileshareStatus -eq 0 ]; then
        echo "*******************************"
        echo "File share created successfully"
        echo "*******************************"
    else
        echo "**************************************"
        echo "File share is not created successfully"
        echo "**************************************"
        deleteResources
        exit 1
    fi

}
# sleep 5
# ################## COPY TEST SCRIPT TO FILE SHARE IN STORAGE ACCOUNT ######################

copyFilesToFileshare() {
    echo "Test Files are uploading into fileshare"
    filename=$script_name
    localFile="${PWD}/src/$script_name"

    azuredataFolderStatus=$(az storage directory create --name data \
                            --share-name $shareName \
                            --account-key $storageAccountKey \
                            --account-name $storageAccountName)

    azureData=$?

    if [ $azureData -ne 0 ]; then
        echo "Data Folder is not created properly"
        deleteResources
        exit 1
    fi
    # azureFU=$(az storage file upload -s $shareName --account-name $storageAccountName --account-key $storageAccountKey --source "$localFile") 
    azureDataFUStatus=$(az storage file upload-batch --destination $shareName/data \
                             --source "${PWD}/data" \
                             --account-key $storageAccountKey \
                             --account-name $storageAccountName)

    azureDataFUStatus=$?

    azureFU=$(az storage file upload -s $shareName --account-name $storageAccountName --account-key $storageAccountKey --source "$localFile") 
    azureFileCopyStatus=$?
    if [ $azureFileCopyStatus -eq 0 ] && [ $azureDataFUStatus -eq 0 ]; then
        echo "************************************"
        echo "Test Files are uploaded successfully"
        echo "************************************"
    else
        echo "***************************"
        echo "Test Files are not uploaded"
        echo "***************************"
        deleteResources
        exit 1
    fi
}

sleep 5

##################  TEST EXECUTION  ######################
testExecution() {
    Date=$(date)
    echo "$Date - Test is Started!"
    countRunning=1;
    while [ $countRunning -gt 0 ]
    do
        countRunning=0; 
        azureLogs=$(az container show -g $resourceGroup -n "$containerGroupName" --query "containers[0].instanceView.currentState.state" -o tsv)
        # echo "Running Status: $azureLogs"    
        if [ $azureLogs = "Running" ]; then 
            ((countRunning=countRunning+1))
        fi
        # echo "After Running comparison - countRunning: $countRunning"  
        if [ $countRunning -gt 0 ] 
        then 
            echo "Load test running with $countRunning containers"
        fi

        sleep 5
    done
    Date=$(date)
    echo "$Date - Test is Finished!"
}


################## SHOW TEST EXECUTION LOGS ######################

showContainerLogs() {
    echo "Displaying Container Logs"
    az container logs -g $resourceGroup -n $containerGroupName
    azureContainerLogStatus=$?
    if [ $azureContainerLogStatus -eq 0 ]; then
        echo "*********************************"
        echo "Container logs are shown properly"
        echo "*********************************"
    else
        echo "***************************************************************************"
        echo "Container logs are not created. Please check the container creation command"
        echo "***************************************************************************"
        exit 1
    fi   

}


# ################## CREATING CONTAINER UNDER RESOURCE GROUP IN AZURE SUBSCRIPTION ######################
# commandline="k6 run --vus $virtual_users --duration ${test_duration}s -e SCRIPT=${script_name} -e SLA=$sla /mnt/azfile/$script_name --summary-export /mnt/azfile/${script_name}_summary.json --out json=/mnt/azfile/${script_name}_alldata.json -o influxdb=http://51.120.5.231:8086/Volvo"
# commandline="k6 run --vus $virtual_users --duration ${test_duration}s -e SCRIPT=${script_name} -e SLA=$sla /mnt/azfile/$script_name --summary-export /mnt/azfile/${script_name}_summary.json --out json=/mnt/azfile/${script_name}_alldata.json"

createContainer() {
    echo "Create Container"
    azureCC=$(az container create -g $resourceGroup \
                        -n $containerGroupName \
                        --image loadimpact/k6 \
                        --cpu 1 \
                        --memory 1 \
                        --restart-policy never \
                        --azure-file-volume-account-name $storageAccountName \
                        --azure-file-volume-account-key $storageAccountKey \
                        --azure-file-volume-share-name $shareName \
                        --azure-file-volume-mount-path "/mnt/azfile" \
                        --command-line "k6 run --vus $virtual_users --duration ${test_duration}s -e SCRIPT=${script_name} -e SLA=$sla /mnt/azfile/$script_name --summary-export /mnt/azfile/${script_name}_summary.json --out json=/mnt/azfile/${script_name}_alldata.json -o influxdb=http://51.120.5.231:8086/Volvo")

    azureContainerStatus=$?
    if [ $azureContainerStatus -eq 0 ]; then
        echo "************************************"
        echo "Container is created successfully"
        echo "************************************"
        testExecution
        showContainerLogs
    else
        echo "*********************************************************************"
        echo "Container is not created. Please check the container creation command"
        echo "*********************************************************************"
        deleteResources
        exit 1
    fi   
}

sleep 5

# ################## SHOW ALL THE FILES IN FILESHARE UNDER STORAGE ACCOUNT ######################
listFiles() {
    echo "Listing all the files available in Fileshare"
    az storage file list -s $shareName --account-name $storageAccountName --account-key $storageAccountKey -o table
    azureListStatus=$?
    if [ $azureListStatus -eq 0 ]; then
        echo "****************************"
        echo "Files are shown successfully"
        echo "****************************"
    else
        echo "************************************************"
        echo "Some issues showing files available in Fileshare"
        echo "************************************************"   
        deleteResources 
        exit 1
    fi
}


sleep 5

# ################## DOWNLOAD ALL THE FILES (JSON & HTML) TO LOCAL LAPTOP UNDER REPORTS FOLDER ######################

downloadReports() {
    [ ! -d "./perfReports" ] && mkdir ./perfReports && echo "Directory created"
    rm -rf ./perfReports/*.json && rm -rf reports/*.html
    downloadPath="./perfReports"
    # echo "Current Path: $downloadPath"
    # data_metrics=$(az storage file exists --account-name $storageAccountName --account-key $storageAccountKey --path ${filename}_alldata.json --share-name $shareName)
    # echo "DATA METRICS: $data_metrics"
    # if [ $(az storage file exists --account-name $storageAccountName --account-key $storageAccountKey --path ${filename}_alldata.json --share-name $shareName) ]; then 
        all_data=$(az storage file download --account-name $storageAccountName --account-key $storageAccountKey -s $shareName --path ${filename}_alldata.json --dest $downloadPath)
    # else
    #     echo "All metrics data are not downloaded"
    # fi
    # if [ $(az storage file exists --account-name $storageAccountName --account-key $storageAccountKey --path ${filename}_summary.json --share-name $shareName) ]; then
        summary_data=$(az storage file download --account-name $storageAccountName --account-key $storageAccountKey -s $shareName --path ${filename}_summary.json --dest $downloadPath)
    # else
    #     echo "Summary metrics data are not downloaded"
    # fi
    # if [ $(az storage file exists --account-name $storageAccountName --account-key $storageAccountKey --path summary.html --share-name $shareName) ]; then
        html_data=$(az storage file download --account-name $storageAccountName --account-key $storageAccountKey -s $shareName --path summary.html --dest $downloadPath)
    # else
    #     echo "HTML Report file is not found"
    # fi
}


# # sleep 5

################## DELETE ALL RESOURCES CREATED UNDER RESOURCE GROUP IN AZURE SUBSCRIPTION ######################

deleteResources() {
    echo "Delete all resources created in resource group"

    az group delete -g $resourceGroup -y
    azureResourceDeletionStatus=$?
    if [ $azureResourceDeletionStatus -eq 0 ]; then
        echo "***********************************"
        echo "Resource Group deleted successfully"
        echo "***********************************"
    else
        echo "******************************"
        echo "Resource Group is not deleted."
        echo "******************************"    
        exit 1
    fi

}

################################# MAIN SCRIPT STARTS ##########################
azureLogin
resourceGroupCreate
createStorageAccount
getStorageAccountKey
createFileShare
copyFilesToFileshare
createContainer
listFiles
downloadReports
deleteResources
################################# MAIN SCRIPT ENDS ##########################