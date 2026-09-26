# 茶茶捕捉：姿态捕捉说明

对于上半身捕捉，我现在有另一个想法，单纯用骨骼追踪和IK链难以实现，未来会进一步研发。
摄像头图像仍然只在本机处理，GMod 通过本机 WebSocket 接收表情系数和骨骼角度。当前版本的稳定重点仍是面部与头部；上半身其余部位请按实验功能使用。

## 捕捉范围

- 完整的 53 项 MediaPipe 面部 Blendshape。
- 头部三轴旋转与颈部跟随。
- 上半身：腰部/骨盆、脊柱、左右锁骨/肩、左右上臂、左右前臂、左右手腕/手。
- 首帧自动校准，也可以随时手动重新校准。
- 停止、断线、超时或关闭姿态捕捉时自动复原骨骼。
- 姿态数据支持多人同步；服务端仍只允许玩家提交自己的姿态。

当前内置了以下标准 ValveBiped 骨骼映射预设：

```text
ValveBiped.Bip01_Head1
ValveBiped.Bip01_Neck1
ValveBiped.Bip01_Pelvis
ValveBiped.Bip01_Spine
ValveBiped.Bip01_Spine2
ValveBiped.Bip01_L_Clavicle
ValveBiped.Bip01_L_UpperArm
ValveBiped.Bip01_L_Forearm
ValveBiped.Bip01_L_Hand
ValveBiped.Bip01_R_Clavicle
ValveBiped.Bip01_R_UpperArm
ValveBiped.Bip01_R_Forearm
ValveBiped.Bip01_R_Hand
```

骨骼映射和 Flex 预设一样是独立文件，不需要修改 Lua。内置文件位于插件的
`data_static/facetracker/bones/valvebiped.txt`；你保存的自定义文件位于：

```text
garrysmod/data/facetracker/bones/你的预设名.txt
```

文件格式示例：

```json
{
  "version": 1,
  "displayName": "我的模型",
  "bones": {
    "head": "my_head_bone",
    "neck": "my_neck_bone",
    "spine": "my_spine_bone",
    "left_upper_arm": "my_left_arm",
    "left_forearm": "my_left_forearm",
    "right_upper_arm": "my_right_arm",
    "right_forearm": "my_right_forearm"
  }
}
```

插件会自动跳过当前模型不存在的骨骼。工具面板状态中的 `骨骼：12/12` 表示标准骨骼全部匹配。

## 启动

依赖与第一版相同，推荐 64 位 Python 3.10。更新插件后不需要重新安装依赖；首次安装仍然双击：

```text
server\install_player_windows.bat
```

完整捕捉模式：

```text
server\start_player_tracker.bat
```

面部、头部和上半身捕捉统一使用 `server\start_player_tracker.bat`，端口为 `8667`。

程序会在 Windows 上依次尝试 DirectShow、Media Foundation 和自动摄像头后端。完整模式的 Pose 标准模型若初始化失败，会自动重试轻量模型；如果两者都失败，窗口仍会以“面部 + 头部”模式打开，并在命令行显示具体错误。完整模式打不开时，请先彻底关闭其他可能占用摄像头的程序。

Hotfix 2 不再把 `face_landmarker.task` 的 Windows 盘符路径直接交给 MediaPipe，而是读取模型内容后加载。这修复了 MediaPipe 把 `D:\...` 错误拼接成 `site-packages/D:\...` 并报 `errno=22` 的问题，同时修正了上下点头方向。

脊柱、左右上臂、左右前臂、腰部/骨盆、双锁骨和双腕会分别判定可见度，摄像头预览会显示 `body N/10`，GMod 面板会分别显示 `身体通道 N/10` 与 `骨骼 N/12`，用于区分识别问题和骨骼名称问题。本版使用未镜像画面识别 Pose；默认身体通道按第三人称视觉交换左右。

程序会用未镜像的原始画面识别人体左右，只把镜像用于预览。默认硬规则是：左右镜像、上下不镜像、头部/腰部水平转向反向，而手臂抬高和手掌前后方向保持一致；真人左侧会驱动角色视觉右侧。上臂被限制在身体前半球和两侧活动，禁止从身体后方翻转 180 度；前臂会按肘到手腕的实际方向分解俯仰和前后。默认摄像头请求 640x480（480p）并以 30 FPS 目标运行，以优先保证至少 24 FPS；Face 和 Pose 会并行处理；需要更宽画幅时可追加 `--width 1280 --height 720` 或 `--width 1920 --height 1080`，识别输入仍按 480 像素宽处理。

## GMod 操作

1. 完全重启 GMod，进入地图。
2. 拿出工具枪，选择 `Poser → 茶茶捕捉`。
3. 点击“启动玩家捕捉”。
4. 正视镜头，让头、肩、双肘和双手腕进入画面，双臂自然下垂。
5. 点击“校准姿态”，保持自然姿势一秒钟。
6. 切换第三人称观察自己的头部和手臂动作。

玩家模式面板中的“骨骼映射预设”可以直接编辑这 12 个槽位（含腰部/骨盆、双锁骨、双腕）。填写模型实际骨骼名后点击“应用当前骨骼映射”，再填写预设名称点击“保存为骨骼预设”。之后把预设输入框设为该名称即可加载。

面板状态应类似：

```text
状态：运行中，桥接：已连接，Flex：53，姿态：已捕捉，身体通道：10/10，骨骼：12/12
```

## 姿态设置

- `启用姿态捕捉`：总开关，仅关闭骨骼，不影响面部。
- `头部与颈部`：只控制头和颈。
- `腰部、脊柱、双臂与双腕`：控制实验性上半身。
- `姿态幅度`：动作太小可提高，抖动或幅度过大可降低。修复版默认值为 `1.25`。
- `姿态平滑速度`：数值越大反应越快，越小越平稳。修复版默认值为 `24`。
- `校准姿态`：把当前自然姿势设为零点。

控制台也可以执行：

```text
facetracker_player_pose_calibrate
facetracker_player_pose_reset
facetracker_player_dumpbones
```

骨骼列表会写入 `garrysmod/data/facetracker/player_bones.txt`，可以用于下一步制作非标准模型骨骼映射。

## 摄像头构图

面部与头部模式只需要清楚看到脸。上半身通道会独立工作：只看到一只手臂时，仍会驱动这一侧；腰部/脊柱在双肩可见时也会尝试输出。建议把摄像头放远一些，让肩、肘和手腕尽量保持在画面内。预览窗口中的绿色姿态连线可用于确认识别情况。

正式版固定使用第三人称正面规则：左右方向镜像、上下方向同向；面板不再提供容易混淆的眼睛镜像开关。`--no-mirror` 只用于排查摄像头方向，会同时关闭预览和 Face 输入镜像；Pose 始终使用未镜像画面识别：

```bat
.venv-player\Scripts\python.exe player_tracker.py --preview --no-mirror
```

## 当前限制

- 上半身骨骼轴向在非标准玩家模型上可能不同；这类模型需要后续单独建立骨骼映射预设。
- 骨骼旋转叠加在当前玩家动画上，武器持枪动画可能限制或覆盖一部分手臂动作。
- 当前没有手指细节、肩胛和角色位置移动捕捉；手腕使用手掌关键点进行基础估算，腰部使用髋部/肩部姿态进行倾斜估算。480p 模式以流畅度优先，预览清晰度会低于 1080p。
- 第一人称通常看不到自己的头和身体，请在第三人称或让其他玩家观察。
- 头部捕捉使用面部变换矩阵，稳定性通常高于实验性手臂捕捉。
