param(
    [string]$ResourceGroupName,
    [string]$KeyVaultName,
    [string]$Location,
    [string]$ServicePrincipalName,
    [string]$VNetName,
    [string]$SubnetName
)

# Login to Azure using SP
Connect-AzAccount -ServicePrincipal -Tenant $env:AZURE_TENANT_ID -ApplicationId $env:AZURE_CLIENT_ID -Credential (New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, (ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force)))

# Set subscription
Set-AzContext -Subscription $env:AZURE_SUBSCRIPTION_ID

# Create RG if not exists
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) { New-AzResourceGroup -Name $ResourceGroupName -Location $Location }

# Create KV if not exists
$kv = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $kv) { $kv = New-AzKeyVault -Name $KeyVaultName -ResourceGroupName $ResourceGroupName -Location $Location -Sku Standard }

# Add tags
$tags = @{ Environment="Production"; ManagedBy="Automation" }
Set-AzResource -ResourceId $kv.ResourceId -Tag $tags -Force

# Add SP access policy
$sp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName
if (-not ($kv.AccessPolicies | Where-Object { $_.ObjectId -eq $sp.Id })) {
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ObjectId $sp.Id `
        -PermissionsToSecrets get,set,list,delete `
        -PermissionsToKeys get,create,delete,list `
        -PermissionsToCertificates get,list,create,import,delete
}

# Create VNet/Subnet if not exists
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $vnet) {
    $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24"
    $vnet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $subnetConfig
}

# Check subnet
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if (-not $subnet) {
    Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24" -VirtualNetwork $vnet | Set-AzVirtualNetwork
}

# Create private endpoint if not exists
$pe = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$KeyVaultName-pe" }
if (-not $pe) {
    New-AzPrivateEndpoint -Name "$KeyVaultName-pe" -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $subnet `
        -PrivateLinkServiceConnection @(New-AzPrivateLinkServiceConnection -Name "kvConnection" -GroupId "vault" -PrivateLinkServiceId $kv.ResourceId)
}
