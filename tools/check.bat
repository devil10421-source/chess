@echo off
REM 《六族遠征》一鍵檢查（Windows）
REM 用法：tools\check.bat "C:\路徑\Godot_v4.7.2-stable_win64_console.exe"
REM 請使用檔名含 _console 的 Godot 執行檔，才能在命令列看到輸出與結束碼。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check.ps1" %*
exit /b %ERRORLEVEL%
