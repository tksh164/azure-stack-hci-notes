# AKS on Azure Stack HCI 21H2

## Azure Stack HCI クラスターの作成

[Azure Stack HCI 21H2 - Evaluation Guide](https://github.com/Azure/AzureStackHCI-EvalGuide/tree/21H2) に従って Azure Stack HCI クラスターを作成します。

**main** ブランチではなく、**21H2** ブランチを使用します。

### Part 1 - Complete the prerequisites - deploy your Azure VM

1. [Deploy your Azure VM (Prerequisite)](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/1_DeployAzureVM.md) に従って、カスタム ARM テンプレートを使用したデプロイをします。

    - VM サイズは **Standard_E16s_v4** が事実上の最低サイズです。これ以上小さいサイズを選択した場合、環境は作れたとしてもその後の検証がほぼ何もできません。
    - データ ディスク サイズは **64** を選択します。
        - 256 GB (32 GB x 8 ディスク) ではディスク容量が不足しやすいです。
        - Azure VM 停止時の AKS VM の保存容量、HCI ノード VM のメモリを増やした場合の VMRS ファイルのサイズなど、VHDX のサイズ以外にもディスク容量が必要になります。ディスク容量が不足すると VMRS ファイルを作成できず、VM を起動できません。
        - Azure VM のディスクは Simple 構成の記憶域スペースなので、後から容量を増やすのは難しいです。
    - 今回は DHCP は使用しない場合を例示するので、DHCP は **Disabled** を選択します。
    - 時々デプロイが失敗します。失敗した場合は、失敗したリソース グループを削除しつつ、再デプロイします。多くても 2 ～ 3 回デプロイすれば大概成功します。

2. AKS on HCI の構成し始めてから更新プログラムが適用されて、再起動が発生するのを避けるために、デプロイ完了後 RDP 接続したらすべての更新プログラムを適用しておきます。

3. HCI ノード VM の RAM サイズを可能な範囲で増やしておきます。

    - 2 ノードなら、**57344 MB** 程度に増やしておくのが良さそうです。
        - 56 GB = (VM RAM: 128 GB - ホスト分: 16 GB) / 2 ノード
        - VMRS ファイル サイズは 2 ノード分で 112 GB です。

### Part 2 - Configure your Azure Stack HCI 21H2 Cluster

[Configure your Azure Stack HCI 21H2 Cluster](https://github.com/Azure/AzureStackHCI-EvalGuide/blob/21H2/deployment/steps/2_DeployAzSHCI.md) に従って Azure Stack HCI クラスターを作成します。

1. ホスト ネットワークの構成

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

2. Cloud witness の構成

### Part 3 - Integrate Azure Stack HCI 21H2 with Azure

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
