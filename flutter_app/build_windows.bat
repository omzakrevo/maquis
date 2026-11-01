@echo off
rem Compile CAISSE PRO pour Windows sur ce PC.
rem Prérequis : Flutter (stable) et Visual Studio 2022 avec « Développement Desktop en C++ ».
rem Optionnel : Inno Setup 6 pour fabriquer l'installateur .exe.
cd /d "%~dp0"
call flutter pub get || goto :err
call flutter build windows --release || goto :err
if not exist dist mkdir dist
powershell -NoProfile -Command "Compress-Archive -Force -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'dist\CaissePro_Windows_portable.zip'"
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" (
  "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" windows\installer\installer.iss
)
echo.
echo Termine : voir le dossier dist
explorer dist
goto :eof
:err
echo La compilation a echoue. Lancez "flutter doctor" pour verifier l'installation.
pause
