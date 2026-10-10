@echo off
REM GluePad F1 - build reproduzivel (sem MSVC, sem CMake, sem admin).
REM Toolchain fixa: C:\Tools\mingw32 (GCC 16.2.0 i686).
setlocal
set CC=C:\Tools\mingw32\bin\i686-w64-mingw32-gcc.exe
set GAME_MODS=C:\Users\rodri\OneDrive\wow\octowow\mods
if not exist "%CC%" (
  echo ERRO: toolchain ausente: %CC%
  echo Siga a receita de reinstall no README.
  exit /b 1
)
if not exist build mkdir build
REM Valida o helper em Lua 5.0 estrito (NUNCA o 5.4 do PATH) e embute em C.
C:\Tools\lua50\luac50.exe -p src\gluepad.lua
if errorlevel 1 (
  echo ERRO: gluepad.lua nao e Lua 5.0 valido.
  exit /b 1
)
python embed_lua.py src\gluepad.lua src\glue_lua.h
if errorlevel 1 (
  echo ERRO: embed do gluepad.lua falhou.
  exit /b 1
)
"%CC%" -shared -o build\GluePad.dll src\dllmain.c src\pad.c src\screen.c src\keycap.c src\glog.c src\glueapi.c src\glue.c -lxinput -Os -Wall -Wl,--subsystem,windows
if errorlevel 1 (
  echo ERRO: compilacao falhou.
  exit /b 1
)
echo OK: build\GluePad.dll gerada. Verificando PE Machine...
powershell -NoProfile -Command "$b=[IO.File]::ReadAllBytes('build\GluePad.dll'); $e=[BitConverter]::ToInt32($b,0x3C); $m=[BitConverter]::ToUInt16($b,$e+4); '{0:X4}' -f $m | Write-Host; if($m -ne 0x14C){ Write-Host 'ERRO: PE nao e i686 (0x014C)'; exit 1 } else { Write-Host 'OK: PE Machine=014C (i386 32-bit)' }"
if errorlevel 1 exit /b 1
copy /Y build\GluePad.dll "%GAME_MODS%\GluePad.dll" >nul
if errorlevel 1 goto copyfail
echo OK: instalada em %GAME_MODS%\GluePad.dll
goto end
:copyfail
echo ERRO: nao consegui copiar para %GAME_MODS%
echo Dica: confira se o OneDrive nao esta sincronizando a pasta no momento.
exit /b 1
:end
