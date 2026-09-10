@echo off
REM ============================================================
REM  Esport Manager - lancement du jeu
REM  Double-cliquez sur ce fichier.
REM  Si Godot est installe ailleurs, corrigez la ligne "set GODOT=".
REM ============================================================

set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT%" goto introuvable

start "" "%GODOT%" --path "%~dp0."
exit /b 0

:introuvable
echo.
echo   Godot est introuvable a cet emplacement :
echo   %GODOT%
echo.
echo   Ouvrez Jouer.bat dans un editeur de texte
echo   et corrigez la ligne commencant par "set GODOT=".
echo.
pause
