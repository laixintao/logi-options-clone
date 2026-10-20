# Mouse Speed Keeper

macOS 上的轻量 Logitech DPI 恢复工具，无界面，不调用 Options+。使用系统 IOKit 和 HID++ 2.0 的 Adjustable DPI（0x2201）功能，不安装驱动或第三方依赖。

只保存并恢复选定鼠标的硬件 DPI；不修改 macOS 全局鼠标速度、触控板、按键、滚轮或键盘。以鼠标自身 Unit ID 匹配设备，避免接收器插槽变动后改错设备。若手动修改了 macOS 的指针速度，手感仍会变化。

## 构建与使用

需要 macOS 和 Xcode Command Line Tools。先让鼠标处于需要保留的速度，然后运行：

```sh
bash scripts/build.sh
.build/mouse-speed probe
.build/mouse-speed capture mouse-config.json
.build/mouse-speed apply mouse-config.json
bash scripts/install.sh
```

`capture` 仅在检测到一只支持的鼠标时保存配置。`apply` 写入后读回验证。安装脚本将可执行文件和配置复制到 `~/Library/Application Support/MouseSpeedKeeper/`，并安装当前用户的 LaunchAgent，在登录时自动启动。

后台每轮检查后休息 5 秒；离线设备的探测有超时，因此实际恢复可能需十几秒。重新枚举 USB 设备以应对接收器重插、鼠标开关和系统唤醒。仅在 DPI 与保存值不同时写入；鼠标离线时等待下次检查。未登录时不运行。

日志和状态：

```sh
launchctl print "gui/$(id -u)/local.mouse-speed-keeper"
cat "$HOME/Library/Application Support/MouseSpeedKeeper/agent.log"
cat "$HOME/Library/Application Support/MouseSpeedKeeper/error.log"
```

如果日志提示无法访问 HID，请检查系统设置 → 隐私与安全性 → 输入监控，必要时允许安装目录内的 `mouse-speed`，随后注销再登录。权限受 macOS 管理，不能由此工具绕过。

## 适用范围

本机验证目标：MX Anywhere 3S，经 Logi Bolt USB 接收器连接，DPI 为 2000。其他型号、蓝牙直连以及休眠/重连场景需要分别验证。仅支持提供 0x2201 和设备 Unit ID 的设备；不支持时报告错误，不猜测配置。

程序本身不依赖 Options+。安装脚本本身不会卸载或停止 Logitech 服务。如果 Options+ 同时运行且设置了不同 DPI，两者可能反复覆盖。Options+ 的按键映射等功能不由此工具替代。

本机配置时已另外退出 Options+，禁用并停止 `gui/503/com.logi.cp-dev-mgr` 和系统更新服务 `system/com.logi.optionsplus.updater`。原软件仍保留。退出原后台时实测 DPI 从 2000 重置为 1000，独立工具成功恢复并读回 2000。

2026-10-20 实机集成测试通过：Options+ 界面、配置后台及更新进程均停止后，将 DPI 从 2000 改为 2100，独立 LaunchAgent 自动恢复至 2000，再次读回确认。尚未执行真实重启、拔插接收器或睡眠唤醒测试。

若要恢复 Options+，先停用本工具，再运行（系统服务需要管理员权限）：

```sh
launchctl enable "gui/$(id -u)/com.logi.cp-dev-mgr"
launchctl bootstrap "gui/$(id -u)" /Library/LaunchAgents/com.logi.optionsplus.plist
sudo launchctl enable system/com.logi.optionsplus.updater
sudo launchctl bootstrap system /Library/LaunchDaemons/com.logi.optionsplus.updater.plist
```

`python3 scripts/check-recovery.py` 会短暂把 DPI 增加 100，检查后台自动恢复；退出时再次恢复原始值。运行前确保后台服务已安装，且鼠标已连接。这是实际硬件集成检查，会短暂改变速度。

修改保存的速度：先停止恢复程序，调整到目标速度，再捕获并重新安装。

```sh
launchctl bootout "gui/$(id -u)/local.mouse-speed-keeper"
# 调整鼠标速度后：
.build/mouse-speed capture mouse-config.json
bash scripts/install.sh
```

## 停用

```sh
bash scripts/uninstall.sh
```

停用脚本移除本工具的登录项，保留配置、可执行文件和日志；鼠标保持停用时的 DPI。不会更改 Logitech 原有登录项。
