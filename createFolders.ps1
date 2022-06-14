#!usr/bin/env powershell
$reportsFolder = "${PWD}\perfReports";
if(!( Test-Path -path $reportsFolder))  
{  
    New-Item -ItemType directory -Path $reportsFolder
    Write-Host "Folder path has been created successfully at: " $reportsFolder
               
}
else
{
    Write-Host "The given folder path $reportsFolder already exists";
}

$srcFolder = "${PWD}\src";
if(!( Test-Path -path $srcFolder))  
{  
    New-Item -ItemType directory -Path $srcFolder
    Write-Host "Folder path has been created successfully at: " $srcFolder
               
}
else
{
    Write-Host "The given folder path $srcFolder already exists";
}

$dataFolder = "${PWD}\data";
if(!( Test-Path -path $dataFolder))  
{  
    New-Item -ItemType directory -Path $dataFolder
    Write-Host "Folder path has been created successfully at: " $dataFolder
               
}
else
{
    Write-Host "The given folder path $dataFolder already exists";
}