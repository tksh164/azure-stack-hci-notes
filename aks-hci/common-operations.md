# よく行う操作

## 停止方法 / 再開方法

Azure VM (Hyper-V ホスト) を停止/開始する前には、AKS on HCI VM や Azure Stack HCI ノード VM を適切な状態にします。

### 停止方法

Azure Stack HCI クラスター上で動作している VM 数によりますが、停止処理がすべて完了するまでには数分かかります。

```powershell
Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
    # Get any running VMs on Azure Stack HCI cluster and turn them off.
    Get-ClusterResource | Where-Object -FilterScript { $_.ResourceType -eq 'Virtual Machine' } | Stop-ClusterResource -Verbose

    # Stop the cluster
    Stop-Cluster -Force -Verbose
}

# Turn off Azure Stack HCI node VMs on your Hyper-V host.
Get-VM | Stop-VM -Force -Verbose
```

### 再開方法

Azure Stack HCI クラスター上に存在する VM 数によりますが、再開処理がすべて完了するまでには数分かかります。

```powershell
# Turn on Azure Stack HCI node VMs on your Hyper-V host.
Get-VM | Start-VM -Verbose

Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
    # Start the cluster
    Start-Cluster -Verbose

    # Get any VMs on Azure Stack HCI cluster and turn them on.
    Get-ClusterResource | Where-Object -FilterScript { $_.ResourceType -eq 'Virtual Machine' } | Start-ClusterResource -Verbose
}
```

再開後は、Azure Stack HCI と AKS on HCI の接続状態を確認しておきます。

```powershell
Invoke-Command -ComputerName 'azshcinode01.azshci.local' -ScriptBlock {
    Write-Host -Object 'AzureStack HCI connection status' -ForegroundColor Cyan
    Get-AzureStackHCI

    Write-Host -Object 'AKS on HCI connection status' -ForegroundColor Cyan
    Get-AksHciBillingStatus -ErrorAction Continue | fl *
}
```

## Azure VM (Hyper-V ホスト) から Azure Stack HCI ノードへの各種アクセス方法

#### PowerShell

- Azure VM (Hyper-V ホスト) 上から接続する場合は (既に Domain Admin としてサインインしているため)、資格情報の入力を省略できるので、`-ComputerName` を使用するのが便利です。

    ```powershell
    Enter-PSSession -ComputerName 'azshcinode01'
    ```

- PowerShell Direct を使用した PSSession でも接続できます。

    ```powershell
    Enter-PSSession -VMName 'AZSHCINODE01'
    ```

- 資格情報

    | 役割 | ユーザー | パスワード |
    | ---- | ---- | ---- |
    | Domain Admin | `azshci\AzureUser` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode01\Administrator` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode02\Administrator` | デプロイ時に指定した Azure VM のパスワード |

### Hyper-V マネージャー

- Azure VM (Hyper-V ホスト) 上には Hyper-V マネージャーがインストールされています。
- 各 HCI ノードに接続すれば Hyper-V マネージャーから操作できます。
    - `azshcinode01.azshci.local`
    - `azshcinode02.azshci.local`

### vmconnect.exe

- Hyper-V マネージャーから vmconnect.exe を使用して HCI ノード VM のコンソールに接続できます。
- 拡張セッションを使用して接続できます。

- 資格情報

    | 役割 | ユーザー | パスワード |
    | ---- | ---- | ---- |
    | ローカル Administrator | `azshcinode01\Administrator` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode02\Administrator` | デプロイ時に指定した Azure VM のパスワード |

### ファイル システム

- HCI ノードにはファイル サーバーの役割がインストールされています。

- Azure VM (Hyper-V ホスト) 上の Explorer からアクセスできます。
    - `\\azshcinode01\C$`
    - `\\azshcinode02\C$`

- 資格情報

    | 役割 | ユーザー | パスワード |
    | ---- | ---- | ---- |
    | Domain Admin | `azshci\AzureUser` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode01\Administrator` | デプロイ時に指定した Azure VM のパスワード |
    | ローカル Administrator | `azshcinode02\Administrator` | デプロイ時に指定した Azure VM のパスワード |

### フェールオーバー クラスター マネージャー

- Azure VM (Hyper-V ホスト) 上にはフェールオーバー クラスター マネージャーがインストールされています。
- `azshciclus.azshci.local` に接続すればフェールオーバー クラスター マネージャーから操作できます。

### kubectl によるワークロード クラスターへのアクセス

`kubectl` を使用する際は、[Get-AksHciCredential](https://docs.microsoft.com/en-us/azure-stack/aks-hci/reference/ps/get-akshcicredential) コマンドレットで使用するワークロード クラスターを切り替えてから操作します。

Get-AksHciCredential コマンドレットを使用すると、指定したワークロード クラスターの `kubeconfig` ファイルを `kubectl` の既定の `kubeconfig` ファイルとして設定してくれます。

```powershell
Get-AksHciCredential -Name 'akswc1'
```

HCI ノード上では、`kubectl` は `C:\Program Files\AksHci\kubectl.exe` にインストールされており、パスが通されています。

```powershell
PS C:\> $env:PATH
C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Windows\System32\OpenSSH\;C:\Users\AzureUser\AppData\Local\Microsoft\WindowsApps;C:\Program Files\AksHci;
```


## Azure Stack HCI の登録に関する操作

- TODO


## AKS on Azure Stack HCI の登録に関する操作

### OutOfPolicy

管理クラスター作成後 60 日以内にワークロード クラスターを作成しない場合、AKS on HCI は OutOfPolicy 状態になります。
OutOfPolicy 状態では、AKS on HCI の更新 (Update-AksHci コマンドレットの実行) や新しいワークロード クラスターの作成はできません。

AKS on HCI が OutOfPolicy 状態になってしまった場合、AKS on HCI (管理クラスター) をアンインストールし、再度デプロイする必要があります。

- [AKS on Azure Stack HCI goes out-of-policy if a workload cluster hasn't been created in 60 days.](https://docs.microsoft.com/en-us/azure-stack/aks-hci/known-issues-upgrade#aks-on-azure-stack-hci-goes-out-of-policy-if-a-workload-cluster-hasn-t-been-created-in-60-days-)

例えば、新しいワークロード クラスターを作成しようとした場合、以下のような Billing が OutOfPolicy というエラーで失敗します。

```powershell
C:\Program Files\AksHci\kvactl.exe cluster create --clusterconfig "C:\ClusterStorage\AksHciVol\AKS-HCI\WorkingDir\1.0.12.10727\yaml\akswc1.yaml"  --kubeconfig "C:\ClusterStorage\AksHciVol\AKS-HCI\WorkingDir\1.0.12.10727\kubeconfig-mgmt" System.Collections.Hashtable.generic_non_zero 1 [Error: Failed get status for addon akshci-billing: Please check on your Azure Registration and try again: Billing is OutOfPolicy]
At C:\Program Files\WindowsPowerShell\Modules\Kva\1.0.32\Common.psm1:2228 char:9
+         throw $errMessage
+         ~~~~~~~~~~~~~~~~~
    + CategoryInfo          : OperationStopped: (C:\Program File...is OutOfPolicy]:String) [], RuntimeException
    + FullyQualifiedErrorId : C:\Program Files\AksHci\kvactl.exe cluster create --clusterconfig "C:\ClusterStorage\AksHciVol\AKS-HCI\WorkingDir\1.0.12.10727\yaml\akswc1.yaml"  --kubeconfig "C:\ClusterStorage\AksHciVol\AKS-HCI\WorkingDir\1.0.12.10727\kubeconfig-mgmt" System.Collections.Hashtable.generic_non_zero 1 [Error: Failed get status for addon akshci-billing: Please check on your Azure Registration and try again: Billing is OutOfPolicy]
```

この場合、[Get-AksHciBillingStatus](https://docs.microsoft.com/en-us/azure-stack/aks-hci/reference/ps/get-akshcibillingstatus) コマンドレットで課金の状態を確認すると、ConnectionStatus は OutOfPolicy になっています。

```powershell
PS C:\> Get-AksHciBillingStatus | fl *

AzureResourceName : akshci-mgmt-cluster-220805-0320
AzureResourceUri  : /subscriptions/55555555-6666-7777-8888-999999999999/resourceGroups/aksazshci/providers/Microsoft.Kubernetes/connectedClusters/akshci-mgmt-cluster-220805-0320
ConnectionStatus  : OutOfPolicy
LastConnected     : 2022-08-10T06:30:05Z
```

[Sync-AksHciBilling](https://docs.microsoft.com/en-us/azure-stack/aks-hci/reference/ps/sync-akshcibilling) コマンドレットを使用して課金情報を同期すると、アップロードに成功したことを示すメッセージが表示されますが、Get-AksHciBillingStatus コマンドレットで確認できる ConnectionStatus は OutOfPolicy のままで、OutOfPolicy 状態が解消されることはありません。

```powershell
PS C:\> Sync-AksHciBilling
Upload Successful!
```


## 管理クラスターの名前を取得

```powershell
(Get-AksHciConfig).Kva.kvaName
```


## kubectl で管理クラスターにアクセス

`WorkingDir` 配下に管理クラスターに接続するための `kubeconfig` ファイルが `kubeconfig-mgmt` という名前で配置されています。

なお、`WorkingDir` 配下には `kubectl` の実行ファイルも配置されています。

Azure VM (Hyper-V ホスト) 上からのアクセス例

```powershell
PS C:\work> $env:KUBECONFIG = '\\azshcinode01\C$\ClusterStorage\AksHciVol\AKS-HCI\WorkingDir\1.0.12.10727\kubeconfig-mgmt'
PS C:\work> .\kubectl.exe get services
NAME         TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   164m
```


## 管理クラスターへの ssh アクセス

管理クラスターには `clouduser` というユーザーが存在します。`clouduser` として管理クラスターに `ssh` 接続するためのプライベート キーは `WorkingDir` 配下の `.ssh` フォルダー内に保存されています。

例: `\\azshcinode01\C$\ClusterStorage\aksvol\AKS-HCI\WorkingDir\.ssh\akshci_rsa`

なお、ssh コマンドで使用するためには、プライベート キー ファイルのアクセス許可は**自分のみ**に設定されている必要があります。

- 接続例

    ```powershell
    PS C:\> ssh.exe clouduser@10.10.13.11 -i 'C:\work\akshci_rsa'
    The authenticity of host '10.10.13.11 (10.10.13.11)' can't be established.
    ECDSA key fingerprint is SHA256:bo2lhIfaNxYfLlIOnUEg5RBoe5dJZT/UllBhyQI12RI.
    Are you sure you want to continue connecting (yes/no)? y
    Please type 'yes' or 'no': yes
    Warning: Permanently added '10.10.13.11' (ECDSA) to the list of known hosts.
    clouduser@moc-l7i1xvl2ew2 [ ~ ]$
    ```


## ログの確認

[Get-AksHciLogs](https://docs.microsoft.com/en-us/azure-stack/aks-hci/reference/ps/get-akshcilogs) コマンドレットを使用すると AKS on HCI 関連の各種ログを含んだ zip ファイルを生成できます。

ログの zip ファイルは WorkingDir 配下に保存されます。

例: `\\azshcinode01\C$\ClusterStorage\AksHciVol\AKS-HCI\WorkingDir\1.0.12.10727\akshcilogskfufig12.45p.zip`

