param(
    [string]$ResourceGroupName,
    [string]$KeyVaultName,
    [string]$Location,
    [string]$ServicePrincipalName,
    [string]$VNetName,
    [string]$SubnetName
)

# Login with Service Principal
Connect-AzAccount `
    -ServicePrincipal `
    -Tenant $env:AZURE_TENANT_ID `
    -ApplicationId $env:AZURE_CLIENT_ID `
    -Credential (New-Object System.Management.Automation.PSCredential($env:AZURE_CLIENT_ID, (ConvertTo-SecureString $env:AZURE_CLIENT_SECRET -AsPlainText -Force)))

Set-AzContext -Subscription $env:AZURE_SUBSCRIPTION_ID

# Resource Group
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $rg) { New-AzResourceGroup -Name $ResourceGroupName -Location $Location }

# Key Vault
$kv = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $kv) { $kv = New-AzKeyVault -Name $KeyVaultName -ResourceGroupName $ResourceGroupName -Location $Location -Sku Standard }

# Tags
$desiredTags = @{ Environment="Production"; ManagedBy="Automation" }
Set-AzResource -ResourceId $kv.ResourceId -Tag $desiredTags -Force

# Access Policy
$sp = Get-AzADServicePrincipal -DisplayName $ServicePrincipalName
$exists = $kv.AccessPolicies | Where-Object { $_.ObjectId -eq $sp.Id }
if (-not $exists) {
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ResourceGroupName $ResourceGroupName -ObjectId $sp.Id `
        -PermissionsToSecrets get,set,list,delete `
        -PermissionsToKeys get,create,delete,list `
        -PermissionsToCertificates get,list,create,import,delete
}

# Key Rotation Policy
$rp = Get-AzKeyVaultKeyRotationPolicy -VaultName $KeyVaultName -ErrorAction SilentlyContinue
if (-not $rp) {
$rotationPolicyJson = @"
{
  "attributes":{"expiryTime":"P2Y"},
  "lifetimeActions":[
    {"trigger":{"timeBeforeExpiry":"P30D"},"action":{"type":"Rotate"}}
  ]
}
"@
    Set-AzKeyVaultKeyRotationPolicy -VaultName $KeyVaultName -InputObject $rotationPolicyJson
}

# Virtual Network and Subnet
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not $vnet) {
    $subnetConfig = New-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24"
    $vnet = New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $subnetConfig
}

$subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if (-not $subnet) {
    Add-AzVirtualNetworkSubnetConfig -Name $SubnetName -AddressPrefix "10.0.1.0/24" -VirtualNetwork $vnet | Set-AzVirtualNetwork
    $vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $SubnetName -VirtualNetwork $vnet
}

# Private Endpoint
$pe = Get-AzPrivateEndpoint -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "$KeyVaultName-pe" }
if (-not $pe) {
    New-AzPrivateEndpoint -Name "$KeyVaultName-pe" -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $subnet `
        -PrivateLinkServiceConnection @(New-AzPrivateLinkServiceConnection -Name "kvConnection" -GroupId "vault" -PrivateLinkServiceId $kv.ResourceId)
}
