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
set "MODE=%~1"
if /I "%MODE%"=="dry" goto :run_dry
if /I "%MODE%"=="real" goto :run_real
if /I "%MODE%"=="execute" goto :run_real

:menu
echo.
echo ============================================
echo    WinDebloat
echo ============================================
echo    [1] Simulacao (Dry Run) - nao altera nada   ^<-- recomendado primeiro
echo    [2] Execucao real        - aplica remocoes
echo    [3] Sair
echo ============================================
echo    Desenvolvido por Edsilas
echo.
set "OPT="
set /p "OPT= Escolha uma opcao [1/2/3]: "
if "%OPT%"=="1" (set "FROMMENU=1" & goto :run_dry)
if "%OPT%"=="2" (set "FROMMENU=1" & goto :confirm_real)
if "%OPT%"=="3" exit /b 0
echo Opcao invalida.
goto :menu

:confirm_real
echo.
echo  [ATENCAO] O modo REAL ira remover aplicativos e aplicar politicas.
set /p "CONF=Digite SIM para confirmar: "
if /I "%CONF%"=="SIM" goto :run_real
echo Cancelado.
goto :menu

REM ----- 5) Execucao -----
:run_dry
call :log "Iniciando Core.ps1 em modo DRYRUN."
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -DryRun -RootDir "%BASEDIR%"
set "RC=%errorlevel%"
goto :done

:run_real
call :log "Iniciando Core.ps1 em modo EXECUTE."
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -Execute -RootDir "%BASEDIR%"
set "RC=%errorlevel%"
goto :done

:done
call :log "Core.ps1 finalizado com codigo %RC%."
echo.
echo [INFO] Concluido. Codigo de saida: %RC%
echo        Verifique os logs em: %LOGDIR%
echo.
pause
REM Se a execucao partiu do menu, volta ao menu (a saida e apenas pela opcao 3).
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
