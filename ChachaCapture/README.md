# 茶茶捕捉

由哔哩哔哩 UP 主茶茶茶先森改进的 GMod 面部与头部捕捉插件。

插件提供两种工作方式：

- **玩家本体模式**：直接驱动当前玩家的面部 Flex 和头部骨骼，不需要工具枪选取实体。
- **NPC/布娃娃模式**：保留原版 Face Tracker 的工具枪流程，可把表情映射到 NPC 或布娃娃。

稳定重点是面部与头部捕捉；腰部、脊柱、手臂和手腕属于实验性的上半身功能。摄像头始终只在本机处理，GMod 通过本机 WebSocket 接收数据。

## Windows 快速开始

1. 将整个 `ChachaCapture` 文件夹放入：

   `GarrysMod/garrysmod/addons/ChachaCapture`

   确认该目录下能直接看到 `lua` 文件夹。
2. 安装 64 位 Python 3.10（也支持 3.11/3.12），双击 `server/install_player_windows.bat`。
3. 双击 `server/start_player_tracker.bat`，再进入 GMod 的 `Poser → 茶茶捕捉`，点击“启动玩家捕捉”。
4. 第一次使用姿态捕捉时，正视镜头、自然放下手臂，点击“校准姿态”。

需要 GWSockets 客户端 DLL：`gmcl_gwsockets_win64.dll`，放入 `garrysmod/lua/bin/`。详细安装、摄像头和多人同步说明见 [README_PLAYER_CN.md](README_PLAYER_CN.md)。骨骼映射说明见 [README_POSE_CN.md](README_POSE_CN.md)，自定义 Flex 预设见 [README_CUSTOM_PRESETS_CN.md](README_CUSTOM_PRESETS_CN.md)。

ARKit 与模型 Flex 的逐项对应、日语五元音（あいうえお）、眼睛和嘴部的推荐公式见 [README_ARKIT_FLEX_GUIDE_CN.md](README_ARKIT_FLEX_GUIDE_CN.md)。

没有实体摄像头时，可以使用 Iriun Webcam 等虚拟摄像头。运行 `server/list_cameras.bat` 查看编号，再用 `start_player_tracker.bat --camera 编号` 启动。

## 方向规则

正式版固定按第三人称正面使用：左右方向镜像、上下方向同向。头部输入会自动转换到 GMod 骨骼轴；PAC3 面部 Flex 与头部骨骼可以分别启用和绑定。

## 致谢

- 原始项目：[vlazed/face-tracker](https://github.com/vlazed/face-tracker)
- GWSockets、MathParser、MediaPipe Face Landmarker
