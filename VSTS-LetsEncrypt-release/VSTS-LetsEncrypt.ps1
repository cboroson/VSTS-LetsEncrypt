Trace-VstsEnteringInvocation $MyInvocation

$KeyVaultName= Get-VstsInput -Name "KeyVaultName" # Name of the Azure Key Vault resource
$ResourceGroupName= Get-VstsInput -Name "ResourceGroupName"
$domain= Get-VstsInput -Name "domain" # Comma separated list of domains and SANs to request in the certificate 
$username= Get-VstsInput -Name "username" # AzureAD ApplicationID
$pw= Get-VstsInput -Name "password" # Key value associated with the AzureAD ApplicationID
$pfxpass= Get-VstsInput -Name "pfxpassword" # Password used to protect the private key
$DirectoryUrl= Get-VstsInput -Name "DirectoryURL" #  ACME server's "directory" endpoint. Currently supported short names include LE_PROD (LetsEncrypt Production v2) and LE_STAGE (LetsEncrypt Staging v2). Defaults to 'LE_PROD'.
$SubscriptionId= Get-VstsInput -Name "SubscriptionId" # Azure subscription ID
$Contact= Get-VstsInput -Name "Contact" # One or more email addresses to associate with this certificate. These addresses will be used by the ACME server to send certificate expiration notifications or other important account notices.
$TenantId= Get-VstsInput -Name "TenantId" # Azure tenant ID
$secretName= Get-VstsInput -Name "secretName" # Name of the output variable that will be passed back to VSTS containing the name of the Key Vault secret
$certName= Get-VstsInput -Name "certName" # Name of the Key Vault secret (limited to alphanumeric and hyphen, without spaces).  If not provided, one will be generated using the requested primary domain.
$CertKeyLength= Get-VstsInput -Name "CertKeyLength" # Bit length of the certificate
$DNSSleep= Get-VstsInput -Name "DNSSleep" # Time in seconds to wait for DNS changes to propagate
$Purpose= Get-VstsInput -Name "Purpose" # Purpose of the certificate to be recorded as a tag value on the Key Vault secret
$WhereInstalled= Get-VstsInput -Name "WhereInstalled" # What services this certificate will be installed to be recorded as a tag value on the Key Vault secret
$Environment= Get-VstsInput -Name "Environment" # Environment value to be recorded as a tag value on the Key Vault secret
$Tenant= Get-VstsInput -Name "Tenant" # Tenant value (in multi-tenant environments) to be recorded as a tag value on the Key Vault secret
$Product= Get-VstsInput -Name "Product" # Product to be recorded as a tag value on the Key Vault secret
$Applications= Get-VstsInput -Name "Applications" # Any applications that reference this certificate to be recorded as a tag value on the Key Vault secret
$secretFormat= Get-VstsInput -Name "secretFormat" # How to store the certificate in Key Vault (key, certificate or secret)

################# Initialize Azure. #################
Import-Module $PSScriptRoot\ps_modules\VstsAzureHelpers_
Initialize-Azure

# Input hygene - remove quotes
$SubscriptionId = $SubscriptionId.trim("'""")
$TenantId = $TenantId.trim("'""")
$secretName = $secretName.trim("'""")
$secretName = $secretName.trim("'""")

# Input hygene - format domain to send to Posh-ACME
# Remove any quotation marks
$domain = $domain.replace("'","")
$domain = $domain.replace('"','')
# Split into array at commas
$domain = $domain.split(',')
# Remove spaces 
$domain = $domain.replace(' ','')
Write-Verbose "Domain: $domain"

# Input hygene - format contacts to send to Posh-ACME
# Remove any quotation marks
$Contact = $Contact.replace("'","")
$Contact = $Contact.replace('"','')
# Split into array at commas
$Contact = $Contact.split(',')
# Remove spaces 
$Contact = $Contact.replace(' ','')
Write-Verbose "Contact: $Contact"


# Verify that specified Key Vault exists
try {
    $DoesKVExist = Get-AzureRmResource -ResourceName $KeyVaultName -ResourceGroupName $ResourceGroupName
}
catch {
    Write-Error "Key Vault $keyVaultName not found in resource group $ResourceGroupName"
    Trace-VstsLeavingInvocation $MyInvocation
    $host.SetShouldExit(1)
}

if (!($DoesKVExist)){
    Write-Error "Key Vault $keyVaultName not found in resource group $ResourceGroupName"
    Trace-VstsLeavingInvocation $MyInvocation
    $host.SetShouldExit(1)
}

# If the password to protect the private key wasn't specified, create a new one
if (!($pfxpass)) {
    $passwordLength = Get-Random -Minimum 20 -Maximum 30
    $pfxpass = ([char[]]([char]33..[char]95) + ([char[]]([char]97..[char]126)) + 0..9 | sort {Get-Random})[0..$PasswordLength] -join ''
}

# Set local temp location for certs so that they don't persist after VSTS job completes
$existing_LOCALAPPDATA = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $env:BUILD_STAGINGDIRECTORY

$password = $pw | ConvertTo-SecureString -AsPlainText -Force
$azcred = New-Object System.Management.Automation.PSCredential ($username, $password)
$azParams = @{
  AZSubscriptionId=$SubscriptionId;
  AZTenantId=$TenantId;
  AZAppCred=$azcred
}

# Get certificiate
if ($contact) {
    $LEResult = New-PACertificate `
        -domain $domain `
        -AcceptTOS `
        -DnsPlugin Azure `
        -PluginArgs $azParams `
        -verbose `
        -PfxPass $pfxpass `
        -DNSSleep $DNSSleep `
        -CertKeyLength $CertKeyLength `
        -DirectoryUrl $DirectoryUrl `
        -Contact $contact
}
else {
    $LEResult = New-PACertificate `
        -domain $domain `
        -AcceptTOS `
        -DnsPlugin Azure `
        -PluginArgs $azParams `
        -verbose `
        -PfxPass $pfxpass `
        -DNSSleep $DNSSleep `
        -CertKeyLength $CertKeyLength `
        -DirectoryUrl $DirectoryUrl
}
# Reset Path
$env:LOCALAPPDATA = $existing_LOCALAPPDATA

# Upload pfx file to key vault
if (!($LEResult)) {
    Write-Error "Certificate file not found"
    Trace-VstsLeavingInvocation $MyInvocation
    $host.SetShouldExit(1)
}

if (!($certname)){
    # Generate name of Key Vault secret
    $certname = ("LetsEncrypt-$($domain.split(',')[0])").replace(".","-")
}
else {
    # Replace periods, spaces and underscores with hyphens
    $certname = $certname -replace '[\. _]',"-"
    # Remove characters that are not allowed in Key Vault secret names
    $certname = $certname -replace '[^0-9a-zA-Z-+$]',''
}

# NOTE:  Tag values must be less than 256 characters
$Subject = $LEResult.AllSans -join(',')
$Subject = $Subject.Substring(0,[System.Math]::Min(254, $Subject.Length))
$Environment = $Environment -join(',')
$Applications = $Applications -join(',')
$Tags = @{
    'SubjectNames' = $Subject
    'Purpose' = $Purpose
    'WhereInstalled' = $WhereInstalled
    'Password' = $pfxpass
    'CertAuthority' = 'LetsEncrypt'
    'Environment' = $Environment
    'Tenant' = $Tenant
    'Product' = $Product
    'Thumbprint' = $LEResult.Thumbprint
    'CertType' = 'Server'
    'Applications' = $Applications
}

switch ($secretFormat) {
    "secret" {
        # Encode the certificate as a password-protrcted Base64 string
        $pfxFilePath = $LEResult.PfxFile
        $flag = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable 
        $collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection 
        $collection.Import($pfxFilePath, $pfxpass, $flag) 
        $pkcs12ContentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12 
        $clearBytes = $collection.Export($pkcs12ContentType,$pfxpass)
        $fileContentEncoded = [System.Convert]::ToBase64String($clearBytes) 
        $secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText -Force 
        $secretContentType = 'application/x-pkcs12' 

        # Upload secret to Key Vault
        Write-Host "Uploading certificate $certname to Key Vault"
        $KVsecret = Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $certname -SecretValue $Secret -ContentType $secretContentType -Expires $LEResult.NotAfter -Tag $Tags| Out-Null
    }
    "certificate" {
        # Upload cert to Key Vault
        Write-Host "Uploading certificate $certname to Key Vault"
        $certpw = $pfxpass | ConvertTo-SecureString -AsPlainText -Force
        $KVsecret = Import-AzureKeyVaultCertificate -VaultName $keyVaultName -Name $certname -FilePath $LEResult.PfxFile -Password $certpw -Tag $Tags | Out-Null
    }
    "key" {
        # Upload cert to Key Vault
        Write-Host "Uploading certificate $certname to Key Vault"
        $certpw = $pfxpass | ConvertTo-SecureString -AsPlainText -Force
        $KVsecret = Add-AzureKeyVaultKey -VaultName $keyVaultName -Name $certname -KeyFilePath $LEResult.PfxFile -KeyFilePassword $certpw -Expires $LEResult.NotAfter -Tag $Tags | Out-Null
    }
}

# Pass secret name as VSTS output
Set-VstsTaskVariable -Name $SecretName -Value $certname

Trace-VstsLeavingInvocation $MyInvocation
