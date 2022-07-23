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
    $clusterName             = 'azshciclus'                 # Azure Stack HCI クラスターの名前です。Evaluation Guide ではこの名前になっています
    $computerName            = 'azshcinode01.azshci.local'  # Azure Stack HCI クラスター内のノードの 1 台です。Evaluation Guide ではこの名前になっています
    $credential              = Get-Credential -UserName 'azshci\AzureUser' -Message 'Enter the password'

    $tenantId                = '00000000-1111-2222-3333-444444444444'
    $subscriptionId          = '55555555-6666-7777-8888-999999999999'
    $azshciResourceGroupName = 'aksazshci'
    $azshciRegion            = 'SoutheastAsia'
    $azshciResourceName      = '{0}-{1}-{2}' -f $clusterName, $azshciResourceGroupName, (Get-Date).ToString('yyMMdd-HHmm')  # Azure Stack HCI リソースの名前。
    $arcResourceGroupName    = '{0}-arc' -f $azshciResourceGroupName

    $params = @{
        ComputerName               = $computerName             # Azure 登録する Azure Stack HCI クラスターの名前、またはいずれかのノードの名前です
        Credential                 = $credential               # ComputerName に接続するための資格情報です。デプロイ時に指定したパスワードを入力します

        TenantId                   = $tenantId                 # Azure Stack HCI リソースを作成する Azure サブスクリプションが関連付いている Azure AD テナントの ID です
        SubscriptionId             = $subscriptionId           # Azure Stack HCI リソースを作成する Azure サブスクリプションの ID です
        ResourceGroupName          = $azshciResourceGroupName  # Azure Stack HCI リソースを作成するリソース グループ名です。既存、新規どちらでも OK です
        Region                     = $azshciRegion             # Azure Stack HCI リソースを作成する場所です。サポートされているリージョンを指定する必要があります。https://docs.microsoft.com/en-us/azure-stack/hci/deploy/register-with-azure
        ResourceName               = $azshciResourceName       # Azure Stack HCI リソースの名前です。省略した場合の既定値はクラスター名です

        EnableAzureArcServer       = $true                     # Azure Stack HCI クラスター ノードを Azure Arc-enabled server として登録する場合は $true を指定します
        ArcServerResourceGroupName = $arcResourceGroupName     # Azure Stack HCI クラスター ノードの Azure Arc リソースを配置するリソース グループ名です。既存のリソース グループは指定できません

        Verbose                    = $true
    }
    Register-AzStackHCI @params
    ```

3. Azure Stack HCI クラスターの登録状態を確認します。

    ```powershell
    Invoke-Command -ComputerName $computerName -ScriptBlock {
        Get-AzureStackHCI
    }
    ```

## AKS on HCI 構成の準備

### ボリュームの作成

### NAT を構成


## AKS on HCI (AKS ホスト / 管理クラスター) の作成

### Azure サブスクリプションの準備

### AksHci PowerShell モジュールのインストール

### ノード用マシンの要件を検証

### 仮想ネットワークを作成

### AKS on HCI の構成を作成

### AKS on HCI (AKS ホスト / 管理クラスター) を作成

## ワークロード クラスターの作成
