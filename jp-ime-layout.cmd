@echo off
::============================================================================
:: jp-ime-layout.cmd
::
:: Chooses which keyboard layout the Japanese IME (Microsoft IME, and also
:: Mozc / Google Japanese Input) uses underneath. Windows only offers English
:: 101 or Japanese 106 keys, so on other keyboards accents and dead keys do not
:: work in the IME's alphanumeric/romaji mode (toggled with Alt + the key left
:: of "1"). The default here is Brazilian ABNT2.
::
:: HOW IT WORKS
::   The Japanese keyboard layout (KBDJPN.DLL) is only a stub. It reads the
::   value below and loads the real layout DLL it names:
::
::     HKLM\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters
::       "LayerDriver JPN" (REG_SZ)
::
::   Windows sets it to kbd101.dll (English 101/102 keys) or kbd106.dll
::   (Japanese 106/109 keys). This script points it to another layout DLL.
::
:: USAGE
::   jp-ime-layout.cmd                  Apply the default layout (ABNT2)
::   jp-ime-layout.cmd --layout pt      Apply another layout (name or DLL)
::   jp-ime-layout.cmd --list           List the layout names
::   jp-ime-layout.cmd --undo           Restore the original layout
::   jp-ime-layout.cmd --status         Show the current setting (no admin)
::   jp-ime-layout.cmd --hide-keyboard  Leave only the Japanese IME (no admin)
::   jp-ime-layout.cmd --show-keyboard  Bring the other keyboards back
::   jp-ime-layout.cmd --help           Show all options
::
:: HIDING THE OTHER KEYBOARD
::   Windows 11 does not let you remove the keyboard of the display language,
::   and re-adds it if you clear it. --hide-keyboard keeps the language (and
::   its spell checker) but makes the Japanese IME the default input method
::   (Set-WinDefaultInputMethodOverride) and leaves only Japanese in
::   HKCU\Keyboard Layout\Preload. It changes only the current user.
::
:: NOTES
::   - Needs administrator rights to apply or undo. It asks via UAC.
::   - Takes effect only after you SIGN OUT and back in (or restart).
::   - The Alt+` IME toggle needs the key left of "1" to produce VK_OEM_3.
::     That is true for ABNT2 and US-based layouts, but not for every layout
::     (e.g. German, French). If it breaks, set another IME on/off key in the
::     Microsoft IME settings (Key and touch customization).
::   - Windows rewrites this value if you change "Hardware keyboard layout"
::     in Settings > Time & language > Language > Japanese > Options, and a
::     major Windows update may reset it. Run --status to check, and run the
::     script again to re-apply.
::   - The original value is saved once, before the first change, in
::     %ProgramData%\JpImeLayout\ (original.txt + original.reg). Every change
::     is logged to %ProgramData%\JpImeLayout\log.txt.
::============================================================================
setlocal EnableExtensions

set "KEY=HKLM\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters"
set "VAL=LayerDriver JPN"
set "DEFAULT_LAYOUT=abnt2"
set "FALLBACK_DLL=kbd101.dll"
set "DATA=%ProgramData%\JpImeLayout"
set "LOG=%DATA%\log.txt"

:: Known layouts: "name|DLL|description". Any other kbd*.dll also works.
set LAYOUTS="abnt2|KBDBR.DLL|Portuguese Brazil ABNT2" ^
 "pt|kbdpo.dll|Portuguese Portugal" ^
 "us|kbdus.dll|US" ^
 "us-intl|KBDUSX.DLL|US International" ^
 "uk|kbduk.dll|United Kingdom" ^
 "es|kbdsp.dll|Spanish" ^
 "latam|kbdla.dll|Latin American Spanish" ^
 "de|kbdgr.dll|German" ^
 "fr|kbdfr.dll|French" ^
 "it|kbdit.dll|Italian" ^
 "dvorak|kbddv.dll|US Dvorak" ^
 "en101|kbd101.dll|English 101/102 keys [Windows option]" ^
 "jp106|kbd106.dll|Japanese 106/109 keys [Windows option]"

set "MODE=apply"
set "LAYOUT="
set "ELEVATED="
set "NOPAUSE="
set "PAUSE_AT_END="
set "RC=0"
:: Saved before parsing the arguments, because SHIFT also shifts %0.
set "SCRIPT=%~f0"

:: Pause at the end when started by double-click, so the window stays open.
:: Delayed expansion keeps an & in the script's path from breaking this line.
setlocal EnableDelayedExpansion
if /i not "!cmdcmdline:%~nx0=!"=="!cmdcmdline!" (endlocal & set "PAUSE_AT_END=1") else endlocal

::---------------------------------------------------------------- arguments
:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--undo"     (set "MODE=undo"   & shift & goto parse)
if /i "%~1"=="--revert"   (set "MODE=undo"   & shift & goto parse)
if /i "%~1"=="-u"         (set "MODE=undo"   & shift & goto parse)
if /i "%~1"=="--apply"    (set "MODE=apply"  & shift & goto parse)
if /i "%~1"=="--status"   (set "MODE=status" & shift & goto parse)
if /i "%~1"=="-s"         (set "MODE=status" & shift & goto parse)
if /i "%~1"=="--list"     (set "MODE=list"   & shift & goto parse)
if /i "%~1"=="--help"     (set "MODE=help"   & shift & goto parse)
if /i "%~1"=="-h"         (set "MODE=help"   & shift & goto parse)
if /i "%~1"=="/?"         (set "MODE=help"   & shift & goto parse)
if /i "%~1"=="--hide-keyboard" (set "MODE=hide" & shift & goto parse)
if /i "%~1"=="--show-keyboard" (set "MODE=show" & shift & goto parse)
if /i "%~1"=="--no-pause" (set "NOPAUSE=1"   & shift & goto parse)
if /i "%~1"=="--elevated" (set "ELEVATED=1"  & shift & goto parse)
if /i "%~1"=="-l" goto opt_layout
if /i "%~1"=="--layout" goto opt_layout
echo ERROR: unknown option "%~1". Run with --help.
set "RC=2"
goto end

:opt_layout
if "%~2"=="" (
    echo ERROR: --layout needs a name or DLL, e.g. --layout pt. See --list.
    set "RC=2"
    goto end
)
set "LAYOUT=%~2"
shift & shift & goto parse

:parsed
if defined ELEVATED set "PAUSE_AT_END=1"
if defined NOPAUSE set "PAUSE_AT_END="
if "%MODE%"=="help"   goto help
if "%MODE%"=="list"   goto list
if "%MODE%"=="status" goto status
if "%MODE%"=="hide"   goto hide
if "%MODE%"=="show"   goto show

:: Validate the layout before asking for admin rights.
if "%MODE%"=="apply" if not defined LAYOUT set "LAYOUT=%DEFAULT_LAYOUT%"
if defined LAYOUT (
    call :resolve "%LAYOUT%" || goto end
)

::---------------------------------------------------------------- elevation
fltmc >nul 2>&1 && goto elevated_ok
if defined ELEVATED (
    echo ERROR: could not get administrator rights.
    set "RC=5"
    goto end
)
echo Administrator rights are needed. Asking via UAC...
set "ARGS=--elevated"
if "%MODE%"=="undo" set "ARGS=%ARGS% --undo"
if defined LAYOUT set "ARGS=%ARGS% --layout %LAYOUT%"
if defined NOPAUSE set "ARGS=%ARGS% --no-pause"
:: Elevate cmd.exe itself. Windows elevates a .cmd file as cmd /C "file" args,
:: which mangles paths with & or with spaces plus ( ), e.g. "name (1).cmd".
set "CMD_ARGS=/d /c ""%SCRIPT%" %ARGS%""
powershell -NoProfile -Command "try { $p = Start-Process -FilePath $env:ComSpec -ArgumentList $env:CMD_ARGS -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { exit 1223 }"
set "RC=%ERRORLEVEL%"
if "%RC%"=="1223" (
    echo Cancelled: UAC prompt was declined.
) else (
    echo Elevated window finished with exit code %RC%.
    set "PAUSE_AT_END="
)
goto end

:elevated_ok
call :read_current
if not exist "%DATA%" mkdir "%DATA%"
if "%MODE%"=="undo" goto undo

::---------------------------------------------------------------- apply
:apply
if /i "%CUR%"=="%RES_DLL%" (
    echo Already set: "%VAL%" = %CUR% [%RES_DESC%]. Nothing to do.
    echo If it is not working yet, sign out and back in.
    goto end
)
:: Save the original value once, before the first change.
if not exist "%DATA%\original.txt" (
    if /i not "%CUR%"=="NOT-SET" (
        >"%DATA%\original.txt" echo %CUR%
        reg export "%KEY%" "%DATA%\original.reg" /y >nul
        echo Original value saved: %CUR%  [%DATA%\original.txt]
    )
)
call :set_value "%RES_DLL%" || goto end
echo.
echo Done: "%VAL%" changed from %CUR% to %RES_DLL% [%RES_DESC%].
echo SIGN OUT and back in [or restart] for the change to take effect.
goto end

::---------------------------------------------------------------- undo
:undo
set "TARGET="
if defined LAYOUT set "TARGET=%RES_DLL%"
if not defined TARGET if exist "%DATA%\original.txt" set /p TARGET=<"%DATA%\original.txt"
if not defined TARGET (
    set "TARGET=%FALLBACK_DLL%"
    echo No saved original value found. Using %FALLBACK_DLL% [English 101/102 keys].
    echo For a Japanese 106/109 keyboard use: --undo --layout jp106
)
if /i "%CUR%"=="%TARGET%" (
    echo Already set to %TARGET%. Nothing to do.
    goto end
)
call :set_value "%TARGET%" || goto end
echo.
echo Done: "%VAL%" changed from %CUR% to %TARGET%.
echo SIGN OUT and back in [or restart] for the change to take effect.
goto end

::---------------------------------------------------------------- status
:status
call :read_current
call :describe "%CUR%"
echo Registry : %KEY%
echo Value    : "%VAL%" = %CUR%  [%DESC%]
if exist "%DATA%\original.txt" (
    set /p ORIG=<"%DATA%\original.txt"
    call echo Original : %%ORIG%%  [saved in %DATA%\original.txt]
) else (
    echo Original : not saved yet
)
reg query "HKCU\Keyboard Layout\Preload" 2>nul | find "00000411" >nul || echo Warning  : Japanese does not seem to be installed for this user.
reg query "HKCU\Keyboard Layout\Preload" 2>nul | find "REG_SZ" | find /v "0411" >nul && (echo Keyboards: other keyboards are loaded too [--hide-keyboard hides them]) || echo Keyboards: Japanese only
echo Note     : a change only takes effect after signing out and back in.
goto end

::---------------------------------------------------------------- hide / show
:: Per-user settings: run without elevation, since an elevated window may
:: belong to another user.
:hide
set "PS=$ErrorActionPreference = 'Stop';"
set "PS=%PS% $ja = Get-WinUserLanguageList | Where-Object LanguageTag -like 'ja*' | Select-Object -First 1;"
set "PS=%PS% if (-not $ja.InputMethodTips) { 'ERROR: Japanese input is not installed for this user.'; exit 4 };"
set "PS=%PS% $tip = $ja.InputMethodTips[0]; Set-WinDefaultInputMethodOverride -InputTip $tip;"
set "PS=%PS% $k = Get-Item 'HKCU:\Keyboard Layout\Preload';"
set "PS=%PS% $n = @($k.GetValueNames() | Where-Object { $_ -match '\A\d+\z' } | Sort-Object { [int]$_ });"
set "PS=%PS% $keep = @($n | ForEach-Object { $k.GetValue($_) } | Where-Object { $_ -like '*0411' });"
set "PS=%PS% if (-not $keep) { $keep = @('00000411') };"
set "PS=%PS% $n | ForEach-Object { Remove-ItemProperty $k.PSPath -Name $_ };"
set "PS=%PS% for ($i = 0; $i -lt $keep.Count; $i++) { New-ItemProperty $k.PSPath -Name ($i + 1) -Value $keep[$i] -PropertyType String | Out-Null };"
set "PS=%PS% 'Default input method: ' + $tip"
call :ps || goto end
echo Done: only the Japanese IME is left. The display language and its spell
echo checker stay. SIGN OUT and back in for the change to take effect.
goto end

:: Removes the override and gives each language without a keyboard its
:: default one, e.g. 0416:00000416 for pt-BR. Set-WinUserLanguageList also
:: rewrites the Preload list.
:show
set "PS=$ErrorActionPreference = 'Stop'; Set-WinDefaultInputMethodOverride; $list = Get-WinUserLanguageList;"
set "PS=%PS% foreach ($l in $list) { $id = '{0:X4}' -f ([Globalization.CultureInfo]$l.LanguageTag).LCID;"
set "PS=%PS% if (-not $l.InputMethodTips -and $id -ne '1000') { $l.InputMethodTips.Add($id + ':0000' + $id) } };"
set "PS=%PS% Set-WinUserLanguageList $list -Force"
call :ps || goto end
echo Done: the keyboards of the other languages are back.
echo SIGN OUT and back in for the change to take effect.
goto end

::---------------------------------------------------------------- list
:list
echo.
echo Layout names for --layout [any kbd*.dll file name in System32 also works]:
echo.
for %%E in (%LAYOUTS%) do for /f "tokens=1-3 delims=|" %%a in (%%E) do call :list_row "%%a" "%%b" "%%c"
echo.
echo Current value: & call :read_current & call echo   %%CUR%%
goto end

:list_row
set "N=%~1          "
set "D=%~2              "
if exist "%SystemRoot%\System32\%~2" (set "OK=") else (set "OK=  [missing]")
if /i "%~1"=="%DEFAULT_LAYOUT%" set "OK=%OK%  [default]"
echo   %N:~0,10%%D:~0,14%%~3%OK%
exit /b 0

::---------------------------------------------------------------- help
:help
echo.
echo jp-ime-layout.cmd - choose the keyboard layout used under the Japanese IME,
echo so accents and dead keys work in its alphanumeric/romaji mode.
echo.
echo Usage: jp-ime-layout.cmd [options]
echo.
echo   [no option], --apply   Apply a layout. Default: %DEFAULT_LAYOUT% [Brazilian ABNT2].
echo   --layout, -l NAME      Layout to use: a name from --list, e.g. pt, us-intl,
echo                          or a DLL file name from System32, e.g. kbdca.dll.
echo                          With --undo, restores to this layout instead.
echo   --list                 List the layout names. No admin rights needed.
echo   --undo, --revert, -u   Restore the original value saved before the first
echo                          change; kbd101.dll if none was saved.
echo   --status, -s           Show the current value. No admin rights needed.
echo   --hide-keyboard        Leave only the Japanese IME for this user, keeping
echo                          the display language and its spell checker.
echo   --show-keyboard        Bring the other languages' keyboards back.
echo   --no-pause             Do not wait for a key press at the end.
echo   --help, -h, /?         Show this help.
echo.
echo Examples:
echo   jp-ime-layout.cmd                    use ABNT2
echo   jp-ime-layout.cmd --layout us-intl   use US International
echo   jp-ime-layout.cmd --undo             back to the original
echo.
echo Registry value changed:
echo   %KEY%
echo   "%VAL%"  [REG_SZ]
echo.
echo Notes:
echo   - Applying or undoing needs admin rights; the script asks via UAC.
echo     --hide-keyboard and --show-keyboard do not.
echo   - Takes effect only after signing out and back in, or restarting.
echo   - The Alt+` IME toggle may stop working on layouts where the key left of
echo     "1" is not "`", e.g. de, fr. Set another IME on/off key in the
echo     Microsoft IME settings if that happens. It works with abnt2 and us*.
echo   - Changing "Hardware keyboard layout" in the Japanese IME settings, or a
echo     major Windows update, can reset the value. Re-run the script then.
echo   - Backup and log: %DATA%
echo.
echo Exit codes: 0 ok, 1 registry write failed, 2 bad arguments,
echo             3 layout not found, 4 Japanese not installed,
echo             5 not elevated, 1223 UAC declined.
goto end

::---------------------------------------------------------------- helpers
:: Turns a layout name or DLL file name into RES_DLL and RES_DESC.
:resolve
set "RES_DLL="
set "RES_DESC="
for %%E in (%LAYOUTS%) do for /f "tokens=1-3 delims=|" %%a in (%%E) do (
    if /i "%~1"=="%%a" (set "RES_DLL=%%b" & set "RES_DESC=%%c")
)
if not defined RES_DLL (
    echo %~1| findstr /i /r "\.dll$" >nul || (
        echo ERROR: unknown layout "%~1". Run with --list.
        set "RC=2"
        exit /b 1
    )
    set "RES_DLL=%~1"
)
if not defined RES_DESC (
    call :describe "%RES_DLL%"
    call set "RES_DESC=%%DESC%%"
)
if not exist "%SystemRoot%\System32\%RES_DLL%" (
    echo ERROR: %SystemRoot%\System32\%RES_DLL% not found.
    set "RC=3"
    exit /b 1
)
exit /b 0

:: Sets DESC for a DLL file name.
:describe
set "DESC=custom layout"
if /i "%~1"=="NOT-SET" (set "DESC=value missing" & exit /b 0)
for %%E in (%LAYOUTS%) do for /f "tokens=1-3 delims=|" %%a in (%%E) do (
    if /i "%~1"=="%%b" set "DESC=%%c"
)
exit /b 0

:read_current
set "CUR="
for /f "tokens=3,*" %%A in ('reg query "%KEY%" /v "%VAL%" 2^>nul ^| find /i "%VAL%"') do set "CUR=%%B"
if not defined CUR set "CUR=NOT-SET"
exit /b 0

:set_value
if "%~1"=="" (
    echo ERROR: no layout DLL to write.
    set "RC=2"
    exit /b 1
)
reg add "%KEY%" /v "%VAL%" /t REG_SZ /d "%~1" /f >nul
if errorlevel 1 (
    echo ERROR: failed to write the registry value.
    set "RC=1"
    exit /b 1
)
>>"%LOG%" echo %date% %time%  user=%USERNAME%  "%VAL%": %CUR% -^> %~1
exit /b 0

:: Runs the PowerShell code in PS. Errors exit with 1.
:ps
powershell -NoProfile -Command "& ([scriptblock]::Create($env:PS))"
set "RC=%ERRORLEVEL%"
exit /b %RC%

::---------------------------------------------------------------- end
:end
if defined PAUSE_AT_END (echo. & pause)
exit /b %RC%
