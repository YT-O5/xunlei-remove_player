param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$scriptDir = $PSScriptRoot
$backupDir = Join-Path $scriptDir 'registry-backup'
$logPath = Join-Path $scriptDir 'uninstall-thunder-player.log'
$fail = 0

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -LiteralPath $logPath -Value $Message -Encoding UTF8
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ThunderInstallDir {
    $candidates = @()

    $regPaths = @(
        'HKLM:\SOFTWARE\WOW6432Node\Thunder Network\ThunderOem\thunder_backwnd',
        'HKLM:\SOFTWARE\Thunder Network\ThunderOem\thunder_backwnd'
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path -LiteralPath $regPath) {
            $dir = (Get-ItemProperty -LiteralPath $regPath -Name 'dir' -ErrorAction SilentlyContinue).dir
            if ($dir) { $candidates += $dir }
        }
    }

    $command = (Get-ItemProperty -LiteralPath 'Registry::HKEY_CLASSES_ROOT\thunder\Shell\Open\command' -ErrorAction SilentlyContinue).'(default)'
    if ($command -match '"([^"]+)"') {
        $exePath = $matches[1]
        $candidates += (Split-Path -Parent (Split-Path -Parent $exePath))
    }

    $candidates += @(
        'C:\Program Files (x86)\Thunder Network\Thunder',
        'C:\Program Files\Thunder Network\Thunder',
        'D:\Thunder Network\Thunder'
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'program\thunder.exe'))) {
            return $candidate
        }
    }
    return $null
}

function Backup-Key {
    param([string]$RegPath, [string]$FileName)
    if ($DryRun) {
        Write-Log "[预览] 备份注册表键 $RegPath"
        return
    }
    if (-not (Test-Path -LiteralPath "Registry::$RegPath")) { return }
    $file = Join-Path $backupDir "$FileName.reg"
    & reg.exe export "$RegPath" "$file" /y 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "[备份] $FileName.reg"
    } else {
        Write-Log "[警告] 备份失败: $RegPath"
    }
}

function Remove-RegKey {
    param([string]$RegPath)
    if ($DryRun) {
        Write-Log "[预览] 删除键 $RegPath"
        return
    }
    & reg.exe delete "$RegPath" /f 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "[成功] 删除键 $RegPath"
    } else {
        Write-Log "[失败] 删除键 $RegPath"
        $script:fail++
    }
}

function Remove-RegValue {
    param([string]$RegPath, [string]$ValueName)
    if ($DryRun) {
        Write-Log "[预览] 删除值 $RegPath\$ValueName"
        return
    }
    & reg.exe delete "$RegPath" /v "$ValueName" /f 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "[成功] 删除值 $RegPath\$ValueName"
    } else {
        Write-Log "[失败] 删除值 $RegPath\$ValueName"
        $script:fail++
    }
}

function Get-ThunderProgIds {
    param([string]$ClassesPsPath)
    if (-not (Test-Path -LiteralPath $ClassesPsPath)) { return @() }
    return @(Get-ChildItem -LiteralPath $ClassesPsPath -ErrorAction SilentlyContinue |
        Where-Object {
            $_.PSChildName -like 'thunder.*' -and
            $_.PSChildName -notlike 'Thunder.MyComputerIcon*'
        })
}

function Clear-ExtAssociations {
    param([string]$ClassesPsPath, [string]$ClassesRegPrefix)
    if (-not (Test-Path -LiteralPath $ClassesPsPath)) { return }
    $count = 0
    Get-ChildItem -LiteralPath $ClassesPsPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like '.*' } |
        ForEach-Object {
            $ext = $_.PSChildName
            $openWithProgids = Join-Path $_.PSPath 'OpenWithProgids'
            if (Test-Path -LiteralPath $openWithProgids) {
                $item = Get-Item -LiteralPath $openWithProgids
                foreach ($valueName in @($item.GetValueNames())) {
                    if ($valueName -like 'thunder.*') {
                        Remove-RegValue "$ClassesRegPrefix\$ext\OpenWithProgids" $valueName
                        $count++
                    }
                }
            }
            $openWithList = Join-Path $_.PSPath 'OpenWithList\thunder.exe'
            if (Test-Path -LiteralPath $openWithList) {
                Remove-RegKey "$ClassesRegPrefix\$ext\OpenWithList\thunder.exe"
                $count++
            }
        }
    Write-Log "[信息] $ClassesRegPrefix 下清理文件关联 $count 项。"
}

function Clear-FileExts {
    $base = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts'
    if (-not (Test-Path -LiteralPath $base)) { return }
    $count = 0
    Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | ForEach-Object {
        $ext = $_.PSChildName
        $openWithList = Join-Path $_.PSPath 'OpenWithList'
        if (Test-Path -LiteralPath $openWithList) {
            $item = Get-Item -LiteralPath $openWithList
            foreach ($valueName in @($item.GetValueNames())) {
                if ($valueName -ne 'MRUList' -and $item.GetValue($valueName) -eq 'thunder.exe') {
                    if ($DryRun) {
                        Write-Log "[预览] 删除 FileExts\$ext\OpenWithList\$valueName"
                    } else {
                        Remove-ItemProperty -LiteralPath $openWithList -Name $valueName -Force -ErrorAction SilentlyContinue
                        Write-Log "[成功] 删除 FileExts\$ext\OpenWithList\$valueName"
                    }
                    $count++
                }
            }
        }
        $userChoice = Join-Path $_.PSPath 'UserChoice'
        if (Test-Path -LiteralPath $userChoice) {
            $progId = (Get-ItemProperty -LiteralPath $userChoice -Name 'ProgId' -ErrorAction SilentlyContinue).ProgId
            if ($progId -like 'thunder.*') {
                if ($DryRun) {
                    Write-Log "[预览] 清除默认关联 $ext (ProgId=$progId)"
                } else {
                    Remove-Item -LiteralPath $userChoice -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "[成功] 清除默认关联 $ext (ProgId=$progId)"
                }
                $count++
            }
        }
    }
    Write-Log "[信息] FileExts 下清理关联 $count 项。"
}

function Stop-ThunderProcesses {
    $names = @('thunder', 'xllite', 'ThunderStart', 'XLLiveUD', 'ThunderRepair')
    foreach ($name in $names) {
        $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        foreach ($process in $processes) {
            if ($DryRun) {
                Write-Log "[预览] 结束进程 $($process.ProcessName) (PID $($process.Id))"
            } else {
                try {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    Write-Log "[成功] 结束进程 $($process.ProcessName) (PID $($process.Id))"
                } catch {
                    Write-Log "[失败] 无法结束 $($process.ProcessName): $($_.Exception.Message)"
                    $script:fail++
                }
            }
        }
    }
}

if (-not $DryRun -and -not (Test-Admin)) {
    Write-Host '[错误] 请以管理员身份运行此脚本。'
    exit 1
}

Write-Log '=========================================='
Write-Log '迅雷内置播放器卸载脚本'
Write-Log '=========================================='
if ($DryRun) {
    Write-Log '[预览模式] 不会修改注册表或文件。'
}

$installDir = Get-ThunderInstallDir
if (-not $installDir) {
    Write-Log '[警告] 未能自动定位迅雷安装目录。'
    $installDir = Read-Host '请输入迅雷安装目录（例如 D:\Thunder Network\Thunder）'
    $installDir = $installDir.Trim('"').TrimEnd('\')
}
if (-not (Test-Path -LiteralPath (Join-Path $installDir 'program\thunder.exe'))) {
    Write-Log "[错误] 目录中未找到 program\thunder.exe: $installDir"
    exit 2
}
Write-Log "[信息] 迅雷安装目录: $installDir"

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
}

Write-Log ''
Write-Log '[1/4] 备份相关注册表...'
Backup-Key 'HKLM\Software\Classes\Applications\thunder.exe' 'Applications_thunder.exe'
Backup-Key 'HKLM\Software\Classes\*\shellex\ContextMenuHandlers\ThunderPlayShell' 'ThunderPlayShell'
Backup-Key 'HKLM\Software\Classes\CLSID\{B5C2806D-20A3-49A0-A123-A96D0F0D1682}' 'ThunderPlayShell_CLSID'

$machineProgIds = @(Get-ThunderProgIds 'HKLM:\Software\Classes')
foreach ($key in $machineProgIds) {
    Backup-Key "HKLM\Software\Classes\$($key.PSChildName)" "progid_$($key.PSChildName)"
}
$userProgIds = @(Get-ThunderProgIds 'HKCU:\Software\Classes')
foreach ($key in $userProgIds) {
    Backup-Key "HKCU\Software\Classes\$($key.PSChildName)" "progid_user_$($key.PSChildName)"
}

Write-Log ''
Write-Log "[2/4] 解除播放器对系统的接管（$($machineProgIds.Count + $userProgIds.Count) 个 ProgId）..."
foreach ($key in $machineProgIds) {
    Remove-RegKey "HKLM\Software\Classes\$($key.PSChildName)"
}
foreach ($key in $userProgIds) {
    Remove-RegKey "HKCU\Software\Classes\$($key.PSChildName)"
}

Remove-RegKey 'HKLM\Software\Classes\Applications\thunder.exe'
Remove-RegKey 'HKCU\Software\Classes\Applications\thunder.exe'
Remove-RegKey 'HKLM\Software\Classes\*\shellex\ContextMenuHandlers\ThunderPlayShell'
Remove-RegKey 'HKCU\Software\Classes\*\shellex\ContextMenuHandlers\ThunderPlayShell'
Remove-RegKey 'HKLM\Software\Classes\CLSID\{B5C2806D-20A3-49A0-A123-A96D0F0D1682}'
Remove-RegKey 'HKCU\Software\Classes\CLSID\{B5C2806D-20A3-49A0-A123-A96D0F0D1682}'

Clear-ExtAssociations 'HKLM:\Software\Classes' 'HKLM\Software\Classes'
Clear-ExtAssociations 'HKCU:\Software\Classes' 'HKCU\Software\Classes'
Clear-FileExts

Write-Log ''
Write-Log '[3/4] 结束迅雷进程...'
$running = @(Get-Process -Name 'thunder', 'xllite' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0 -and -not $DryRun) {
    Write-Log '[提示] 检测到迅雷正在运行。继续将结束迅雷进程，当前下载任务会中断（可断点续传）。'
    $answer = Read-Host '是否继续？[Y/N]'
    if ($answer -notmatch '^[Yy]') {
        Write-Log '用户取消操作。'
        exit 1
    }
}
Stop-ThunderProcesses
Start-Sleep -Seconds 2

Write-Log ''
Write-Log '[4/4] 跳过播放器内核文件。'
Write-Log '[说明] 迅雷主程序启动时会加载 player_helper.node 和 APlayer.dll，'
Write-Log '       用空文件替换会导致“损坏的映像”或无法启动。'
Write-Log '       因此本脚本只解除系统接管，不修改播放器文件。'

Write-Log ''
Write-Log '=========================================='
if ($fail -eq 0) {
    Write-Log '卸载完成。'
} else {
    Write-Log "卸载完成，但有 $fail 项失败。"
}
Write-Log "安装目录: $installDir"
Write-Log "备份目录: $backupDir"
Write-Log '提示：迅雷更新或修复后可能重新创建播放器组件和文件关联，需要重新运行本脚本。'
Write-Log '提示：建议重启电脑或注销，使右键菜单和默认应用设置生效。'
if ($DryRun) {
    Write-Log '这是预览模式，未做任何修改。'
}
if ($fail -eq 0) { exit 0 } else { exit 1 }
