@echo off
setlocal EnableExtensions
title WinDebloat - Launcher

REM ============================================================
REM  WinDebloat - Launcher.bat
REM  Desenvolvido por Edsilas
REM  Copyright 2026 Edsilas
REM  Licensed under the Apache License, Version 2.0 (the "License");
REM  you may not use this file except in compliance with the License.
REM  You may obtain a copy of the License at
REM      http://www.apache.org/licenses/LICENSE-2.0
REM  Distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
REM  CONDITIONS OF ANY KIND. See the License for details.
REM ============================================================
REM  Orquestrador: verifica privilegios, localiza PowerShell 7
REM  (com fallback para Windows PowerShell 5.1), registra log de
REM  inicializacao e executa Core.ps1.
REM ============================================================

REM ----- Caminhos base -----
set "BASEDIR=%~dp0"
if "%BASEDIR:~-1%"=="\" set "BASEDIR=%BASEDIR:~0,-1%"
set "CORE=%BASEDIR%\Core.ps1"
set "LOGDIR=%BASEDIR%\Logs"
set "BOOTLOG=%LOGDIR%\Launcher.log"
REM Codigo de saida padrao; garante que %RC% nunca expanda vazio em :done.
set "RC=0"

if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1

call :log "==================================================="
call :log "WinDebloat Launcher iniciado."
call :log "BASEDIR=%BASEDIR%"

REM ----- 1) Verificar Core.ps1 -----
if not exist "%CORE%" (
    call :log "ERRO: Core.ps1 nao encontrado em %CORE%."
    echo [ERRO] Core.ps1 nao encontrado. Coloque o Launcher.bat na mesma pasta do Core.ps1.
    pause
    exit /b 10
)

REM ----- 2) Verificar privilegios administrativos -----
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    call :log "Sem privilegios de admin. Tentando auto-elevacao..."
    echo [INFO] Solicitando privilegios administrativos...
    REM Re-executa este .bat elevado, preservando o argumento de modo.
    REM Correcao: -ArgumentList '' lanca erro no PowerShell; so passar se houver args.
    if "%~1"=="" (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b 0
)
call :log "Privilegios administrativos: OK."

REM ----- 3) Localizar mecanismo PowerShell (pwsh 7 preferido; fallback 5.1) -----
set "PWSH="
set "ENGINE="
where pwsh >nul 2>&1
if %errorlevel%==0 (
    set "PWSH=pwsh"
    set "ENGINE=PowerShell 7"
) else (
    if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
        set "ENGINE=PowerShell 7"
    )
    if not defined PWSH if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" (
        set "PWSH=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
        set "ENGINE=PowerShell 7"
    )
    REM Fallback: Windows PowerShell 5.1, componente nativo do Windows 10/11.
    if not defined PWSH if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
        set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
        set "ENGINE=Windows PowerShell 5.1"
    )
)

if not defined PWSH (
    call :log "ERRO: nenhum mecanismo PowerShell encontrado."
    echo.
    echo [ERRO] Nenhum PowerShell foi encontrado neste sistema.
    echo        Instale o PowerShell 7 pela Microsoft Store ou pelo MSI oficial
    echo        e execute novamente este Launcher.
    echo.
    pause
    exit /b 11
)
call :log "Mecanismo selecionado: %ENGINE% (%PWSH%)"
echo [INFO] Mecanismo PowerShell: %ENGINE%

REM ----- 4) Selecionar modo (argumento ou menu) -----
set "LASTRUN=nenhuma nesta sessao"
set "MODE=%~1"
if /I "%MODE%"=="dry" goto :run_dry
if /I "%MODE%"=="real" goto :run_real
if /I "%MODE%"=="execute" goto :run_real
if /I "%MODE%"=="dry-aggressive" goto :run_dry_aggr
if /I "%MODE%"=="real-aggressive" goto :run_real_aggr

:menu
title WinDebloat - Menu principal
cls
REM Estado dinamico: reavaliado a cada exibicao (o usuario pode criar o
REM Config.psd1 entre uma acao e outra sem reabrir o programa).
if exist "%BASEDIR%\Config.psd1" (
    set "CFGSTATE=personalizada [Config.psd1]"
) else (
    set "CFGSTATE=padrao [opcional: copie Config.exemplo.psd1]"
)
echo.
echo  ==================================================================
echo    WinDebloat  -  Limpeza segura para Windows 10/11
echo  ==================================================================
echo    Mecanismo ..: %ENGINE%
echo    Pasta ......: %BASEDIR%
echo    Listas .....: %CFGSTATE%
echo    Ultima acao : %LASTRUN%
echo  ------------------------------------------------------------------
echo    SIMULACOES (mostram tudo sem alterar nada)
echo    [1] Simulacao padrao        ^<-- recomendado primeiro
echo    [2] Simulacao agressiva
echo.
echo    EXECUCOES REAIS (pedem confirmacao SIM)
echo    [3] Execucao real padrao      remove apps, otimiza servicos
echo    [4] Execucao real agressiva   inclui ajustes avancados
echo.
echo    UTILITARIOS
echo    [R] Ver ultimo relatorio      abre Debloat.log no Bloco de Notas
echo    [B] Abrir pasta de backups    abre a pasta Recovery
echo    [5] Sair
echo  ==================================================================
echo    Desenvolvido por Edsilas ^| Apache License 2.0
echo.
set "OPT="
set /p "OPT= Escolha uma opcao [1/2/3/4/5/R/B]: "
if "%OPT%"=="1" (set "FROMMENU=1" & goto :run_dry)
if "%OPT%"=="2" (set "FROMMENU=1" & goto :run_dry_aggr)
if "%OPT%"=="3" (set "FROMMENU=1" & goto :confirm_real)
if "%OPT%"=="4" (set "FROMMENU=1" & goto :confirm_real_aggr)
if "%OPT%"=="5" exit /b 0
if /I "%OPT%"=="R" goto :view_report
if /I "%OPT%"=="B" goto :open_recovery
echo.
echo  Opcao invalida: digite 1, 2, 3, 4, 5, R ou B e pressione Enter.
pause
goto :menu

:view_report
if exist "%LOGDIR%\Debloat.log" (
    call :log "Abrindo relatorio Debloat.log."
    start "" notepad.exe "%LOGDIR%\Debloat.log"
) else (
    echo.
    echo  Ainda nao ha relatorio: rode primeiro uma Simulacao [1] ou [2].
    pause
)
goto :menu

:open_recovery
if exist "%BASEDIR%\Recovery" (
    call :log "Abrindo pasta Recovery."
    start "" explorer.exe "%BASEDIR%\Recovery"
) else (
    echo.
    echo  A pasta Recovery ainda nao existe: ela e criada na primeira execucao.
    pause
)
goto :menu

:confirm_real
echo.
echo  [ATENCAO] O modo REAL ira remover aplicativos, otimizar servicos
echo            e aplicar politicas.
set "CONF="
set /p "CONF=Digite SIM para confirmar: "
if /I "%CONF%"=="SIM" goto :run_real
echo Cancelado.
goto :menu

:confirm_real_aggr
echo.
echo  [ATENCAO] O modo AGRESSIVO amplia os ajustes de servicos e aplica
echo            configuracoes avancadas de desempenho. Tudo e reversivel
echo            (ponto de restauracao + script em Recovery), mas recomenda-se
echo            rodar a Simulacao agressiva antes.
set "CONF="
set /p "CONF=Digite SIM para confirmar: "
if /I "%CONF%"=="SIM" goto :run_real_aggr
echo Cancelado.
goto :menu

REM ----- 5) Execucao -----
:run_dry
set "RUNDESC=Simulacao padrao"
title WinDebloat - Simulacao padrao em andamento...
call :log "Iniciando Core.ps1 em modo DRYRUN."
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -DryRun -RootDir "%BASEDIR%"
set "RC=%errorlevel%"
goto :done

:run_dry_aggr
set "RUNDESC=Simulacao agressiva"
title WinDebloat - Simulacao agressiva em andamento...
call :log "Iniciando Core.ps1 em modo DRYRUN AGRESSIVO."
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -DryRun -Aggressive -RootDir "%BASEDIR%"
set "RC=%errorlevel%"
goto :done

:run_real
set "RUNDESC=Execucao real padrao"
title WinDebloat - Execucao real em andamento...
call :log "Iniciando Core.ps1 em modo EXECUTE."
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -Execute -RootDir "%BASEDIR%"
set "RC=%errorlevel%"
goto :done

:run_real_aggr
set "RUNDESC=Execucao real agressiva"
title WinDebloat - Execucao real agressiva em andamento...
call :log "Iniciando Core.ps1 em modo EXECUTE AGRESSIVO."
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -Execute -Aggressive -RootDir "%BASEDIR%"
set "RC=%errorlevel%"
goto :done

:done
title WinDebloat - Concluido
call :log "Core.ps1 finalizado com codigo %RC% (%RUNDESC%)."
REM Traducao do codigo de saida para uma mensagem clara ao usuario.
set "RCMSG=codigo desconhecido; consulte os logs"
if "%RC%"=="0"  set "RCMSG=sucesso, sem alertas"
if "%RC%"=="1"  set "RCMSG=concluido com alertas; revise Errors.log"
if "%RC%"=="2"  set "RCMSG=sem privilegios administrativos"
if "%RC%"=="3"  set "RCMSG=modulo Appx indisponivel"
if "%RC%"=="4"  set "RCMSG=falha no inventario do sistema"
if "%RC%"=="5"  set "RCMSG=reinicializacao pendente; reinicie e rode de novo"
if "%RC%"=="6"  set "RCMSG=Config.psd1 invalido; corrija ou renomeie o arquivo"
if "%RC%"=="7"  set "RCMSG=outra execucao ja em andamento; aguarde e tente de novo"
set "LASTRUN=%RUNDESC% (%RCMSG%)"
echo.
echo  ------------------------------------------------------------------
echo    RESULTADO
echo    Acao ........: %RUNDESC%
echo    Situacao ....: %RCMSG% (codigo %RC%)
echo    Relatorios ..: %LOGDIR%
echo    Backups .....: %BASEDIR%\Recovery
if "%RC%"=="0" if /I not "%RUNDESC:~0,9%"=="Simulacao" echo    Proximo passo: REINICIE o computador para concluir as alteracoes.
echo  ------------------------------------------------------------------
echo.
pause
REM Se a execucao partiu do menu, volta ao menu (a saida e apenas pela opcao 5).
REM No modo direto (Launcher.bat dry/real), encerra com o codigo de saida,
REM preservando o comportamento para uso em scripts e automacao.
if defined FROMMENU (
    set "FROMMENU="
    goto :menu
)
exit /b %RC%

REM ----- Sub-rotina de log -----
:log
echo [%date% %time%] %~1>>"%BOOTLOG%"
goto :eof
