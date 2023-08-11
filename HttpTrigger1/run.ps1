using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
Import-Module Posh-SSH

# ServicePrincipal for Local Testing
# $AppId = $ENV:APPID
# $AppSecret = $ENV:APPSECRET
# $TenantID= $ENV:TENANTID
# $SecureSecret = $AppSecret | ConvertTo-SecureString -AsPlainText -Force
# $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId,$SecureSecret
# Connect-AzAccount -ServicePrincipal -Credential $Credential -Tenant $TenantID 
# Write-Host "Service Principal Connected"

# Azure KeyVault and Storage info
$kvName = "kvSFTP01"
$storageAccountName = "gocustom"
$containerName = "testhubname-leases"
$blob_name = "hello_sftp.txt"

# Interact with query parameters or the body of the request.
$cName = $Request.Query.cName
$bName = $Request.Query.bName
$saName = $Request.Query.saName
if(-not $cName -or -not $bName -or -not $saName) {
    $body = "One of the need params (saName, bName, cName) is missing, Will use default storage account, container and blob: ", $containerName, $blob_name, $storageAccountName , "\nspecify cName and bName in query parameters to override"
    Write-Host $body
} else {
    $containerName = $cName
    $blob_name = $bName
    $storageAccountName = $saName
    $body = "Will download from following storage account, container and blob: ", $storageAccountName, $containerName, $blob_name
    Write-Host $body
}

# SFTP credentials
$sftpServer = Get-AzKeyVaultSecret -VaultName $kvName -Name "sftpServer" -AsPlainText
$sftpUsername = Get-AzKeyVaultSecret -VaultName $kvName -Name "sftpUsername" -AsPlainText
$sftpPassword = Get-AzKeyVaultSecret -VaultName $kvName -Name "sftpPassword" -AsPlainText
$sftpPort = 22
Write-Host $sftpServer + $sftpUsername + $sftpPassword

# Establish SFTP session
$session = New-SFTPSession -ComputerName $sftpServer -Port $sftpPort -Credential (New-Object System.Management.Automation.PSCredential($sftpUsername, (ConvertTo-SecureString $sftpPassword -AsPlainText -Force))) -AcceptKey

If (($session.Host -ne $sftpServer) -or !($session.Connected)){
    Write-Host $session.Connected + " " + $session.Host
    Write-Host "SFTP server Connectivity failed..!"
    exit 1
 }

# Connect to storage
$ctx = New-AzStorageContext -StorageAccountName $storageAccountName
#$blobList = Get-AzStorageBlob -Context $ctx -Container $containerName

# Upload each file to the SFTP server
$blob = Get-AzStorageBlob -Context $ctx -Container $containerName -Blob $blob_name
$destinationPath = "/" #SFTP Server Location
$sourcePath = "../" + $blob.Name # Store Location in Azure Function
Get-AzStorageBlobContent -Context $ctx -Container $containerName -Blob $blob.Name -Destination $sourcePath -Force # Download from Azure Storage
Set-SFTPItem -SessionId $session.SessionId -Path $sourcePath -Destination $destinationPath -Force # Upload to SFTP Server

Write-Host "Files successfully uploaded"

# Close the SFTP session
Remove-SFTPSession -SessionId $session.SessionId
$body += "SFTP files uploaded successfully."
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
