# 茶茶捕捉

本插件由哔哩哔哩UP主茶茶茶先森对 GitHub 开源项目 vlazed 大大的 gmod facetracker 项目改良而来，增加了player模式，pac3调整与头部骨骼捕捉、Flex编辑器等功能，并对日本二次元企划 BangDream It's MyGO!!!!! 中的角色做了专门的flex适配。意在推动二创作品更灵动的表达，谢谢你的喜欢！

插件提供两种工作方式：

- **玩家本体模式**：直接驱动当前玩家的面部 Flex 和头部骨骼，不需要工具枪选取实体。
- **NPC/布娃娃模式**：保留原版 Face Tracker 的工具枪流程，可把表情映射到 NPC 或布娃娃。

稳定重点是面部与头部捕捉；腰部、脊柱、手臂和手腕属于实验性的上半身功能，暂时未实装。摄像头仅在本地运行，请放心使用。

## Windows 快速开始
前提提要：你需要一台 64 位的 Windows 电脑，并预留至少 350mb 的存储空间。

1. 安装 64 位 Python 3.10（最稳定）。
   下载地址：
   `https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe`

2. 将文件`gmcl_gwsockets_win64.dll`放入：

   `GarrysMod\garrysmod\lua\bin `

3. 将整个 `ChachaCapture` 文件夹放入：

   `GarrysMod/garrysmod/addons`

4. 打开 Chachacapture，打开 server 文件夹，双击`install_player_windows.bat`，程序会开始自行安装所有所需的脚本，等到所有脚本安装完毕，按任意键关闭此窗口。
5. 确保你的 Windows 设备有摄像采集设备（没有实体摄像头时，可以使用 Iriun Webcam 等虚拟摄像头。运行 `server/list_cameras.bat` 查看编号，再用 `start_player_tracker.bat --camera 编号` 启动）。之后双击 server 文件夹中的`start_player_tracker.bat`，你的摄像头会被启用，并出现一个 640x480 的视频采集窗口。（请放心，我们不会收集您的个人信息，一切都在本地运行）。
6. 打开x64版本的 Garry's Mod 即可开始使用该插件。

详细安装、摄像头和多人同步说明见 [README_PLAYER_CN.md](README_PLAYER_CN.md)。骨骼映射说明见 [README_POSE_CN.md](README_POSE_CN.md)，自定义 Flex 预设见 [README_CUSTOM_PRESETS_CN.md](README_CUSTOM_PRESETS_CN.md)。

ARKit 与模型 Flex 的逐项对应、日语五元音（あいうえお）、眼睛和嘴部的推荐公式见 [README_ARKIT_FLEX_GUIDE_CN.md](README_ARKIT_FLEX_GUIDE_CN.md)。



## 致谢

- 原始项目：[vlazed/face-tracker](https://github.com/vlazed/face-tracker)
- GWSockets、MathParser、MediaPipe Face Landmarker
