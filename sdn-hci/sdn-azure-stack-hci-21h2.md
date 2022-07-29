# AKS on Azure Stack HCI 21H2

## Azure Stack HCI クラスターの作成

[Azure Stack HCI 21H2 - Evaluation Guide](https://github.com/Azure/AzureStackHCI-EvalGuide/tree/21H2) に従って Azure Stack HCI クラスターを作成します。

**main** ブランチではなく、**21H2** ブランチを使用します。

### Part 1 - Complete the prerequisites - deploy your Azure VM

[Deploy your Azure VM (Prerequisite)](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/1_DeployAzureVM.md) を参考にして Azure VM (Hyper-V ホスト) をデプロイします。

1. カスタム ARM テンプレートを使用してデプロイします。デプロイに要する時間は 35 分程度です。

    時々デプロイが失敗します。失敗した場合は、失敗したリソース グループを削除しつつ、再デプロイします。多くても 2 ～ 3 回デプロイすれば大概成功します。

    - Virtual Machine Size: **Standard_E16s_v4**
        - VM サイズは Standard_E16s_v4 が事実上の最低サイズです。これ以上小さいサイズを選択した場合、環境は作れたとしてもその後の検証がほぼ何もできません。
    - Data Disk Size: **64**
        - データ ディスク サイズは 64 GB x 8 ディスク (512 GB) を選択します。
        - 32 GB x 8 ディスク (256 GB) ではディスク容量が不足しやすいです。
            - Azure VM 停止時の AKS VM の保存容量、HCI ノード VM のメモリを増やした場合の VMRS ファイルのサイズなど、VHDX のサイズ以外にもディスク容量が必要になります。ディスク容量が不足すると VMRS ファイルを作成できず、VM を起動できません。
            - Azure VM のディスクは Simple 構成の記憶域スペースなので、後から容量を増やすのは難しいです。
    - Enable DHCP: **Disabled**
        - 今回は DHCP は使用しません。

2. デプロイ完了後、Azure VM (Hyper-V ホスト) に RDP 接続して Azure VM (Hyper-V ホスト) にすべての更新プログラムを適用します。

    - AKS on HCI の構成し始めてから更新プログラムが適用されて再起動が発生してしまうことを避けられます。
    - コストを節約するために既定では OS ディスクは Standard HDD LRS となっているため、更新プログラムの適用にはそれなりに時間を要します。

3. Azure VM (Hyper-V ホスト) 上の HCI ノード VM の RAM サイズを可能な範囲で増やしておきます。

    - Standard_E16s_v4 で 2 ノード クラスターなら、**57344 MB** 程度に増やしておくのが良いです。
        - 56 GB = (HCI ノード VM RAM: 128 GB - Hyper-V ホスト分: 16 GB) / 2 ノード。
        - VMRS ファイル サイズは 2 ノード分で 112 GB です。

### Part 2 - Configure your Azure Stack HCI 21H2 Cluster

[Configure your Azure Stack HCI 21H2 Cluster](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/2_DeployAzSHCI.md) を参考にして Azure Stack HCI クラスターを作成します。

1. ホスト ネットワークを構成します。

    - **One physical network adapter for management** を選択します。

        - azshcinode**01**.azshci.local

            | MAC アドレス | 名前 | IP アドレス | サブネット マスク | 説明 |
            | ---- | ---- | ---- | ---- | ---- |
            | 00-15-5D-00-04-**01** | Management<br/>(変更前の時点では Ethernet N) | 192.168.0.2 | 16 | 管理トラフィック用 |

        - azshcinode**02**.azshci.local

            | MAC アドレス | 名前 | IP アドレス | サブネット マスク | 説明 |
            | ---- | ---- | ---- | ---- | ---- |
            | 00-15-5D-00-04-**05** | Management<br/>(変更前の時点では Ethernet N) | 192.168.0.3 | 16 | 管理トラフィック用 |

    - **Create one virtual switch for compute only** を選択します。

        - azshcinode**01**.azshci.local
            - 10.10.**13**.1 の IP アドレスを持ったネットワーク アダプターを選択します。

        - azshcinode**02**.azshci.local
            - 10.10.**13**.2 の IP アドレスを持ったネットワーク アダプターを選択します。

    - 最終的なストレージ トラフィック用とコンピューティング トラフィック用ネットワーク アダプターの構成

        - azshcinode**01**.azshci.local

            | MAC アドレス | 名前 | IP アドレス | サブネット マスク | 説明 |
            | ---- | ---- | ---- | ---- | ---- |
            | 00-15-5D-00-04-**02** | Storage 1 | 10.10.11.1 | 24 | ストレージ トラフィック用 1 |
            | 00-15-5D-00-04-**03** | Storage 2 | 10.10.12.1 | 24 | ストレージ トラフィック用 2 |
            | 00-15-5D-00-04-**04** | Compute | 10.10.13.1 | 24 | コンピューティング トラフィック用 |

        - azshcinode**02**.azshci.local

            | MAC アドレス | 名前 | IP アドレス | サブネット マスク | 説明 |
            | ---- | ---- | ---- | ---- | ---- |
            | 00-15-5D-00-04-**06** | Storage 1 | 10.10.11.2 | 24 | ストレージ トラフィック用 1 |
            | 00-15-5D-00-04-**07** | Storage 2 | 10.10.12.2 | 24 | ストレージ トラフィック用 2 |
            | 00-15-5D-00-04-**08** | Compute | 10.10.13.2 | 24 | コンピューティング トラフィック用 |

2. クラウド監視を構成します。

    クラウド監視用のストレージ アカウントを作成し、そのストレージ アカウントを使用して Azure Stack HCI クラスターの監視を構成します。

    ストレージ アカウントの作成例:

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
    Install-PackageProvider -Name 'NuGet' -Scope AllUsers -Force -Verbose
    Install-Module -Name 'PowerShellGet' -Scope AllUsers -Force -Verbose
    ```

    インストールした PowerShell モジュールが確実に読み込まれるように PowerShell を閉じて起動し直した後で Az.StackHCI モジュールをインストールします。

    ```powershell
    Install-Module -Name 'Az.StackHCI' -Scope AllUsers -Force -Verbose
    ```

3. インストールした PowerShell モジュールが確実に読み込まれるように PowerShell を開き直しておきます。

4. Azure Stack HCI クラスターを Azure に登録します。

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

5. Azure Stack HCI クラスターの登録状態を確認します。

    ```powershell
    Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
        Get-AzureStackHCI
    }
    ```

    登録状態を確認した結果の例:

    ```powershell
    PS C:\> Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
    >>     Get-AzureStackHCI
    >> }

    PSComputerName     : azshcinode01.azshci.local
    RunspaceId         : 791b714b-ba27-4b84-aa2e-dc62c59f7d3c
    ClusterStatus      : Clustered
    RegistrationStatus : Registered
    RegistrationDate   : 7/15/2022 4:53:08 AM
    AzureResourceName  : azshciclus-aksazshci4-220715-0448
    AzureResourceUri   : /Subscriptions/55555555-6666-7777-8888-999999999999/resourceGroups/aksazshci/providers/Microsoft.AzureStackHCI/clusters/azshciclus-aksazshci-220715-0448
    ConnectionStatus   : Connected
    LastConnected      : 7/15/2022 4:57:18 AM
    IMDSAttestation    : Disabled
    DiagnosticLevel    : Basic
    ```

参考情報:

- [Connect and manage Azure Stack HCI registration](https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure)


