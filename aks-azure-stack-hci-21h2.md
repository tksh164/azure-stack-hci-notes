# AKS on Azure Stack HCI 21H2

## Azure Stack HCI クラスターの作成

[Azure Stack HCI 21H2 - Evaluation Guide](https://github.com/Azure/AzureStackHCI-EvalGuide/tree/21H2) に従って Azure Stack HCI クラスターを作成します。

**main** ブランチではなく、**21H2** ブランチを使用します。

### Part 1 - Complete the prerequisites - deploy your Azure VM

[Deploy your Azure VM (Prerequisite)](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/1_DeployAzureVM.md) を参考にして Azure VM (Hyper-V ホスト) をデプロイします。

1. カスタム ARM テンプレートを使用してデプロイします。デプロイに要する時間は 35 分程度です。

    - VM サイズは **Standard_E16s_v4** が事実上の最低サイズです。これ以上小さいサイズを選択した場合、環境は作れたとしてもその後の検証がほぼ何もできません。
    - データ ディスク サイズは **64** を選択します。
        - 256 GB (32 GB x 8 ディスク) ではディスク容量が不足しやすいです。
        - Azure VM 停止時の AKS VM の保存容量、HCI ノード VM のメモリを増やした場合の VMRS ファイルのサイズなど、VHDX のサイズ以外にもディスク容量が必要になります。ディスク容量が不足すると VMRS ファイルを作成できず、VM を起動できません。
        - Azure VM のディスクは Simple 構成の記憶域スペースなので、後から容量を増やすのは難しいです。
    - 今回は DHCP は使用しない場合を例示するので、DHCP は **Disabled** を選択します。
    - 時々デプロイが失敗します。失敗した場合は、失敗したリソース グループを削除しつつ、再デプロイします。多くても 2 ～ 3 回デプロイすれば大概成功します。

2. デプロイ完了後、Azure VM (Hyper-V ホスト) に RDP 接続したら、Azure VM (Hyper-V ホスト) にすべての更新プログラムを適用します。

    - これにより、AKS on HCI の構成し始めてから更新プログラムが適用されて再起動が発生してしまうことを避けられます。

3. Azure VM (Hyper-V ホスト) 上の HCI ノード VM の RAM サイズを可能な範囲で増やしておきます。

    - Standard_E16s_v4 で 2 ノードなら、**57344 MB** 程度に増やしておくのが良いです。
        - 56 GB = (HCI ノード VM RAM: 128 GB - Hyper-V ホスト分: 16 GB) / 2 ノード。
        - VMRS ファイル サイズは 2 ノード分で 112 GB です。

### Part 2 - Configure your Azure Stack HCI 21H2 Cluster

[Configure your Azure Stack HCI 21H2 Cluster](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/2_DeployAzSHCI.md) を参考にして Azure Stack HCI クラスターを作成します。

1. ホスト ネットワークを構成します。

    - One physical network adapter for management
        - Management
            - Node 1: 192.168.0.2/16
            - Node 2: 192.168.0.3/16

    - Create one virtual switch for compute only
        - Compute
            - Node 1: 10.10.13.1/24
            - Node 2: 10.10.13.2/24
        - Storage
            - Node 1: 10.10.11.1/24
            - Node 1: 10.10.12.1/24
            - Node 2: 10.10.11.2/24
            - Node 2: 10.10.12.2/24

2. クラウド監視を構成します。

    ```powershell
    $params = @{
        Name                   = 'azshciwitness0{0}' -f (-join ((48..57) + (97..122) | Get-Random -Count 4 |% {[char]$_}))
        ResourceGroupName      = 'aksazshci'
        Location               = 'japaneast'
        SkuName                = 'Standard_LRS'
        Kind                   = 'StorageV2'
        EnableHttpsTrafficOnly = $true
        MinimumTlsVersion      = 'TLS1_2'
        AllowBlobPublicAccess  = $false
    }
    $sa = New-AzStorageAccount @params

    $sa.Context | Format-List -Property StorageAccountName,@{ Name = 'Endpoint'; Expression = { $_.EndpointSuffix.Trim('/') } }
    $sa | Get-AzStorageAccountKey
    ```

### Part 3 - Integrate Azure Stack HCI 21H2 with Azure

[Integrate Azure Stack HCI 21H2 with Azure](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/3_AzSHCIIntegration.md) を参考にして Azure Stack HCI クラスターを Azure に登録します。

1. Hyper-V ホスト上 (Azure VM 上) に必要な PowerShell モジュールをインストールします。

    ```powershell
    Install-PackageProvider -Name NuGet -Force -Verbose
    Install-Module -Name 'PowershellGet' -Scope AllUsers -Confirm:$false -SkipPublisherCheck -Force -Verbose

    Install-Module -Name 'Az.StackHCI' -Scope AllUsers -Confirm:$false -Verbose
    ```

2. PowerShell を閉じて起動し直します。

    - インストールした PowerShell モジュールが確実に読み込まれるように PowerShell を開き直しておきます。

3. Azure Stack HCI クラスターを Azure に登録します。

    ```powershell
    $clusterName             = 'azshciclus'                 # The Azure Stack HCI cluster name. The evaluation guide uses this name.
    $computerName            = 'azshcinode01.azshci.local'  # The node name that one of the cluster nodes in the Azure Stack HCI cluster.
    $credential              = Get-Credential -UserName 'azshci\AzureUser' -Message 'Enter the password'

    $tenantId                = '00000000-1111-2222-3333-444444444444'
    $subscriptionId          = '55555555-6666-7777-8888-999999999999'
    $azshciResourceGroupName = 'aksazshci'
    $azshciRegion            = 'SoutheastAsia'
    $azshciResourceName      = '{0}-{1}-{2}' -f $clusterName, $azshciResourceGroupName, (Get-Date).ToString('yyMMdd-HHmm')
    $arcResourceGroupName    = '{0}-arc' -f $azshciResourceGroupName

    $params = @{
        ComputerName               = $computerName             # The cluster name or one of the cluster node name in the cluster that is being registered to Azure.
        Credential                 = $credential               # The credential for the ComputerName. Use the password specified during Azure VM deployment.

        TenantId                   = $tenantId                 # The Azure AD tenant that associated with Azure subscription to create the Azure Stack HCI resource.
        SubscriptionId             = $subscriptionId           # The Azure subscription to create the Azure Stack HCI resource.
        ResourceGroupName          = $azshciResourceGroupName  # The resource group to create the Azure Stack HCI resource.
        Region                     = $azshciRegion             # The region to create the Azure Stack HCI resource. Be sure to specify the supported region. https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure
        ResourceName               = $azshciResourceName       # The resource name of the Azure Stack HCI resource. The default value is the cluster name.

        EnableAzureArcServer       = $true                     # Set $true if want to register Azure Stack HCI cluster as Azure Arc-enabled server.
        ArcServerResourceGroupName = $arcResourceGroupName     # The resource group to create the Arc resource of Azure Stack HCI nodes.

        Verbose                    = $true
    }
    Register-AzStackHCI @params
    ```

3. Azure Stack HCI クラスターの登録状態を確認します。

    ```powershell
    Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
        Get-AzureStackHCI
    }
    ```

    実行結果の例:

    ```powershell
    PSComputerName     : azshcinode01.azshci.local
    RunspaceId         : 791b714b-ba27-4b84-aa2e-dc62c59f7d3c
    ClusterStatus      : Clustered
    RegistrationStatus : Registered
    RegistrationDate   : 7/15/2022 4:53:08 AM
    AzureResourceName  : azshciclus-aksazshci4-220715-0448
    AzureResourceUri   : /Subscriptions/55555555-6666-7777-8888-999999999999/resourceGroups/aksazshci4/providers/Microsoft.AzureStackHCI/clusters/azshciclus-aksazshci4-220715-0448
    ConnectionStatus   : Connected
    LastConnected      : 7/15/2022 4:57:18 AM
    IMDSAttestation    : Disabled
    DiagnosticLevel    : Basic
    ```

## AKS on HCI を構成するための Azure VM (Hyper-V) ホスト上の準備

### ボリュームの作成

```powershell
Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
    New-Volume -FriendlyName 'AksHciVol' -StoragePoolFriendlyName 'S2D*' -FileSystem CSVFS_ReFS -UseMaximumSize -ProvisioningType Fixed -ResiliencySettingName Mirror -Verbose
}
```

### NAT を構成

```powershell
Get-NetAdapter -Name '*InternalNAT*' | New-NetIPAddress -AddressFamily IPv4 -IPAddress 10.10.13.254 -PrefixLength 24

New-NetNat -Name 'AzSHCINAT-Compute' -InternalIPInterfaceAddressPrefix 10.10.13.0/24
```

構成結果を確認

```powershell
Get-NetAdapter -Name '*InternalNAT*' | Get-NetIPAddress | Format-Table -Property InterfaceIndex,InterfaceAlias,IPAddress,PrefixLength,AddressFamily

Get-NetNat | Format-Table -Property Name,InternalIPInterfaceAddressPrefix,Active
```

構成結果の確認例:

```powershell
PS C:\> Get-NetAdapter -Name '*InternalNAT*' | Get-NetIPAddress | Format-Table -Property InterfaceIndex,InterfaceAlias,IPAddress,PrefixLength,AddressFamily

InterfaceIndex InterfaceAlias          IPAddress    PrefixLength AddressFamily
-------------- --------------          ---------    ------------ -------------
             8 vEthernet (InternalNAT) 192.168.0.1            16          IPv4
             8 vEthernet (InternalNAT) 10.10.13.254           24          IPv4

PS C:\> Get-NetNat | Format-Table -Property Name,InternalIPInterfaceAddressPrefix,Active

Name              InternalIPInterfaceAddressPrefix Active
----              -------------------------------- ------
AzSHCINAT         192.168.0.0/16                     True
AzSHCINAT-Compute 10.10.13.0/24                      True
```

## AKS on HCI を構成するための Azure サブスクリプション上の準備

リソース プロバイダーを登録します。

```powershell
Get-AzResourceProvider -ProviderNamespace 'Microsoft.Kubernetes'
Get-AzResourceProvider -ProviderNamespace 'Microsoft.KubernetesConfiguration'
```

## AKS on HCI を構成するための HCI ノード上の準備

### HCI ノードへの AksHci PowerShell モジュールのインストール

```powershell
$hciNodes = 'azshcinode01.azshci.local', 'azshcinode02.azshci.local'

Invoke-Command -ComputerName $hciNodes -ScriptBlock {
    Install-PackageProvider -Name 'NuGet' -Force -Verbose
    Install-Module -Name 'PowershellGet' -Confirm:$false -SkipPublisherCheck -Force -Verbose
}
```

```powershell
$hciNodes = 'azshcinode01.azshci.local', 'azshcinode02.azshci.local'

Invoke-Command -ComputerName $hciNodes -ScriptBlock {
    Install-Module -Name 'Az.Accounts' -Repository 'PSGallery' -RequiredVersion 2.2.4 -Force -Verbose
    Install-Module -Name 'Az.Resources' -Repository 'PSGallery' -RequiredVersion 3.2.0 -Force -Verbose
    Install-Module -Name 'AzureAD' -Repository 'PSGallery' -RequiredVersion 2.0.2.128 -Force -Verbose
    Install-Module -Name 'AksHci' -Repository 'PSGallery' -AcceptLicense -Force -Verbose 
}
```

### HCI ノードの要件の検証

```powershell
Initialize-AksHciNode
```

## AKS on HCI (AKS ホスト / 管理クラスター) の作成

### 管理クラスターで使用する仮想ネットワークを作成

```powershell
$params = @{
    Name               = 'akshci-main-network'
    VSwitchName        = 'ComputeSwitch'
    Gateway            = '10.10.13.254'
    DnsServers         = '192.168.0.1'
    IpAddressPrefix    = '10.10.13.0/24'
    K8sNodeIpPoolStart = '10.10.13.10'
    K8sNodeIpPoolEnd   = '10.10.13.149'
    VipPoolStart       = '10.10.13.150'
    VipPoolEnd         = '10.10.13.250'
}
$vnet = New-AksHciNetworkSetting @params
```

### AKS on HCI の構成を作成

```powershell
$VerbosePreference = 'Continue'

$clusterRoleName = 'akshci-mgmt-cluster-{0}' -f (Get-Date).ToString('yyMMdd-HHmm')
$baseDir         = 'C:\ClusterStorage\AksHciVol\AKS-HCI'

$params = @{
    ImageDir            = Join-Path -Path $baseDir -ChildPath 'Images'
    WorkingDir          = Join-Path -Path $baseDir -ChildPath 'WorkingDir'
    CloudConfigLocation = Join-Path -Path $baseDir -ChildPath 'Config'
    SkipHostLimitChecks = $false
    ClusterRoleName     = $clusterRoleName
    CloudServiceCidr    = '192.168.0.11/16'
    VNet                = $vnet
    KvaName             = $clusterRoleName
    ControlplaneVmSize  = 'Standard_D4s_v3'
    Verbose             = $true
}
Set-AksHciConfig @params
```

### 管理クラスターを Azure Arc-enabled Kubernetes として登録するための構成を作成

```powershell
$VerbosePreference = 'Continue'

$tenantId          = '00000000-1111-2222-3333-444444444444'
$subscriptionId    = '55555555-6666-7777-8888-999999999999'
$resourceGroupName = 'aksazshci'

$params = @{
    TenantId                = $tenantId           # The Azure AD tenant that associated with Azure subscription to create the Azure Arc-enabled Kubernetes resource for the management cluster.
    SubscriptionId          = $subscriptionId     # The Azure subscription to create the Azure Arc-enabled Kubernetes resource for the management cluster.
    ResourceGroupName       = $resourceGroupName  # The resource group to create the Azure Arc-enabled Kubernetes resource for the management cluster.
    UseDeviceAuthentication = $true               # Use the OAuth 2.0 device authorization grant flow. The registration operation authorizes with the output URL and code in a web browser.
    Verbose                 = $true
}
Set-AksHciRegistration @params
```

### 管理クラスターを作成

```powershell
$VerbosePreference = 'Continue'
Install-AksHci -Verbose
```

## ワークロード クラスターの作成

```powershell
$params = @{
    Name                  = 'akswc1'
    ControlPlaneNodeCount = 1
    ControlplaneVmSize    = 'Standard_A4_v2'
    LoadBalancerVmSize    = 'Standard_A2_v2'
    NodePoolName          = 'nodepool1'
    NodeCount             = 1
    NodeVmSize            = 'Standard_A2_v2'
    OSType                = 'Linux'
    Verbose               = $true
}
New-AksHciCluster @params
```

## よく行う操作

### 停止方法 / 再開方法

#### 停止方法

```powershell
$creds = Get-Credential -UserName 'azshci\AzureUser' -Message 'Enter the password for the account'
$hciVMName = 'AZSHCINODE01'

Invoke-Command -VMName $hciVMName -Credential $creds -ScriptBlock {
    # Get any running VMs on Azure Stack HCI and turn them off.
    Get-ClusterResource | Where-Object -FilterScript { $_.ResourceType -eq 'Virtual Machine' } | Stop-ClusterResource -Verbose

    # Stop the cluster
    Stop-Cluster -Force -Verbose
}

# Power down Azure Stack HCI node VMs on your Hyper-V host.
Get-VM | Stop-VM -Force -Verbose
```

#### 再開方法

```powershell
$creds = Get-Credential -UserName 'azshci\AzureUser' -Message 'Enter the password for the account'
$hciVMName = 'AZSHCINODE01'

Get-VM | Start-VM -Verbose

Invoke-Command -VMName $hciVMName -Credential $creds -ScriptBlock {
    # Stop the cluster
    Start-Cluster -Verbose

    # Get any running VMs on Azure Stack HCI and turn them off.
    Get-ClusterResource | Where-Object -FilterScript { $_.ResourceType -eq 'Virtual Machine' } | Start-ClusterResource -Verbose
}
```

### Azure VM (Hyper-V ホスト) から Azure Stack HCI ノードへの各種アクセス方法

#### vmconnect.exe

- 拡張セッションを使用して接続できます。

- 資格情報

    | 役割 | ユーザー | パスワード |
    | ---- | ---- | ---- |
    | ローカル Administrator | `azshcinode01\Administrator` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode02\Administrator` | デプロイ時に指定した Azure VM のパスワード |

#### PowerShell

- Azure VM (Hyper-V ホスト) 上から接続する場合は、資格情報を省略できるので、`-ComputerName` を使用するのが便利です。

    ```powershell
    Enter-PSSession -ComputerName azshcinode01
    ```

- PowerShell Direct を使用した PSSession でも接続できます。

    ```powershell
    Enter-PSSession -VMName azshcinode01
    ```

- 資格情報

    | 役割 | ユーザー | パスワード |
    | ---- | ---- | ---- |
    | Domain Admin | `azshci\AzureUser` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode01\Administrator` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode02\Administrator` | デプロイ時に指定した Azure VM のパスワード |

#### ファイル システム

- HCI ノードにはファイル サーバーの役割はインストールされています。

- Azure VM (Hyper-V ホスト) 上の Explorer からアクセスできます。
    - `\\azshcinode01\C$`
    - `\\azshcinode02\C$`

- 資格情報

    | 役割 | ユーザー | パスワード |
    | ---- | ---- | ---- |
    | Domain Admin | `azshci\AzureUser` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode01\Administrator` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode02\Administrator` | デプロイ時に指定した Azure VM のパスワード |

#### フェールオーバー クラスター マネージャー

- Azure VM (Hyper-V ホスト) 上にはフェールオーバー クラスター マネージャーがインストールされています。
- `azshciclus.azshci.local` に接続すればフェールオーバー クラスター マネージャーから操作できます。

#### Hyper-V マネージャー

- Azure VM (Hyper-V ホスト) 上には Hyper-V マネージャーがインストールされています。
- 各 HCI ノードに接続すれば Hyper-V マネージャーから操作できます。
    - `azshcinode01.azshci.local`
    - `azshcinode02.azshci.local`

### AKS on HCI の削除

管理クラスターやワークロード クラスターを含めた AKS on HCI 関連の要素 (保存された構成ファイルなども含む) を全て削除します。AKS on HCI のを再構築したい場合に実行します。

```powershell
Uninstall-AksHci
```

### ワークロード クラスターの削除

管理クラスターは残したまま、ワークロード クラスターのみを削除します。

```powershell
Remove-AksHciCluster -Name 'akswc1'
```

### Azure Stack HCI の登録に関する操作


### ログの確認

