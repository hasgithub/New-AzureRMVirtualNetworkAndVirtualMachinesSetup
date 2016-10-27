#First must login to Azure, using Resource Manager
Login-AzureRMAccount

#User may have several subscriptions, so select one to use for this script
Get-AzureRMSubscription | Sort SubscriptionName | Select SubscriptionName |FT
$subscr=Read-Host "Enter selected subscription name from list above"
$subscription = Get-AzureRmSubscription -SubscriptionName $subscr

while (!$subscription) {
    Get-AzureRMSubscription | Sort SubscriptionName | Select SubscriptionName |FT
    $subscr = Read-Host "Invalid subscription name chosen, please enter subscription name from list above"
    $subscription = Get-AzureRmSubscription -SubscriptionName $subscr
}

Get-AzureRMSubscription -SubscriptionName $subscr | Select-AzureRmSubscription
Write-Host "Setting Azure subscription to: " $subscr

#VMs should be part of a resource group, either an existing one or a new one
Get-AzureRMResourceGroup | Sort ResourceGroupName | Select ResourceGroupName |FT
$rgName=Read-Host "Enter existing or new resource group name"

$rg = Get-AzureRmResourceGroup -Name $rgName

if (!$rg)
{
    Write-Host "New Resource Group Name, additional settings required"
    
    #Resource groups need to be part of a location
    Get-AzureRmLocation | Sort Location | Select Location |FT
    $locName=Read-Host "Enter location name such as WestUS"

    $loc = Get-AzureRmLocation | where Location -eq $locName
    while (!$loc) {
        Get-AzureRmLocation | Sort Location | Select Location |FT
        $locName=Read-Host "Invalid location name entered, pleae enter location name such as WestUS"
        $loc = Get-AzureRmLocation | where Location -eq $locName
    }


    #Create the resource group
    New-AzureRMResourceGroup -Name $rgName -Location $locName
}
Write-Host "Resource Group configuration completed. Using Resource Group" $rgName "in" $locName

#VMs need a storage account to store the virtual disk, either an existing one or a new one 
Get-AzureRMStorageAccount | Sort StorageAccountName |Select StorageAccountName | FT
$saName=Read-Host "Enter existing or new Storage Account Name"
$sa = Get-AzureRMStorageAccount | where StorageAccountName -eq $saName
if (!$sa)
{
    Write-Host "New Storage Account, Creating" $saName "..."
    New-AzureRMStorageAccount -Name $saName -ResourceGroupName $rgName -Type Standard_LRS -Location $locName
} else {
    Write-Host "Existing storage account selected" $saName
}

#Setup the virtual network
Get-AzureRmVirtualNetwork | Select Name, ResourceGroupName, Location | Format-Table
$vnetName = Read-Host "Enter Virtual Network existing name, or new name to create a new Virtual Network"

$vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $rgName -Name $vnetName

if (!$vNet) {
    Write-Host "New virtual network name entered, configuration will begin..."
    
    $vNetAddressPrefix = Read-Host "Enter address prefix for virtual network, press [Enter] to use default of 10.0.0.0/16"
    if (!$vNetAddressPrefix)
    {
        $vNetAddressPrefix = "10.0.0.0/16"
    }

    $dnsIP = Read-Host "Enter name of DNS Server, or press [Enter] to use default of 10.0.0.4"
    if (!$tdnsIP)
    {
        $dnsIP = "10.0.0.4"
    }
    New-AzureRMVirtualNetwork -Name $vNetName -ResourceGroupName $rgName -Location $locName -AddressPrefix $vNetAddressPrefix -DnsServer $dnsIP

}
$vNet = Get-AzureRmVirtualNetwork -ResourceGroupName $rgName -Name $vnetName
Write-Host "Using Virtual Network" $vnet.Name "with address prefix" $vNet.AddressSpace.AddressPrefixes " and DNS Server" $vNet.DhcpOptions.DnsServers

#Setup the subnet environment

Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vNet | Select Name, AddressPrefix |Format-Table
$vNetSubNetName = Read-Host "Enter name of existing subnet or new subnet name"
$vNetSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $vNetSubNetName -VirtualNetwork $vNet
if (!$vNetSubnet){
    Write-Host "New subnet name, additional settings required"
    $vNetSubNetAddressPrefix = Read-Host "Enter address prefix for subnet, press [Enter] to use default of 10.0.0.0/24"
    if (!$vNetSubNetAddressPrefix)
    {
        $vNetSubNetAddressPrefix = "10.0.0.0/24"
    }
    Add-AzureRMVirtualNetworkSubnetConfig -Name $vNetSubNetName -AddressPrefix $vNetSubNetAddressPrefix -VirtualNetwork $vNet
    $vNetSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $vNetSubNetName -VirtualNetwork $vNet
}
Write-Host "Using subnet" $vNetSubnet.Name "with address prefix" $vNetSubnet.AddressPrefix 

#Setup security group and initial rules for the virtual network to allow RDP traffic to all VMs in the subnet   
$nsgName = Read-Host "Enter subnet Network Security Group name"

Write-Host "Setting rule to allow RDP access for all VMs in this subnet"
$rules = @()
#$RDPrule=New-AzureRMNetworkSecurityRuleConfig -Name "RDPTraffic" -Description "Allow RDP to all VMs on the subnet" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389
#$rules = $rules + $RDPrule
#add this rule to the network security rules to allow HTTP traffic to it
#$rule2 = New-AzureRMNetworkSecurityRuleConfig -Name "WebTraffic" -Description "Allow HTTP to the SharePoint server" -Access Allow -Protocol Tcp -Direction Inbound -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix "10.0.0.6/32" -DestinationPortRange 80
$rulePriority=100
$webIP = Read-Host "Enter destination address prefix of server to allow traffic, e.g. 10.0.0.6/32, enter * for all IPs, or enter blank value and press [Enter] when complete"
while ($webIP)
{
    $webRuleName = Read-Host "Enter name for this rule (no spaces)"
    $webRuleDescription = Read-Host "Enter description of this rule"
    $webPort = Read-Host "Enter port to allow traffic on e.g. 80 for web traffic, 3389 for RDP, 1433 for SQL"
    
    $webAccessType = Read-Host "Enter Access type: Allow or Deny (default Allow)"
    if (!$webAccessType) {
        $webAccessType = "Allow"
    }

    $webProtocol = Read-Host "Enter protocol, (default Tcp)"
    if (!$webProtocol)
    {
        $webProtocol = "Tcp"
    }

    $webDirection = Read-Host "Enter traffic direction, (default Inbound)"
    if (!$webDirection) {
        $webDirection = "Inbound"
    }

    $sourceAddressPrefix = Read-Host "Enter source address prefix, (default Internet)"
    if (!$sourceAddressPrefix)
    {
        $sourceAddressPrefix = "Internet"
    }

    $sourcePortRange = Read-Host "Enter source port range, default *"
    if (!$sourcePortRange) {
        $sourcePortRange="*"
    }
    
    $webRule = New-AzureRMNetworkSecurityRuleConfig -Name $webRuleName -Description $webRuleDescription -Access $webAccessType -Protocol $webProtocol -Direction $webDirection -Priority $rulePriority -SourceAddressPrefix $sourceAddressPrefix -SourcePortRange $sourcePortRange -DestinationAddressPrefix $webIP -DestinationPortRange $webPort
    
    $rules = $rules + $webRule
    Write-Host ".............."
    Write-Host "Rule Added"
    Write-Host ".............."
    $rulePriority = $rulePriority+1
    $webIP = Read-Host "Enter destination address prefix of server to allow traffic, e.g. 10.0.0.6/32, enter * for all IPs, or enter blank value and press [Enter] when complete"

}

$nsg = New-AzureRMNetworkSecurityGroup -Name $nsgName -ResourceGroupName $rgName -Location $locName -SecurityRules $rules

#Add the security group to the subnet
Set-AzureRMVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $nsgName -AddressPrefix $vNetSubNetAddressPrefix -NetworkSecurityGroup $nsg

Write-Host "Begin configuration of environment VMs"

$createVM = Read-Host "Press [Enter] to continue or type 'Done' to end creation of VMs"

    while (!$createVM) {
        #Set private IP address for this VM
        while (!$privateIPAddress){
            $privateIPAddress = Read-Host("Enter Private IP address, e.g. 10.0.0.4")
        
        }
        while (!$vmName) {
            $vmName = Read-Host "Enter VM Name (no spaces, 8 characters or less)"
        }

        #Select VM Sizing
        while (!$vmSize) {
            $vmSizeMaxCores = Read-Host "Enter maximum number of cores for VM, e.g. 4"
            $vmSizeMaxRam = Read-Host "Enter maximum RAM for VM in MB, e.g. 4096" 
            $vmSizeMaxDataDiskCount = Read-Host "Enter maximum data disks to be attached, e.g. 2"
            Get-AzureRmVMSize -Location $locName | Where NumberOfCores -le $vmSizeMaxCores | Where MemoryInMB -le $vmSizeMaxRam| Where MaxDataDiskCount -le $vmSizeMaxDataDiskCount | Select Name, NumberOfCores, MemoryInMB, MaxDataDiskCount | Format-Table
            $vmSize = Read-Host "Enter Name of VM Size for VM" $privateIPAddress "or press [Enter] to search sizes again"
        }
        
        # Create an availability set for domain controller virtual machines
        $avSetName = Read-Host "Enter availability set name, or press [Enter] for none"
        if ($avSetName) {
            $avSet = New-AzureRMAvailabilitySet -Name $avSetName -ResourceGroupName $rgName -Location $locName
        }
        while (!$nicName) {
            $nicName = Read-Host "Enter NIC name, e.g. 'adVM-NIC'"
        }
        $allocationMethod = Read-Host "Enter allocation method, press [Enter] for default value 'Dynamic'"
        if (!$allocationMethod)
        {
            $allocationMethod = "Dynamic"
        }
        $pip = New-AzureRmPublicIpAddress -Name $nicName -ResourceGroupName $rgName -Location $locName -AllocationMethod $allocationMethod
        $nic = New-AzureRmNetworkInterface - Name $nicName -ResourceGroupName $rgName -Location $locName -Subnet $vNetSubnet -PublicIpAddress $pip.Id -PrivateIpAddress $privateIPAddress
        if (!$avSet) {
            $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
        } else {
            $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $avSet.Id
        }

        $storageAcc=Get-AzureRMStorageAccount -ResourceGroupName $rgName -Name $saName
        $numOfDisks = Read-Host ("How many additional disks should be added? (Default 1)")
        if (!$numOfDisks)
        {
            $numOfDisks = 1
        }

        for ($i=0; $i -lt $numOfDisks; $i++){
            $vmDiskName=Read-Host "Enter disk identifier name (no spaces) e.g. ADDS-Data"
            $vmDiskSize=Read-Host "Enter disk size in GB, e.g. 20"
            $vhdURI = $storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/" + $vmName +"-"+$vnetName+"-"+$vmDiskName + ".vhd"
            #for now only allow creation of empty disks, later version might have coding for image files
            Add-AzureRmVMDataDisk -VM $vm -Name $vmDiskName -DiskSizeInGB $vmDiskSize -VhdUri $vhdURI -CreateOption Empty
            $vmDiskName=""
            $vmDiskSize=""
            $vhdURI = ""
        }

        $cred=Get-Credential -Message "Type the name and password of the local administrator account for the VM"
        #Will only do Windows machines, later version may include option for Linux configuration
        $vm=Set-AzureRMVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
        

        #This takes awhile so will do this once and keep the results for later
        if (!$publishers){
            $publishers = Get-AzureRmVMImagePublisher -Location $locName | Where PublisherName -Like "*Microsoft*" | Select PublisherName
            $offers = $publishers | foreach {Get-AzureRmVMImageOffer -Location $locName -PublisherName $_.PublisherName } | Select Offer, PublisherName
            $skus = $offers | foreach {Get-AzureRmVMImageSku -Location $locName -PublisherName $_.PublisherName -Offer $_.Offer} | Select PublisherName, Offer, Skus
        }
        $skus |Format-Table -AutoSize
        $skuName = Read-Host "Enter SKU Name to be selected"
        $offerName = $skus | Where Skus -eq $skuName | Select Offer
        $publisherName = $skus | Where Skus -eq $skuName | Select PublisherName
        $version = Read-Host "Enter version of deployment, press [Enter] to use default of 'latest'"

        if (!$version){
            $version="latest"
        }
        $vm=Set-AzureRMVMSourceImage -VM $vm -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $version
        $vm=Add-AzureRMVMNetworkInterface -VM $vm -Id $nic.Id
        $osDiskUri=$storageAcc.PrimaryEndpoints.Blob.ToString() + "vhds/"+$vmName+"-"+$vnetName+"-OSDisk.vhd"
        $vm=Set-AzureRMVMOSDisk -VM $vm -Name adVM-SP2016Vnet-OSDisk -VhdUri $osDiskUri -CreateOption fromImage
        New-AzureRMVM -ResourceGroupName $rgName -Location $locName -VM $vm


        $createVM = Read-Host "Press [Enter] to continue or type 'Done' to end creation of VMs"
        #reset all variables for new VM 
        $privateIPAddress=''
        $vmName=''
        $avSetName=''
        $nicName=''
        $allocationMethod=''
        $pip=''
        $nic=''
        $avSet=''
        $vm=''
        $vmSize=''
        $vmSizeMaxCores=''
        $vmSizeMaxRam=''
        $vmSizeMaxDataDiskCount=''
        $storageAcc = ""
        $vmDiskName=""
        $vmDiskSize=""
        $vhdURI=""
        $cred=""
        $skuName = ""
        $offerName = ""
        $publisherName = ""
}

Write-Host "For a SharePoint Farm configuration follow steps for individual VM configurations athttps://technet.microsoft.com/library/mt723354.aspx"



