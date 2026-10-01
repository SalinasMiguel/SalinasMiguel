@echo off
setlocal
rem Lanzador: pide permisos de administrador y muestra el menu.

net session >nul 2>&1
if errorlevel 1 (
    echo Pidiendo permisos de administrador...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

:menu
cls
echo ==================================================
echo    OPTIMIZAR PC - sin tirones ni congelamientos
echo ==================================================
echo.
echo    1. Diagnostico  (solo revisa, no cambia nada)
echo    2. Optimizar    (pregunta antes de cada cambio)
echo    3. Deshacer los cambios de la opcion 2
echo    4. Salir
echo.
set "opcion="
set /p "opcion=Elige una opcion (1-4): "

if "%opcion%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostico.ps1"
if "%opcion%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0optimizar.ps1"
if "%opcion%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0optimizar.ps1" -Revertir
if "%opcion%"=="4" exit /b

echo.
pause
goto menu
