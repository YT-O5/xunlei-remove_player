# xunlei-remove_player

解除迅雷内置播放器对视频/音频文件系统接管的 Windows 脚本。

## 背景

迅雷没有独立的播放器 exe，播放功能集成在 `thunder.exe`，播放器内核位于 `program\player`（`APlayer.dll` 等）。`player_helper.node` 是主程序启动时 `require` 的 native addon，`APlayer.dll` 也会在启动过程中被加载。

因此**不能**用删除、重命名或空文件替换这些文件：迅雷会报“找不到模块”或“损坏的映像”，甚至无法启动。本脚本只清理系统层面的播放器接管，不修改迅雷程序文件。

## 包含脚本

| 文件 | 作用 |
| --- | --- |
| `uninstall-thunder-player.bat` | 启动器，检查管理员权限并调用 PowerShell 脚本 |
| `uninstall-thunder-player.ps1` | 清理注册表关联和右键菜单 |

两个文件必须放在同一目录。

## 使用方法

1. 退出迅雷（包括托盘图标和正在进行的下载任务）。
2. 右键 `uninstall-thunder-player.bat`，选择“以管理员身份运行”。
3. 按提示确认。脚本会结束迅雷进程（如有），当前下载会中断，之后可断点续传。
4. 重启电脑或注销，使右键菜单和默认应用设置生效。

## 脚本做什么

- 备份相关注册表到 `registry-backup`。
- 删除 `HKLM\Software\Classes\Applications\thunder.exe`（“使用迅雷播放器播放”打开方式）。
- 删除右键菜单扩展 `ThunderPlayShell` 及其 CLSID。
- 删除约 100 个 `thunder.*` 媒体 ProgId（保留 `Thunder.MyComputerIcon`）。
- 清理各扩展名的 `OpenWithProgids\thunder.*`、`OpenWithList\thunder.exe`。
- 清理 `HKCU\...\FileExts` 中的迅雷打开方式和默认关联。
- **不修改** `program\player`、`player_helper.node`、`APlayer.dll`。

`thunder://` 协议和迅雷下载功能不受影响。

## 注意事项

- 迅雷更新或“修复”后可能重新注册文件关联，需要重新运行脚本。
- 如果只想让某个视频格式恢复默认播放器，可在 Windows“设置 → 应用 → 默认应用”中重新选择。
- 恢复注册表：右键以管理员身份导入 `registry-backup` 中对应的 `.reg` 文件。
- `.bat` 使用 GBK/ANSI 编码，`.ps1` 使用 UTF-8 BOM；请在 Windows 上运行。
- 不要尝试删除/重命名 `player_helper.node`，也不要把 `APlayer.dll` 替换成空文件，否则迅雷会无法启动。

## 免责声明

本脚本仅用于清理自己电脑上的迅雷播放器接管。修改注册表有风险，请先备份或创建系统还原点。使用本脚本造成的任何后果由使用者自行承担。

## 许可

本仓库未声明开源许可证。转载或分发时请保留本仓库地址。
