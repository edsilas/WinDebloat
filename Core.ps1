#requires -Version 5.1
# ==========================================================================
# WinDebloat - Core.ps1
# Copyright 2026 Edsilas
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==========================================================================
<#
.SYNOPSIS
    WinDebloat - Núcleo de remoção de bloatware para Windows 10 / 11 x64.
    Desenvolvido por Edsilas.

.DESCRIPTION
    Remove aplicativos e componentes não essenciais pré-instalados pela Microsoft
    e por OEMs, preservando integralmente os componentes críticos do sistema
    (Windows Update, Microsoft Store, Defender, Firewall, SmartScreen, runtimes,
    serviços de login/AAD/domínio, BitLocker, WinRE, etc.).

    Suporta dois modos:
      -DryRun   : simulação. Nada é removido. Apenas registra o que faria.
      -Execute  : execução real.

    Se nenhum modo for informado, o padrão é -DryRun (mais seguro).

.PARAMETER DryRun
    Executa em modo simulação (nenhuma alteração é feita).

.PARAMETER Execute
    Executa em modo real (remoções e políticas são aplicadas).

.PARAMETER RootDir
    Pasta raiz onde Logs/ e Recovery/ serão criados. Padrão: pasta do script.

.PARAMETER SkipRestorePoint
    Não tenta criar ponto de restauração (útil em ambientes onde está desativado).

.NOTES
    Autor   : Edsilas
    Licença : Apache License 2.0 (ver arquivo LICENSE)

    Compatível com Windows PowerShell 5.1 E PowerShell 7+ (pwsh):
      - No PowerShell 7, os módulos Appx e Dism são carregados via camada de
        compatibilidade (-UseWindowsPowerShell), pois dependem de APIs
        exclusivas do Windows PowerShell 5.1.
      - No Windows PowerShell 5.1, os módulos são importados nativamente e o
        ponto de restauração usa Checkpoint-Computer diretamente.
    O comportamento funcional é idêntico nos dois mecanismos.

    Execução totalmente local. Não acessa a internet. Não usa ferramentas de terceiros.
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Execute,
    [string]$RootDir = $PSScriptRoot,
    [switch]$SkipRestorePoint,
    [switch]$Aggressive
)

# ==========================================================================
# REGIÃO 0 - INICIALIZAÇÃO E ESTADO GLOBAL
# ==========================================================================
#region Init

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolução de modo. DryRun tem prioridade em caso de ambiguidade (segurança).
if (-not $DryRun -and -not $Execute) { $DryRun = $true }
if ($DryRun -and $Execute) { $Execute = $false }
$script:Mode      = if ($Execute) { 'EXECUTE' } else { 'DRYRUN' }
$script:IsDryRun  = -not $Execute

# Modo agressivo: amplia a otimização de serviços e aplica ajustes avançados.
# Vale tanto para simulação quanto para execução real.
$script:IsAggressive = [bool]$Aggressive

# Detecção do mecanismo PowerShell em uso.
#   'Core'    = PowerShell 7+ (pwsh)  -> Appx/Dism via camada de compatibilidade
#   'Desktop' = Windows PowerShell 5.1 -> Appx/Dism nativos; Checkpoint-Computer nativo
$script:IsCoreEdition = ($PSVersionTable.PSEdition -eq 'Core')

# Estrutura de pastas de saída
if ([string]::IsNullOrWhiteSpace($RootDir)) { $RootDir = (Get-Location).Path }
$script:RootDir     = $RootDir
$script:LogDir      = Join-Path $RootDir 'Logs'
$script:RecoveryDir = Join-Path $RootDir 'Recovery'

foreach ($d in @($script:LogDir, $script:RecoveryDir)) {
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

$script:Stamp        = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:DebloatLog   = Join-Path $script:LogDir 'Debloat.log'
$script:RemovedLog   = Join-Path $script:LogDir 'RemovedApps.log'
$script:ErrorLog     = Join-Path $script:LogDir 'Errors.log'

# Contadores para o relatório final
$script:Stats = [ordered]@{
    Removidos   = 0
    Simulados   = 0
    Protegidos  = 0
    Preservados = 0
    NaoEncontr  = 0
    Erros       = 0
    Politicas   = 0
    Servicos    = 0
}

# Preferências do usuário (preenchidas por Read-UserConfig, se Config.psd1 existir)
$script:PreserveApps     = @()
$script:PreserveServices = @()

#endregion

# ==========================================================================
# REGIÃO 1 - LOGGING
# ==========================================================================
#region Logging

function Write-Log {
    <#
        Registra uma linha em Debloat.log e no console, com nível e carimbo de tempo.
        Níveis: INFO, OK, WARN, ERROR, DRYRUN, STEP.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','DRYRUN','STEP')]
        [string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] [{1,-6}] {2}' -f $ts, $Level, $Message

    # Cor no console por nível
    $color = switch ($Level) {
        'OK'     { 'Green' }
        'WARN'   { 'Yellow' }
        'ERROR'  { 'Red' }
        'DRYRUN' { 'Cyan' }
        'STEP'   { 'Magenta' }
        default  { 'Gray' }
    }
    Write-Host $line -ForegroundColor $color

    # Sempre grava no log principal; nunca deixa o logging derrubar a execução.
    try { Add-Content -LiteralPath $script:DebloatLog -Value $line -Encoding UTF8 } catch { }

    if ($Level -eq 'ERROR') {
        try { Add-Content -LiteralPath $script:ErrorLog -Value $line -Encoding UTF8 } catch { }
        $script:Stats.Erros++
    }
}

function Write-PhaseProgress {
    <#
        Exibe a barra de progresso GERAL (fases do processo) via Write-Progress.
        Write-Progress é nativo do PS 5.1 e do PS 7, renderiza apenas no console
        e não interfere nos logs. Envolvido em try/catch: a barra é cosmética e
        jamais pode derrubar a execução (mesma filosofia do logging).
    #>
    param(
        [Parameter(Mandatory)][int]$Step,
        [Parameter(Mandatory)][int]$Total,
        [Parameter(Mandatory)][string]$Status
    )
    try {
        $pct = [int](($Step / $Total) * 100)
        Write-Progress -Id 0 -Activity ("WinDebloat [{0}]" -f $script:Mode) `
            -Status ("Fase {0} de {1}: {2}" -f $Step, $Total, $Status) `
            -PercentComplete $pct
    } catch { }
}

function Write-RemovedRecord {
    <#
        Registra em RemovedApps.log um item processado, com método e resultado.
    #>
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Result
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '[{0}] App="{1}" Metodo="{2}" Resultado="{3}"' -f $ts, $App, $Method, $Result
    try { Add-Content -LiteralPath $script:RemovedLog -Value $line -Encoding UTF8 } catch { }
}

#endregion

# ==========================================================================
# REGIÃO 2 - PRÉ-VOO: PRIVILÉGIOS E MÓDULOS
# ==========================================================================
#region Preflight

function Test-Administrator {
    <# Retorna $true se o processo atual estiver elevado. #>
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-NativeQuiet {
    <#
        Executa um comando nativo (reg.exe, reagentc.exe, ...) com
        $ErrorActionPreference temporariamente em 'Continue'.

        Motivo (compatibilidade PS 5.1): no Windows PowerShell 5.1, redirecionar
        o stderr de um executável (2>$null / 2>&1) com ErrorActionPreference =
        'Stop' converte qualquer linha de stderr em erro TERMINANTE
        (NativeCommandError), abortando o try em situações rotineiras — como
        'reg export' de uma chave inexistente. O PowerShell 7 não tem esse
        comportamento. Este wrapper garante semântica idêntica nos dois.
        $LASTEXITCODE permanece disponível após a chamada.
    #>
    param([Parameter(Mandatory)][scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command } finally { $ErrorActionPreference = $prev }
}

function Test-PendingReboot {
    <#
        Detecta reinicialização pendente por atualizações do Windows, pelas
        chaves oficiais de estado. Executar remoções nesse estado disputa o
        armazém de componentes com o Windows Update — a execução real aborta.
    #>
    foreach ($p in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        if (Test-Path -LiteralPath $p) { return $true }
    }
    return $false
}

function Read-UserConfig {
    <#
        Lê o arquivo OPCIONAL Config.psd1 (na mesma pasta do Core.ps1) com as
        preferências do usuário, via Import-PowerShellDataFile — nativo e
        seguro: avalia apenas dados, nunca executa código.

        Chaves aceitas:
          PreservarApps     = lista de nomes amigáveis de $TargetApps a NÃO remover
          PreservarServicos = lista de nomes de serviços de $ServiceTargets a NÃO ajustar

        Retorna $false se o arquivo existir e for inválido: nesse caso a
        execução aborta, porque prosseguir ignorando as preferências poderia
        remover exatamente o que o usuário pediu para manter.
    #>
    $cfgPath = Join-Path $PSScriptRoot 'Config.psd1'
    if (-not (Test-Path -LiteralPath $cfgPath)) {
        Write-Log 'Config.psd1 não encontrado; usando as listas padrão (arquivo opcional; veja Config.exemplo.psd1).' 'INFO'
        return $true
    }

    try {
        $cfg = Import-PowerShellDataFile -LiteralPath $cfgPath -ErrorAction Stop
    } catch {
        Write-Log "Config.psd1 inválido: $($_.Exception.Message)" 'ERROR'
        Write-Log 'Corrija ou renomeie o arquivo e execute novamente. Abortando para respeitar suas preferências.' 'ERROR'
        return $false
    }

    foreach ($k in @($cfg.Keys)) {
        if ($k -notin @('PreservarApps', 'PreservarServicos')) {
            Write-Log "Config.psd1: chave desconhecida ignorada: '$k'" 'WARN'
        }
    }
    if ($cfg.ContainsKey('PreservarApps')) {
        $script:PreserveApps = @(@($cfg['PreservarApps']) | Where-Object { $_ })
    }
    if ($cfg.ContainsKey('PreservarServicos')) {
        $script:PreserveServices = @(@($cfg['PreservarServicos']) | Where-Object { $_ })
    }

    if ($script:PreserveApps.Count -gt 0) {
        Write-Log ("Config.psd1: {0} app(s) a preservar: {1}" -f $script:PreserveApps.Count, ($script:PreserveApps -join ', ')) 'INFO'
        foreach ($p in $script:PreserveApps) {
            if (-not $script:TargetApps.Contains($p)) {
                Write-Log ("Config.psd1: '{0}' não corresponde a nenhum app da lista de alvos (verifique a grafia em Config.exemplo.psd1)." -f $p) 'WARN'
            }
        }
    }
    if ($script:PreserveServices.Count -gt 0) {
        Write-Log ("Config.psd1: {0} serviço(s) a preservar: {1}" -f $script:PreserveServices.Count, ($script:PreserveServices -join ', ')) 'INFO'
        foreach ($p in $script:PreserveServices) {
            if (-not $script:ServiceTargets.Contains($p)) {
                Write-Log ("Config.psd1: '{0}' não corresponde a nenhum serviço da lista de alvos." -f $p) 'WARN'
            }
        }
    }
    return $true
}

function Import-CompatModule {
    <#
        Importa um módulo dependente de APIs do Windows (Appx, Dism).
        - Windows PowerShell 5.1: importação nativa (sempre disponível).
        - PowerShell 7: tenta nativa e cai para a camada de compatibilidade
          WinPSCompatSession (-UseWindowsPowerShell), exclusiva do PS7.
    #>
    param([Parameter(Mandatory)][string]$Name)

    if (Get-Module -Name $Name) { return $true }

    # 1ª tentativa: importação nativa (padrão no 5.1; funciona em alguns builds do PS7).
    try {
        Import-Module -Name $Name -ErrorAction Stop -WarningAction SilentlyContinue
        Write-Log "Módulo '$Name' importado nativamente." 'INFO'
        return $true
    } catch { }

    # 2ª tentativa: camada de compatibilidade — parâmetro exclusivo do PS7.
    # No 5.1 esse parâmetro não existe; se a nativa falhou lá, não há fallback.
    if ($script:IsCoreEdition) {
        try {
            Import-Module -Name $Name -UseWindowsPowerShell -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Log "Módulo '$Name' importado via camada de compatibilidade." 'INFO'
            return $true
        } catch {
            Write-Log "Falha ao importar módulo '$Name': $($_.Exception.Message)" 'ERROR'
            return $false
        }
    }

    Write-Log "Falha ao importar módulo '$Name' no Windows PowerShell 5.1." 'ERROR'
    return $false
}

#endregion

# ==========================================================================
# REGIÃO 3 - INVENTÁRIO DO SISTEMA
# ==========================================================================
#region Inventory

function Get-SystemInventory {
    <#
        Coleta versão, build, edição, idioma e arquitetura do Windows.
        Aborta de forma controlada se não for Windows 10/11 x64.
    #>
    Write-Log 'Coletando inventário do sistema...' 'STEP'

    $os  = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs  = Get-CimInstance -ClassName Win32_ComputerSystem
    $cv  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $reg = Get-ItemProperty -Path $cv

    $build = [int]$reg.CurrentBuildNumber
    # Windows 11 = build >= 22000. Antes disso, Windows 10.
    $major = if ($build -ge 22000) { 11 } else { 10 }

    $inv = [pscustomobject]@{
        Produto      = $os.Caption
        VersaoMajor  = $major
        Build        = $build
        UBR          = $reg.UBR
        Edicao       = $reg.EditionID
        DisplayVer   = $reg.DisplayVersion
        Idioma       = (Get-WinSystemLocale).Name
        Arquitetura  = $os.OSArchitecture
        Dominio      = $cs.PartOfDomain
        DominioNome  = $cs.Domain
    }

    Write-Log ("SO........: {0} (Win{1}, build {2}.{3})" -f $inv.Produto, $inv.VersaoMajor, $inv.Build, $inv.UBR) 'INFO'
    Write-Log ("Edição....: {0}  Versão: {1}" -f $inv.Edicao, $inv.DisplayVer) 'INFO'
    Write-Log ("Idioma....: {0}  Arquitetura: {1}" -f $inv.Idioma, $inv.Arquitetura) 'INFO'
    Write-Log ("Domínio...: {0} {1}" -f $inv.Dominio, $inv.DominioNome) 'INFO'

    if ($inv.Arquitetura -notmatch '64') {
        throw "Arquitetura não suportada ($($inv.Arquitetura)). A ferramenta exige x64."
    }
    if ($inv.VersaoMajor -notin 10,11) {
        throw "Versão de Windows não suportada (build $build)."
    }

    return $inv
}

#endregion

# ==========================================================================
# REGIÃO 4 - LISTAS: ALVOS E PROTEÇÃO
# ==========================================================================
#region Lists

# Mapa: Nome amigável -> padrões de PackageFamily/Name (curinga permitido).
# A correspondência é restrita a esses padrões; nada é removido por dedução.
$script:TargetApps = [ordered]@{
    'Xbox App'                 = @('Microsoft.GamingApp')
    'Xbox Game Bar'            = @('Microsoft.XboxGamingOverlay','Microsoft.XboxGameOverlay')
    'Xbox Gaming Services'     = @('Microsoft.GamingServices')
    'Xbox Identity Provider'   = @('Microsoft.XboxIdentityProvider')
    'Xbox TCUI'                = @('Microsoft.Xbox.TCUI')
    'Xbox Speech To Text'      = @('Microsoft.XboxSpeechToTextOverlay')
    'Clipchamp'                = @('Clipchamp.Clipchamp')
    'Teams Consumer'           = @('MicrosoftTeams','MSTeams')
    'Skype'                    = @('Microsoft.SkypeApp')
    'Mixed Reality Portal'     = @('Microsoft.MixedReality.Portal')
    '3D Viewer'                = @('Microsoft.Microsoft3DViewer')
    'Paint 3D'                 = @('Microsoft.MSPaint')
    'Cortana'                  = @('Microsoft.549981C3F5F10')
    'Feedback Hub'             = @('Microsoft.WindowsFeedbackHub')
    'Get Help'                 = @('Microsoft.GetHelp')
    'Quick Assist'             = @('MicrosoftCorporationII.QuickAssist')
    'Windows Maps'             = @('Microsoft.WindowsMaps')
    'Bing News'                = @('Microsoft.BingNews')
    'Bing Weather'             = @('Microsoft.BingWeather')
    'Bing Sports'              = @('Microsoft.BingSports')
    'Bing Finance'             = @('Microsoft.BingFinance')
    'People'                   = @('Microsoft.People')
    'Phone Link / Your Phone'  = @('Microsoft.YourPhone')
    'Solitaire'                = @('Microsoft.MicrosoftSolitaireCollection')
    'To Do'                    = @('Microsoft.Todos')
    'Office Hub'               = @('Microsoft.MicrosoftOfficeHub')
    'OneConnect'               = @('Microsoft.OneConnect')
    'Family'                   = @('MicrosoftCorporationII.MicrosoftFamily')
    'Alarms'                   = @('Microsoft.WindowsAlarms')
    'Sound Recorder'           = @('Microsoft.WindowsSoundRecorder')
    'Camera'                   = @('Microsoft.WindowsCamera')
    'Movies & TV'              = @('Microsoft.ZuneVideo')
    'Zune Music (Groove)'      = @('Microsoft.ZuneMusic')
    'Dev Home'                 = @('Microsoft.Windows.DevHome')
    'Power Automate'           = @('Microsoft.PowerAutomateDesktop')
}

# Lista de PROTEÇÃO (regex). Qualquer pacote cujo nome casar aqui é
# IGNORADO mesmo que apareça acidentalmente em outra lista. É a última
# linha de defesa contra remoções perigosas.
$script:ProtectedRegex = @(
    'WindowsStore'                 # Microsoft Store
    'StorePurchaseApp'
    'DesktopAppInstaller'          # winget / instalador de apps
    'WindowsTerminal'
    'VCLibs'                       # Runtime C++
    'NET\.Native'                  # .NET Native
    'UI\.Xaml'                     # WinUI / XAML runtime
    'SecHealthUI'                  # Central de Segurança / Defender (UI)
    'Apprep\.ChxApp'               # SmartScreen
    'AAD\.BrokerPlugin'            # Login Azure AD
    'AccountsControl'              # Login de contas
    'CredDialogHost'
    'LockApp'
    'ShellExperienceHost'          # Shell
    'StartMenuExperienceHost'      # Menu Iniciar
    'Client\.CBS'                  # Componentes de shell do Win11
    'Client\.Core'
    'CloudExperienceHost'          # OOBE / configuração
    'AssignedAccessLockApp'
    'BioEnrollment'                # Windows Hello
    'Win32WebViewHost'
    'WebExperience'                # Widgets host base (cuidado)
    'XGpuEjectDialog'
    'AsyncTextService'             # Entrada de texto
    'InputApp'
    'ParentalControls'
    'PeopleExperienceHost'
    'PinningConfirmationDialog'
    'CapturePicker'
    'NarratorQuickStart'           # Acessibilidade
    'ECApp'
    'Search'                       # SearchHost / Cortana base de busca
    'Microsoft\.WindowsAppRuntime' # Windows App SDK
    'Microsoft\.Windows\.Photos'   # Fotos (não está na lista de remoção)
    'Microsoft\.WindowsNotepad'
    'Microsoft\.Paint$'            # Paint 2D (preservar; remover apenas Paint 3D)
)

function Test-IsProtected {
    <# $true se o nome do pacote casar com a lista de proteção. #>
    param([Parameter(Mandatory)][string]$PackageName)
    foreach ($rx in $script:ProtectedRegex) {
        if ($PackageName -match $rx) { return $true }
    }
    return $false
}

#endregion

# ==========================================================================
# REGIÃO 4B - SERVIÇOS: ANÁLISE, OTIMIZAÇÃO E MODO AGRESSIVO
# ==========================================================================
#region Services

<#
    Filosofia (a mesma dos aplicativos):
    - Curadoria explícita: só entram na lista serviços com ganho conhecido e
      risco baixo. Nada é ajustado "por dedução".
    - Guarda de proteção: mesmo que um serviço essencial entrasse por engano
      na lista, o filtro regex abaixo o barra.
    - Preferência por 'Manual' (inicia sob demanda) em vez de 'Disabled':
      preserva compatibilidade — se algo precisar do serviço, ele sobe sozinho.
      'Disabled' é reservado a casos sem efeito colateral conhecido.
    - Reversão tripla: ponto de restauração + estado anterior registrado no log
      + script pronto de restauração gerado em Recovery\.
#>

# Alvos de otimização. 'Start' = modo padrão ($null = não tocar no padrão);
# 'Aggressive' = modo agressivo. Ambos respeitam Dry Run e a guarda abaixo.
$script:ServiceTargets = [ordered]@{
    'DiagTrack'        = @{ Start = 'Manual';   Aggressive = 'Disabled'; Motivo = 'Telemetria (Experiências do Usuário Conectado)' }
    'dmwappushservice' = @{ Start = 'Manual';   Aggressive = 'Manual';   Motivo = 'Roteamento de mensagens WAP Push' }
    'MapsBroker'       = @{ Start = 'Manual';   Aggressive = 'Manual';   Motivo = 'Gerenciador de mapas baixados (app Mapas removido)' }
    'Fax'              = @{ Start = 'Manual';   Aggressive = 'Disabled'; Motivo = 'Serviço de fax' }
    'RetailDemo'       = @{ Start = 'Disabled'; Aggressive = 'Disabled'; Motivo = 'Modo de demonstração de loja' }
    'WMPNetworkSvc'    = @{ Start = 'Manual';   Aggressive = 'Manual';   Motivo = 'Compartilhamento de rede do Windows Media Player' }
    'RemoteRegistry'   = @{ Start = 'Disabled'; Aggressive = 'Disabled'; Motivo = 'Registro remoto (endurecimento de segurança)' }
    'XblAuthManager'   = @{ Start = 'Manual';   Aggressive = 'Manual';   Motivo = 'Autenticação Xbox Live (apps Xbox removidos)' }
    'XblGameSave'      = @{ Start = 'Manual';   Aggressive = 'Manual';   Motivo = 'Salvamento de jogos Xbox Live' }
    'XboxNetApiSvc'    = @{ Start = 'Manual';   Aggressive = 'Manual';   Motivo = 'Rede Xbox Live' }
    # --- Exclusivos do modo agressivo (Start = $null) ---
    'SysMain'          = @{ Start = $null; Aggressive = 'Manual'; Motivo = 'Pré-carregamento de apps (Superfetch); dispensável em SSD' }
    'WerSvc'           = @{ Start = $null; Aggressive = 'Manual'; Motivo = 'Relatório de Erros do Windows' }
    'lfsvc'            = @{ Start = $null; Aggressive = 'Manual'; Motivo = 'Serviço de geolocalização' }
    'TrkWks'           = @{ Start = $null; Aggressive = 'Manual'; Motivo = 'Rastreamento de links distribuídos' }
    'WalletService'    = @{ Start = $null; Aggressive = 'Manual'; Motivo = 'Serviço de carteira (Wallet)' }
}

# Guarda de proteção: serviços que JAMAIS são tocados, mesmo se listados acima
# por engano. Cobre atualização, segurança, rede, áudio, shell, licenciamento,
# busca, impressão, Bluetooth, energia, perfis e infraestrutura RPC/COM.
$script:ProtectedServicesRegex = @(
    '^wuauserv$','^UsoSvc$','^BITS$','^DoSvc$','^WaaSMedicSvc$','^TrustedInstaller$','^msiserver$',
    '^WinDefend$','^WdNisSvc$','^Sense$','^SecurityHealthService$','^wscsvc$','^MpsSvc$','^BFE$',
    '^Dnscache$','^Dhcp$','^NlaSvc$','^netprofm$','^LanmanWorkstation$','^LanmanServer$','^Wcmsvc$','^WlanSvc$','^WwanSvc$',
    '^RpcSs$','^RpcEptMapper$','^DcomLaunch$','^BrokerInfrastructure$','^CoreMessagingRegistrar$','^SystemEventsBroker$',
    '^Audiosrv$','^AudioEndpointBuilder$','^CryptSvc$','^EventLog$','^Schedule$','^Themes$','^ProfSvc$','^UserManager$',
    '^Winmgmt$','^Power$','^PlugPlay$','^Spooler$','^StateRepository$','^AppXSvc$','^ClipSVC$','^LicenseManager$',
    '^WSearch$','^VSS$','^swprv$','^sppsvc$','^W32Time$','^KeyIso$','^SamSs$','^LSM$','^SENS$','^ShellHWDetection$',
    '^bthserv$','^BTAGService$','^CDPSvc$','^TokenBroker$','^VaultSvc$','^WbioSrvc$','^camsvc$','^XboxGipSvc$'
) -join '|'

function Invoke-SystemAnalysis {
    <#
        Análise SOMENTE LEITURA do estado do sistema: serviços, processos e
        programas de inicialização. Nada é alterado aqui, em nenhum modo.
        Um resumo vai para o log e o relatório completo para Logs\Analise_*.txt.
    #>
    Write-Log '=== FASE: ANÁLISE DO SISTEMA (somente leitura) ===' 'STEP'
    $report = New-Object System.Collections.Generic.List[string]

    try {
        $svcs    = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
        $running = @($svcs | Where-Object { $_.State -eq 'Running' })
        $auto    = @($svcs | Where-Object { $_.StartMode -eq 'Auto' })
        Write-Log ("Serviços: {0} instalados, {1} em execução, {2} com início automático." -f $svcs.Count, $running.Count, $auto.Count) 'INFO'
        $report.Add('===== SERVIÇOS (nome, estado, tipo de início) =====')
        foreach ($s in ($svcs | Sort-Object State, Name)) {
            $report.Add(("{0,-42} {1,-9} {2}" -f $s.Name, $s.State, $s.StartMode))
        }
    } catch { Write-Log "Análise de serviços indisponível: $($_.Exception.Message)" 'WARN' }

    try {
        $procs = @(Get-Process -ErrorAction Stop | Sort-Object WorkingSet64 -Descending)
        Write-Log ("Processos em execução: {0}. Os dez maiores consumidores de memória estão no relatório." -f $procs.Count) 'INFO'
        $report.Add(''); $report.Add('===== 10 PROCESSOS COM MAIOR USO DE MEMÓRIA =====')
        foreach ($p in ($procs | Select-Object -First 10)) {
            $report.Add(("{0,-38} {1,10:N0} MB" -f $p.ProcessName, ($p.WorkingSet64 / 1MB)))
        }
    } catch { Write-Log "Análise de processos indisponível: $($_.Exception.Message)" 'WARN' }

    try {
        $report.Add(''); $report.Add('===== PROGRAMAS DE INICIALIZAÇÃO (informativo; NÃO são alterados) =====')
        $startupCount = 0
        foreach ($rk in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                          'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')) {
            if (-not (Test-Path -LiteralPath $rk)) { continue }
            $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($pp in $props.PSObject.Properties) {
                if ($pp.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$') {
                    $report.Add(("[{0}] {1} = {2}" -f $rk, $pp.Name, $pp.Value))
                    $startupCount++
                }
            }
        }
        Write-Log ("Programas de inicialização detectados: {0} (informativo; a ferramenta não os altera por serem escolhas pessoais)." -f $startupCount) 'INFO'
    } catch { Write-Log "Análise de inicialização indisponível: $($_.Exception.Message)" 'WARN' }

    try {
        $dst = Join-Path $script:LogDir ("Analise_Sistema_{0}.txt" -f $script:Stamp)
        $report | Set-Content -LiteralPath $dst -Encoding UTF8
        Write-Log "Relatório completo da análise salvo em: $dst" 'OK'
    } catch { Write-Log "Não foi possível salvar o relatório de análise: $($_.Exception.Message)" 'WARN' }
}

function Invoke-ServiceOptimization {
    <#
        Ajusta o tipo de início dos serviços da lista curada, respeitando
        Dry Run e a guarda de proteção. Antes de qualquer alteração real,
        gera em Recovery\ um script de restauração com o estado anterior
        exato de cada serviço (incluindo início automático atrasado).
    #>
    $modeTxt = if ($script:IsAggressive) { 'MODO AGRESSIVO' } else { 'modo padrão' }
    Write-Log ("=== FASE: OTIMIZAÇÃO DE SERVIÇOS ({0}) ===" -f $modeTxt) 'STEP'

    $restoreLines = New-Object System.Collections.Generic.List[string]
    $restoreLines.Add('# Restauração dos serviços ajustados pelo WinDebloat (execução ' + $script:Stamp + ')')
    $restoreLines.Add('# Como usar: clique com o botão direito neste arquivo > Executar com o PowerShell.')
    $restoreLines.Add('# O script solicita elevação (UAC) sozinho e mostra o resultado de cada serviço.')
    $restoreLines.Add('#requires -Version 5.1')
    $restoreLines.Add('$id = [Security.Principal.WindowsIdentity]::GetCurrent()')
    $restoreLines.Add('$pr = New-Object Security.Principal.WindowsPrincipal($id)')
    $restoreLines.Add('if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {')
    $restoreLines.Add('    Start-Process powershell.exe -Verb RunAs -ArgumentList (''-NoProfile -ExecutionPolicy Bypass -File "{0}"'' -f $MyInvocation.MyCommand.Path)')
    $restoreLines.Add('    exit')
    $restoreLines.Add('}')

    foreach ($entry in $script:ServiceTargets.GetEnumerator()) {
        $name    = $entry.Key
        $desired = if ($script:IsAggressive) { $entry.Value.Aggressive } else { $entry.Value.Start }
        if (-not $desired) { continue }  # alvo exclusivo do modo agressivo

        # Preferência do usuário (Config.psd1): não tocar neste serviço.
        if ($script:PreserveServices.Count -gt 0 -and ($script:PreserveServices -contains $name)) {
            Write-Log ("PRESERVADO (Config.psd1): serviço {0}" -f $name) 'INFO'
            $script:Stats.Preservados++
            continue
        }

        if ($name -match $script:ProtectedServicesRegex) {
            Write-Log "PROTEGIDO (serviço essencial; ignorado): $name" 'WARN'
            $script:Stats.Protegidos++
            continue
        }

        $svc = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $name) -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Log "Serviço não existe neste sistema: $name" 'INFO'
            continue
        }

        # Estado atual + flag de início automático atrasado (para restauração fiel).
        $curMode = $svc.StartMode
        $delayed = $false
        try {
            $rp = Get-ItemProperty -LiteralPath ("HKLM:\SYSTEM\CurrentControlSet\Services\{0}" -f $name) -ErrorAction SilentlyContinue
            if ($rp -and $rp.PSObject.Properties['DelayedAutostart']) { $delayed = ($rp.DelayedAutostart -eq 1) }
        } catch { }
        $scStart = switch ($curMode) {
            'Auto'     { if ($delayed) { 'delayed-auto' } else { 'auto' } }
            'Manual'   { 'demand' }
            'Disabled' { 'disabled' }
            default    { 'demand' }
        }
        $restoreLines.Add(("sc.exe config `"{0}`" start= {1} | Out-Null; Write-Host 'Restaurado: {0} -> {1}'" -f $name, $scStart))

        if ($curMode -eq $desired) {
            Write-Log ("Já no estado desejado: {0} (início: {1})" -f $name, $curMode) 'INFO'
            continue
        }

        if ($script:IsDryRun) {
            Write-Log ("[SIMULAÇÃO] Serviço {0}: início {1} -> {2} ({3})" -f $name, $curMode, $desired, $entry.Value.Motivo) 'DRYRUN'
            $script:Stats.Servicos++
            continue
        }

        try {
            Set-Service -Name $name -StartupType $desired -ErrorAction Stop
            if ($desired -eq 'Disabled' -and $svc.State -eq 'Running') {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            }
            Write-Log ("Serviço ajustado: {0} (início: {1} -> {2}) - {3}" -f $name, $curMode, $desired, $entry.Value.Motivo) 'OK'
            $script:Stats.Servicos++
        } catch {
            Write-Log ("Falha ao ajustar serviço {0}: {1}" -f $name, $_.Exception.Message) 'ERROR'
        }
    }

    if (-not $script:IsDryRun) {
        try {
            $restoreLines.Add('Write-Host ""; Write-Host "Restauração concluída." -ForegroundColor Green')
            $restoreLines.Add('Read-Host "Pressione Enter para fechar"')
            $restorePath = Join-Path $script:RecoveryDir ("Restaurar_Servicos_{0}.ps1" -f $script:Stamp)
            $restoreLines | Set-Content -LiteralPath $restorePath -Encoding UTF8
            Write-Log "Script de restauração de serviços salvo em: $restorePath" 'OK'
        } catch {
            Write-Log "Não foi possível salvar o script de restauração: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Set-AggressiveTweaks {
    <#
        Ajustes avançados de registro, aplicados APENAS no modo agressivo.
        Todos reversíveis pelos arquivos .reg exportados em Recovery\ e pelo
        ponto de restauração. Respeitam Dry Run via Set-RegValue.
    #>
    if (-not $script:IsAggressive) { return }
    Write-Log '=== FASE: AJUSTES AVANÇADOS (MODO AGRESSIVO) ===' 'STEP'

    # Telemetria no nível mínimo suportado pela edição (1 = Básico/Obrigatório;
    # 0 só tem efeito em Enterprise/Education — usar 1 evita falsa sensação).
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 1

    # Game DVR / captura em segundo plano: consome CPU e GPU continuamente,
    # mesmo sem uso. A Game Bar já foi removida na fase de aplicativos.
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
    Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0

    Write-Log 'Ajustes avançados concluídos (reversíveis via Recovery\ e ponto de restauração).' 'INFO'
}

#endregion

# ==========================================================================
# REGIÃO 5 - RECUPERAÇÃO (RESTORE POINT + EXPORT DE REGISTRO)
# ==========================================================================
#region Recovery

function New-RecoveryArtifacts {
    <#
        Cria, quando suportado:
          - Ponto de restauração do sistema;
          - Exportação das chaves de registro que serão alteradas;
          - Inventário inicial de apps (baseline) para auditoria.
    #>
    Write-Log 'Preparando artefatos de recuperação...' 'STEP'

    # --- Baseline de apps instalados (sempre, mesmo em DryRun) ---
    try {
        $baseline = Join-Path $script:RecoveryDir ("Appx_Baseline_{0}.txt" -f $script:Stamp)
        Get-AppxPackage -AllUsers |
            Select-Object Name, PackageFullName, Version |
            Sort-Object Name |
            Format-Table -AutoSize | Out-String |
            Set-Content -LiteralPath $baseline -Encoding UTF8
        Write-Log "Baseline de apps salvo em: $baseline" 'OK'
    } catch {
        Write-Log "Não foi possível salvar baseline de apps: $($_.Exception.Message)" 'WARN'
    }

    # --- Exportação das chaves de registro tocadas ---
    $keysToExport = @(
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer'
        # Chaves tocadas pelos ajustes avançados (modo agressivo). Exportar
        # sempre é inofensivo: chave inexistente é simplesmente ignorada.
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
        'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
        'HKCU\System\GameConfigStore'
        'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    )
    foreach ($k in $keysToExport) {
        $safe = ($k -replace '[\\:]', '_')
        $dst  = Join-Path $script:RecoveryDir ("Reg_{0}_{1}.reg" -f $safe, $script:Stamp)
        try {
            # reg export falha silenciosamente se a chave não existir; tudo bem.
            # Invoke-NativeQuiet: no PS 5.1, stderr redirecionado + EAP 'Stop'
            # viraria erro terminante (ver função). No PS7 é neutro.
            $null = Invoke-NativeQuiet { & reg.exe export $k $dst /y 2>$null }
            if (Test-Path -LiteralPath $dst) {
                Write-Log "Registro exportado: $k" 'OK'
            }
        } catch {
            Write-Log "Falha ao exportar $k : $($_.Exception.Message)" 'WARN'
        }
    }

    # --- Ponto de restauração ---
    if ($SkipRestorePoint) {
        Write-Log 'Ponto de restauração ignorado (-SkipRestorePoint).' 'WARN'
        return
    }
    if ($script:IsDryRun) {
        Write-Log '[SIMULAÇÃO] Criaria um ponto de restauração do sistema.' 'DRYRUN'
        return
    }

    # Remove o limite de 1 ponto a cada 24h APENAS durante esta criação.
    # O valor original é capturado e restaurado no finally (correção: antes
    # a alteração ficava permanente no sistema).
    $sr       = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqName = 'SystemRestorePointCreationFrequency'
    $prevFreq = $null
    $freqSet  = $false

    try {
        if (-not (Test-Path $sr)) { New-Item -Path $sr -Force | Out-Null }
        # Leitura segura sob StrictMode (correção para PS 5.1): acessar uma
        # propriedade inexistente do resultado lança PropertyNotFoundException
        # no Windows PowerShell 5.1. Verificamos a existência via PSObject antes.
        $srProps = Get-ItemProperty -Path $sr -ErrorAction SilentlyContinue
        if ($srProps -and $srProps.PSObject.Properties[$freqName]) {
            $prevFreq = $srProps.$freqName
        }
        New-ItemProperty -Path $sr -Name $freqName -Value 0 -PropertyType DWord -Force | Out-Null
        $freqSet = $true

        if (-not $script:IsCoreEdition) {
            # --- Windows PowerShell 5.1: cmdlets nativos, sem delegação. ---
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "WinDebloat $script:Stamp" `
                -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            Write-Log 'Ponto de restauração criado (nativo 5.1).' 'OK'
        } else {
            # --- PowerShell 7: Checkpoint-Computer / Enable-ComputerRestore NÃO
            # existem no PS7. Delegamos ao Windows PowerShell 5.1 (componente
            # nativo do Windows 10/11), com fallback via CIM. ---
            $winPs = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

            if (Test-Path -LiteralPath $winPs) {
                $cmd = @"
Enable-ComputerRestore -Drive '$env:SystemDrive\' -ErrorAction SilentlyContinue
Checkpoint-Computer -Description 'WinDebloat $script:Stamp' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
"@
                $out = & $winPs -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log 'Ponto de restauração criado com sucesso.' 'OK'
                } else {
                    Write-Log "Ponto de restauração não criado (saída 5.1: $out)." 'WARN'
                }
            } else {
                # Fallback nativo via CIM (exige System Restore já habilitado).
                $res = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' `
                        -MethodName 'CreateRestorePoint' -Arguments @{
                            Description      = "WinDebloat $script:Stamp"
                            RestorePointType = [uint32]12   # MODIFY_SETTINGS
                            EventType        = [uint32]100  # BEGIN_SYSTEM_CHANGE
                        } -ErrorAction Stop
                if ($res.ReturnValue -eq 0) { Write-Log 'Ponto de restauração criado (CIM).' 'OK' }
                else { Write-Log "CreateRestorePoint retornou $($res.ReturnValue)." 'WARN' }
            }
        }
    } catch {
        Write-Log "Não foi possível criar ponto de restauração: $($_.Exception.Message)" 'WARN'
        Write-Log 'Prosseguindo (a exportação de registro e o baseline continuam válidos).' 'WARN'
    } finally {
        # Devolve o registro ao estado anterior: restaura o valor original
        # ou remove a chave se ela não existia antes.
        if ($freqSet) {
            try {
                if ($null -ne $prevFreq) {
                    Set-ItemProperty -Path $sr -Name $freqName -Value $prevFreq -Force
                } else {
                    Remove-ItemProperty -Path $sr -Name $freqName -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Log "Não foi possível restaurar '$freqName': $($_.Exception.Message)" 'WARN'
            }
        }
    }
}

#endregion

# ==========================================================================
# REGIÃO 6 - REMOÇÃO DE APLICATIVOS
# ==========================================================================
#region Removal

function Remove-TargetApp {
    <#
        Processa UM aplicativo alvo:
          1) Resolve os pacotes instalados (todos os usuários) que casam com os padrões;
          2) Aplica o guarda de proteção a cada pacote;
          3) Remove para todos os usuários (Remove-AppxPackage -AllUsers);
          4) Remove o provisioned package (afeta novos usuários futuros).
        Respeita o modo DryRun.
    #>
    param(
        [Parameter(Mandatory)][string]$FriendlyName,
        [Parameter(Mandatory)][string[]]$Patterns
    )

    Write-Log "Processando: $FriendlyName" 'STEP'
    $foundAny = $false

    # ---- 6.1 Pacotes instalados (perfis atuais) ----
    foreach ($pat in $Patterns) {
        # Filtro em memória sobre o cache montado em Invoke-AppRemoval:
        # mesma semântica de -Name (curinga via -like), sem custo de chamada.
        $pkgs = @($script:PkgCache | Where-Object { $_.Name -like $pat })

        foreach ($pkg in $pkgs) {
            $foundAny = $true

            if (Test-IsProtected -PackageName $pkg.Name) {
                Write-Log "PROTEGIDO, ignorado: $($pkg.Name)" 'WARN'
                Write-RemovedRecord -App $pkg.Name -Method 'Get-AppxPackage' -Result 'PROTEGIDO/IGNORADO'
                $script:Stats.Protegidos++
                continue
            }

            if ($script:IsDryRun) {
                Write-Log "[SIMULAÇÃO] Removeria (todos os usuários): $($pkg.PackageFullName)" 'DRYRUN'
                Write-RemovedRecord -App $pkg.Name -Method 'Remove-AppxPackage -AllUsers' -Result 'SIMULADO'
                $script:Stats.Simulados++
                continue
            }

            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Write-Log "Removido (todos os usuários): $($pkg.Name)" 'OK'
                Write-RemovedRecord -App $pkg.Name -Method 'Remove-AppxPackage -AllUsers' -Result 'REMOVIDO'
                $script:Stats.Removidos++
            } catch {
                $allUsersErr = $_.Exception.Message
                # Fallback (comum no Windows 10): pacotes em estado "staged"
                # falham na remoção -AllUsers com 0x80070002 ("arquivo não
                # encontrado"), embora estejam instalados para o usuário atual.
                # Nesse caso, removemos a instalação do usuário atual — que é a
                # visível no Menu Iniciar — e o provisioned (etapa seguinte)
                # cobre os usuários futuros.
                $fallbackOk = $false
                $curFound   = $false
                try {
                    $cur = Get-AppxPackage -Name $pkg.Name -ErrorAction SilentlyContinue
                    if ($cur) {
                        $curFound = $true
                        $cur | Remove-AppxPackage -ErrorAction Stop
                        Write-Log "Removido (usuário atual; -AllUsers indisponível neste build): $($pkg.Name)" 'OK'
                        Write-RemovedRecord -App $pkg.Name -Method 'Remove-AppxPackage (usuário atual)' -Result 'REMOVIDO'
                        $script:Stats.Removidos++
                        $fallbackOk = $true
                    }
                } catch { }

                if (-not $fallbackOk) {
                    if (-not $curFound) {
                        # -AllUsers falhou E o app não existe para o usuário atual:
                        # o pacote pertence a outro perfil deste computador (ou é
                        # um registro "staged" órfão). O Windows não permite
                        # removê-lo a partir desta conta — não é uma falha real
                        # da ferramenta, portanto registramos como aviso.
                        Write-Log "Não removido: $($pkg.Name) está instalado apenas em outro perfil de usuário deste computador. Para removê-lo, execute a ferramenta conectado na conta desse usuário." 'WARN'
                        Write-RemovedRecord -App $pkg.Name -Method 'Remove-AppxPackage -AllUsers' -Result "NAO REMOVIDO (outro perfil de usuário): $allUsersErr"
                    } else {
                        Write-Log "Falha ao remover $($pkg.Name): $allUsersErr" 'ERROR'
                        Write-RemovedRecord -App $pkg.Name -Method 'Remove-AppxPackage -AllUsers' -Result "ERRO: $allUsersErr"
                    }
                }
            }
        }
    }

    # ---- 6.2 Provisioned packages (novos usuários futuros) ----
    foreach ($pat in $Patterns) {
        $prov = @($script:ProvCache | Where-Object { $_.DisplayName -like $pat })

        foreach ($pp in $prov) {
            $foundAny = $true

            if (Test-IsProtected -PackageName $pp.DisplayName) {
                Write-Log "PROTEGIDO (provisioned), ignorado: $($pp.DisplayName)" 'WARN'
                $script:Stats.Protegidos++
                continue
            }

            if ($script:IsDryRun) {
                Write-Log "[SIMULAÇÃO] Removeria provisioned: $($pp.DisplayName)" 'DRYRUN'
                Write-RemovedRecord -App $pp.DisplayName -Method 'Remove-AppxProvisionedPackage' -Result 'SIMULADO'
                $script:Stats.Simulados++
                continue
            }

            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                Write-Log "Provisioned removido: $($pp.DisplayName)" 'OK'
                Write-RemovedRecord -App $pp.DisplayName -Method 'Remove-AppxProvisionedPackage' -Result 'REMOVIDO'
                $script:Stats.Removidos++
            } catch {
                Write-Log "Falha ao remover provisioned $($pp.DisplayName): $($_.Exception.Message)" 'ERROR'
                Write-RemovedRecord -App $pp.DisplayName -Method 'Remove-AppxProvisionedPackage' -Result "ERRO: $($_.Exception.Message)"
            }
        }
    }

    if (-not $foundAny) {
        Write-Log "Não encontrado neste sistema: $FriendlyName" 'INFO'
        $script:Stats.NaoEncontr++
    }
}

function Invoke-AppRemoval {
    <# Itera todo o mapa de alvos, com barra de progresso por aplicativo. #>
    Write-Log '=== FASE: REMOÇÃO DE APLICATIVOS ===' 'STEP'

    # --- Cache de inventário (desempenho) ---
    # Uma única consulta a cada fonte substitui ~50 chamadas (uma por padrão).
    # No PowerShell 7, cada chamada atravessa a camada de compatibilidade
    # (remoting), tornando este cache a maior otimização de tempo da fase.
    # O fallback por usuário atual continua consultando ao vivo, pois precisa
    # do estado real no momento da falha.
    $script:PkgCache  = @()
    $script:ProvCache = @()
    try {
        $script:PkgCache = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
        Write-Log ("Inventário em cache: {0} pacotes instalados (todos os usuários)." -f $script:PkgCache.Count) 'INFO'
    } catch {
        Write-Log "Falha ao montar cache de pacotes instalados: $($_.Exception.Message)" 'ERROR'
    }
    try {
        $script:ProvCache = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
        Write-Log ("Inventário em cache: {0} pacotes provisionados." -f $script:ProvCache.Count) 'INFO'
    } catch {
        Write-Log "Provisioned packages indisponíveis nesta execução: $($_.Exception.Message)" 'WARN'
    }

    $total = $script:TargetApps.Count
    $i = 0
    foreach ($entry in $script:TargetApps.GetEnumerator()) {
        $i++
        # Barra secundária (aninhada à geral). Cosmética: nunca derruba a execução.
        try {
            Write-Progress -Id 1 -ParentId 0 -Activity 'Removendo aplicativos' `
                -Status ("({0}/{1}) {2}" -f $i, $total, $entry.Key) `
                -PercentComplete ([int](($i / $total) * 100))
        } catch { }

        # Preferência do usuário (Config.psd1): pula o app inteiro.
        if ($script:PreserveApps.Count -gt 0 -and ($script:PreserveApps -contains $entry.Key)) {
            Write-Log ("PRESERVADO (Config.psd1): {0}" -f $entry.Key) 'INFO'
            $script:Stats.Preservados++
            continue
        }

        Remove-TargetApp -FriendlyName $entry.Key -Patterns $entry.Value
    }
    try { Write-Progress -Id 1 -ParentId 0 -Activity 'Removendo aplicativos' -Completed } catch { }
}

#endregion

# ==========================================================================
# REGIÃO 7 - POLÍTICAS ANTI-REINSTALAÇÃO
# ==========================================================================
#region Policies

function Set-RegValue {
    <#
        Define um valor de registro criando o caminho se necessário.
        Respeita DryRun. Conta políticas aplicadas.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord','String','QWord')][string]$Type = 'DWord'
    )

    if ($script:IsDryRun) {
        Write-Log "[SIMULAÇÃO] Definir $Path\$Name = $Value ($Type)" 'DRYRUN'
        $script:Stats.Politicas++
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        Write-Log "Política aplicada: $Path\$Name = $Value" 'OK'
        $script:Stats.Politicas++
    } catch {
        Write-Log "Falha ao aplicar política $Path\$Name : $($_.Exception.Message)" 'ERROR'
    }
}

function Set-AntiReinstallPolicy {
    <#
        Aplica políticas suportadas pela Microsoft para impedir a reinstalação
        silenciosa de apps promocionais, sugeridos, patrocinados e OEM.
        Atua em HKLM (máquina) e HKCU (usuário atual). Para novos usuários,
        ver Set-DefaultUserPolicy.
    #>
    Write-Log '=== FASE: POLÍTICAS ANTI-REINSTALAÇÃO ===' 'STEP'

    # --- CloudContent (GPO de máquina) ---
    $cloud = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    Set-RegValue -Path $cloud -Name 'DisableWindowsConsumerFeatures'    -Value 1
    Set-RegValue -Path $cloud -Name 'DisableConsumerAccountStateContent' -Value 1
    Set-RegValue -Path $cloud -Name 'DisableCloudOptimizedContent'       -Value 1
    Set-RegValue -Path $cloud -Name 'DisableSoftLanding'                 -Value 1

    # --- ContentDeliveryManager (usuário atual) ---
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $cdmValues = @{
        'SilentInstalledAppsEnabled'        = 0   # instalação silenciosa de apps
        'ContentDeliveryAllowed'            = 0
        'OemPreInstalledAppsEnabled'        = 0   # bloatware OEM
        'PreInstalledAppsEnabled'           = 0
        'PreInstalledAppsEverEnabled'       = 0
        'SubscribedContentEnabled'          = 0
        'SystemPaneSuggestionsEnabled'      = 0   # apps sugeridos
        'SoftLandingEnabled'                = 0
        'RotatingLockScreenOverlayEnabled'  = 0
        'SubscribedContent-338387Enabled'   = 0
        'SubscribedContent-338388Enabled'   = 0   # sugestões no Iniciar
        'SubscribedContent-338389Enabled'   = 0
        'SubscribedContent-353698Enabled'   = 0
        'FeatureManagementEnabled'          = 0
    }
    foreach ($kv in $cdmValues.GetEnumerator()) {
        Set-RegValue -Path $cdm -Name $kv.Key -Value $kv.Value
    }

    # --- Desabilitar instalação automática de apps "sugeridos" (HKLM) ---
    $explorerPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    Set-RegValue -Path $explorerPol -Name 'DisableSearchBoxSuggestions' -Value 1
}

function Set-DefaultUserPolicy {
    <#
        Aplica as chaves de ContentDeliveryManager ao perfil DEFAULT,
        de modo que NOVOS usuários criados no futuro já nasçam sem bloatware.
        Carrega temporariamente C:\Users\Default\NTUSER.DAT.
    #>
    Write-Log 'Aplicando políticas ao perfil padrão (novos usuários)...' 'STEP'

    $defaultHive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
    if (-not (Test-Path -LiteralPath $defaultHive)) {
        Write-Log "Hive padrão não encontrado em $defaultHive. Pulando." 'WARN'
        return
    }

    if ($script:IsDryRun) {
        Write-Log '[SIMULAÇÃO] Carregaria NTUSER.DAT padrão e aplicaria ContentDeliveryManager.' 'DRYRUN'
        return
    }

    $mount = 'HKLM\WinDebloatDefault'
    try {
        $null = Invoke-NativeQuiet { & reg.exe load $mount $defaultHive 2>$null }
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe load retornou código $LASTEXITCODE (hive em uso ou sem permissão)."
        }
        $base = "Registry::$mount\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (-not (Test-Path -LiteralPath $base)) { New-Item -Path $base -Force | Out-Null }
        foreach ($name in 'SilentInstalledAppsEnabled','OemPreInstalledAppsEnabled','PreInstalledAppsEnabled','SubscribedContentEnabled','SystemPaneSuggestionsEnabled') {
            New-ItemProperty -LiteralPath $base -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
        }
        Write-Log 'Políticas aplicadas ao perfil padrão.' 'OK'
    } catch {
        Write-Log "Falha ao aplicar políticas ao perfil padrão: $($_.Exception.Message)" 'ERROR'
    } finally {
        # Coleta de lixo antes de descarregar, senão o hive fica preso.
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        Invoke-NativeQuiet { & reg.exe unload $mount 2>$null } | Out-Null
    }
}

#endregion

# ==========================================================================
# REGIÃO 8 - VALIDAÇÕES FINAIS
# ==========================================================================
#region Validation

function Invoke-FinalValidation {
    <#
        Confirma que os componentes críticos continuam presentes/saudáveis.
        Não corrige nada: apenas reporta. Falhas aqui são avisos altos.
    #>
    Write-Log '=== FASE: VALIDAÇÃO FINAL ===' 'STEP'
    $allOk = $true

    # 8.1 Microsoft Store presente
    $store = Get-AppxPackage -AllUsers -Name 'Microsoft.WindowsStore' -ErrorAction SilentlyContinue
    if ($store) { Write-Log 'OK: Microsoft Store presente.' 'OK' }
    else { Write-Log 'ALERTA: Microsoft Store NÃO encontrada!' 'ERROR'; $allOk = $false }

    # 8.2 winget / App Installer presente
    $appinst = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
    if ($appinst) { Write-Log 'OK: App Installer (winget) presente.' 'OK' }
    else { Write-Log 'ALERTA: App Installer ausente.' 'WARN' }

    # 8.3 Serviços críticos
    $svcMap = @{
        'wuauserv' = 'Windows Update'
        'WinDefend'= 'Microsoft Defender'
        'mpssvc'   = 'Windows Firewall'
        'wscsvc'   = 'Central de Segurança'
        'LanmanWorkstation' = 'Rede (Workstation)'
        'Dnscache' = 'Cliente DNS'
    }
    foreach ($s in $svcMap.GetEnumerator()) {
        $svc = Get-Service -Name $s.Key -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log ("OK: serviço '{0}' presente (status: {1})." -f $s.Value, $svc.Status) 'OK'
        } else {
            Write-Log ("ALERTA: serviço '{0}' não encontrado!" -f $s.Value) 'ERROR'
            $allOk = $false
        }
    }

    # 8.4 SmartScreen
    $ss = Get-AppxPackage -AllUsers -Name '*Apprep.ChxApp*' -ErrorAction SilentlyContinue
    if ($ss) { Write-Log 'OK: componente do SmartScreen presente.' 'OK' }
    else { Write-Log 'ALERTA: componente do SmartScreen não encontrado.' 'WARN' }

    # 8.5 WinRE
    try {
        $reAgent = Invoke-NativeQuiet { & reagentc.exe /info 2>$null } | Out-String
        if ($reAgent -match 'Enabled|Habilitado') {
            Write-Log 'OK: ambiente de recuperação (WinRE) habilitado.' 'OK'
        } else {
            Write-Log 'INFO: estado do WinRE não confirmado (verifique manualmente).' 'WARN'
        }
    } catch {
        Write-Log 'INFO: não foi possível consultar o WinRE.' 'WARN'
    }

    # 8.6 Nenhum serviço crítico pode ter o início DESABILITADO
    $svcStartOk = $true
    foreach ($crit in @('wuauserv','WinDefend','mpssvc','Dnscache','Dhcp','wscsvc')) {
        try {
            $cs = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $crit) -ErrorAction SilentlyContinue
            if ($cs -and $cs.StartMode -eq 'Disabled') {
                Write-Log ("ALERTA: serviço crítico '{0}' está com início DESABILITADO!" -f $crit) 'ERROR'
                $svcStartOk = $false
                $allOk = $false
            }
        } catch { }
    }
    if ($svcStartOk) { Write-Log 'OK: nenhum serviço crítico foi desabilitado.' 'OK' }

    if ($allOk) {
        Write-Log 'Validação final: todos os componentes críticos verificados estão presentes.' 'OK'
    } else {
        Write-Log 'Validação final: HÁ ALERTAS. Revise Errors.log antes de confiar no resultado.' 'ERROR'
    }
    return $allOk
}

#endregion

# ==========================================================================
# REGIÃO 9 - FLUXO PRINCIPAL
# ==========================================================================
#region Main

function Main {
    $modeLevel = if ($script:IsDryRun) { 'DRYRUN' } else { 'STEP' }
    Write-Log '=====================================================' 'INFO'
    Write-Log " WinDebloat - Núcleo (Core.ps1)" 'INFO'
    Write-Log " Desenvolvido por Edsilas | Apache License 2.0" 'INFO'
    Write-Log (" PowerShell: {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition) 'INFO'
    Write-Log (" Modo: {0}" -f $script:Mode) $modeLevel
    Write-Log (" Otimização: {0}" -f $(if ($script:IsAggressive) { 'AGRESSIVA' } else { 'padrão' })) $modeLevel
    Write-Log " Raiz: $script:RootDir" 'INFO'
    Write-Log '=====================================================' 'INFO'

    if (-not (Test-Administrator)) {
        Write-Log 'Este script exige privilégios administrativos. Abortando.' 'ERROR'
        return 2
    }

    # Preferências do usuário (Config.psd1 opcional). Arquivo presente e
    # inválido aborta: prosseguir poderia remover o que ele pediu para manter.
    if (-not (Read-UserConfig)) { return 6 }

    # Reinicialização pendente: a execução real disputa o armazém de
    # componentes com o Windows Update — aborta com orientação clara.
    if (Test-PendingReboot) {
        if ($script:IsDryRun) {
            Write-Log 'AVISO: há uma reinicialização pendente (atualização do Windows). A simulação continua, mas reinicie o computador antes da execução real.' 'WARN'
        } else {
            Write-Log 'Reinicialização pendente detectada: o Windows aguarda um reboot de atualização.' 'ERROR'
            Write-Log 'Reinicie o computador e execute a ferramenta novamente.' 'ERROR'
            return 5
        }
    }

    # Carregar módulos dependentes de Windows.
    $okAppx = Import-CompatModule -Name 'Appx'
    $okDism = Import-CompatModule -Name 'Dism'
    if (-not $okAppx) {
        Write-Log 'Módulo Appx indisponível. Não é possível continuar com segurança.' 'ERROR'
        return 3
    }
    if (-not $okDism) {
        Write-Log 'Módulo Dism indisponível: provisioned packages não serão tocados.' 'WARN'
    }

    try {
        $inv = Get-SystemInventory
    } catch {
        Write-Log "Inventário falhou: $($_.Exception.Message)" 'ERROR'
        return 4
    }

    Write-PhaseProgress -Step 1 -Total 7 -Status 'Análise do sistema'
    Invoke-SystemAnalysis
    Write-PhaseProgress -Step 2 -Total 7 -Status 'Preparando artefatos de recuperação'
    New-RecoveryArtifacts
    Write-PhaseProgress -Step 3 -Total 7 -Status 'Removendo aplicativos'
    Invoke-AppRemoval
    Write-PhaseProgress -Step 4 -Total 7 -Status 'Otimizando serviços'
    Invoke-ServiceOptimization
    Write-PhaseProgress -Step 5 -Total 7 -Status 'Aplicando políticas anti-reinstalação'
    Set-AntiReinstallPolicy
    Set-AggressiveTweaks
    Write-PhaseProgress -Step 6 -Total 7 -Status 'Aplicando políticas ao perfil padrão'
    Set-DefaultUserPolicy
    Write-PhaseProgress -Step 7 -Total 7 -Status 'Validação final'
    $valOk = Invoke-FinalValidation
    try { Write-Progress -Id 0 -Activity ("WinDebloat [{0}]" -f $script:Mode) -Completed } catch { }

    # --- Relatório final ---
    Write-Log '=====================================================' 'INFO'
    Write-Log ' RESUMO DA EXECUÇÃO' 'STEP'
    Write-Log ("   Removidos.....: {0}" -f $script:Stats.Removidos) 'INFO'
    Write-Log ("   Simulados.....: {0}" -f $script:Stats.Simulados) 'INFO'
    Write-Log ("   Protegidos....: {0}" -f $script:Stats.Protegidos) 'INFO'
    Write-Log ("   Preservados...: {0}" -f $script:Stats.Preservados) 'INFO'
    Write-Log ("   Não encontr...: {0}" -f $script:Stats.NaoEncontr) 'INFO'
    Write-Log ("   Serviços......: {0}" -f $script:Stats.Servicos) 'INFO'
    Write-Log ("   Políticas.....: {0}" -f $script:Stats.Politicas) 'INFO'
    Write-Log ("   Erros.........: {0}" -f $script:Stats.Erros) 'INFO'
    Write-Log '=====================================================' 'INFO'

    if ($script:IsDryRun) {
        Write-Log 'SIMULAÇÃO concluída. Nada foi alterado. Para aplicar, use -Execute.' 'DRYRUN'
    } else {
        Write-Log 'EXECUÇÃO concluída. Reinicie o sistema para finalizar as alterações.' 'OK'
    }

    # Lista final de apps removidos (snapshot para auditoria).
    try {
        $after = Join-Path $script:RecoveryDir ("Appx_Apos_{0}.txt" -f $script:Stamp)
        Get-AppxPackage -AllUsers | Select-Object Name, Version |
            Sort-Object Name | Format-Table -AutoSize | Out-String |
            Set-Content -LiteralPath $after -Encoding UTF8
    } catch { }

    if ($script:Stats.Erros -gt 0 -or -not $valOk) { return 1 }
    return 0
}

$exit = Main
exit $exit

#endregion
