@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions
title 迅雷内置播放器卸载脚本
color 07

echo ==========================================
echo 迅雷内置播放器卸载脚本
echo ==========================================
echo.
echo 此脚本将解除迅雷播放器对视频/音频文件的系统接管。
echo.
echo 不会删除或修改迅雷主程序、player_helper.node 和
echo APlayer.dll，下载功能不受影响。
echo.
echo 说明：迅雷内置播放器与主程序耦合，无法安全删除
echo 播放器文件；本脚本只清理注册表中的关联和右键菜单。
echo.
echo 请确保以管理员身份运行此脚本。
echo.

net session >nul 2>&1
if errorlevel 1 (
    echo [错误] 当前不是管理员权限。
    echo 请右键点击此脚本，选择“以管理员身份运行”。
    pause
    exit /b 1
)

pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-thunder-player.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if "%RC%"=="0" (
    echo 脚本执行完毕。
) else (
    echo 脚本执行结束，但存在失败项，请查看日志。
)
echo.
pause
exit /b %RC%
