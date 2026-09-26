# 茶茶捕捉：GMod 玩家面部与头部捕捉

茶茶捕捉提供面部、头部和上半身捕捉。骨骼映射与姿态细节见 [README_POSE_CN.md](README_POSE_CN.md)。

这个版本在原版 Face Tracker 上增加了“玩家模式”：无需工具枪选择 NPC 或布娃娃，面捕数据会直接驱动当前玩家模型，并可同步给同一服务器中的其他玩家。

## 已实现

- `LocalPlayer()` 自动成为面部和姿态捕捉目标。
- 兼容原版 `gmod_facetracker.py` 的 53 项有序数组协议。
- 兼容外部追踪器使用的键名 JSON 协议。
- 玩家切换模型后自动重新匹配 Flex。
- PAC3 头部目标模式：可扫描并驱动靠近玩家头部、拥有 Flex 的 PAC3 客户端模型，而不是被隐藏的原始玩家模型。
- PAC3 手动绑定：可在 Q 菜单中选择具体模型实体和头部骨骼，避免同一 PAC3 Outfit 有多个模型时自动选错。
- 强度、平滑速度、同步帧率和自动重连设置。
- 只允许玩家向服务器提交自己的表情，不能修改其他玩家或任意实体。
- 8 位量化多人同步，默认每秒 30 帧（服务器上限也默认为 30）。
- 摄像头画面只在本机处理；WebSocket 只监听 `127.0.0.1`。

## Windows 安装

### 1. 放置插件

整个 `ChachaCapture` 文件夹应放到：

```text
...\Steam\steamapps\common\GarrysMod\garrysmod\addons
```

安装后完全退出并重启 GMod，控制台应出现：

```text
茶茶捕捉已加载（面部 + 头部；PAC3 兼容优化）
```

GWSocketsd DLL 名称应为
`gmcl_gwsockets_win64.dll`，放在 `garrysmod/lua/bin/`，并使用 64 位 Garry's Mod。

### 2. 安装 Python 3.10（推荐）

推荐使用你原来已经验证过的 64 位 Python 3.10，并使用下面的独立 `.venv-player` 环境。安装脚本会依次尝试 64 位 Python 3.10、3.11、3.12；依赖会自动选择当前镜像中可用的 MediaPipe 0.10.x 版本，不再固定到已经下架的 0.10.21。

双击：

```text
server\install_player_windows.bat
```

或者在 `server` 文件夹打开 CMD，手动运行：

```bat
py -3.10 -m venv .venv-player
.venv-player\Scripts\activate
python -m pip install --upgrade pip
python -m pip install -r requirements-player.txt
```

### 3. 启动

1. 双击 `server\start_player_tracker.bat`。启动脚本默认请求 640x480、30 FPS；腰部、双臂和双腕目前属于实验功能。
2. 进入 GMod 地图，拿出工具枪，在 `Poser → 茶茶捕捉` 打开工具面板。
3. 在面板顶部的“玩家本体模式”分类中点击“启动玩家捕捉”，然后保持自然姿势点击“校准姿态”。这里不需要右键选择 NPC 或布娃娃；原来的实体模式仍然保留。

也可以使用备用入口：`Q 菜单 → Utilities → User → 茶茶捕捉`。

`8667` 端口一次只能运行一个 Python WebSocket 服务：玩家模式使用 `player_tracker.py`，NPC/布娃娃模式使用 `gmod_facetracker.py`，两者不要同时启动。
从仅头部模式切换到完整上半身模式时，也必须先按 `Q` 关闭仅头部窗口，否则端口和摄像头仍会被它占用。

也可以在 GMod 控制台输入：

```text
face_tracker_start
```

如果控制台提示 `unknown command`，说明 addon 的 Lua autorun 没有加载。请先检查上面的目录层级和控制台加载标记，再完全重启 GMod；摄像头 Python 窗口启动成功并不代表 GMod addon 已加载。

停止：

```text
face_tracker_stop
```

查看连接、预设和 Flex 匹配数量：

```text
facetracker_player_status
```

高级用户仍可在控制台使用 `facetracker_player_dumpflexes` 导出当前玩家模型的 Flex 名称，输出文件位于 `garrysmod\data\facetracker\player_flexes.txt`。

## 摄像头问题

摄像头窗口使用 ASCII 字体显示标题和状态文字，避免 Windows/OpenCV 的中文字体乱码。默认打开摄像头 `0`。

如果你使用 Iriun Webcam、OBS Virtual Camera 或其他虚拟摄像头，先确认它已经在 Windows 的“相机”应用中出现，然后双击：

```text
server\list_cameras.bat
```

脚本会列出 OpenCV 能看到的摄像头编号。把 Iriun 对应的编号填入启动参数，例如：

```bat
start_player_tracker.bat --camera 1
```

Iriun 在 OpenCV 中会表现为普通摄像头，不需要在 GMod 里额外安装插件；手机端和 Windows 端 Iriun Webcam 驱动正常连接后，选择它的编号即可。

请确认 Windows 的“隐私和安全性 → 摄像头”允许桌面应用访问摄像头。

修复版会依次尝试 DirectShow、Media Foundation 和自动摄像头后端。完整模式会先加载 Pose 标准模型，失败时自动重试轻量模型；若 Pose 仍失败，摄像头窗口会继续以面部与头部模式运行，并把具体原因显示在命令行中。

Hotfix 2 使用内存方式加载 `face_landmarker.task`，以避开 MediaPipe 0.10.x 在 Windows 盘符绝对路径上的 `site-packages/D:\...` 拼接错误。

正式版默认采集 640x480（480p），并以 30 FPS 目标运行，优先保证实际响应达到 24 FPS 以上。需要更宽画幅时，可在启动命令后追加 `--width 1280 --height 720` 或 `--width 1920 --height 1080`；识别输入仍会按 `--processing-width 480` 等比例缩小。人体 Pose 使用未镜像画面识别，预览再镜像显示。默认硬规则是左右镜像、上下不镜像，真人左侧会驱动角色视觉右侧；上臂限制在身体前半球和两侧，避免从后方翻转。

## 使用自定义 Flex 预设

新手制作模型专属 Flex 映射，请先阅读 [README_FLEX_CREATOR_CN.md](README_FLEX_CREATOR_CN.md)。

原版界面保存的预设通常位于：

```text
garrysmod\data\facetracker\presets\你的预设名.txt
```

在玩家面捕面板的“预设”输入框填写文件名（不要填写 `.txt`），或使用控制台：

```text
facetracker_player_preset 你的预设名
```

`auto` 会先扫描 `garrysmod/data/facetracker/presets/` 中你保存的预设，再比较内置的 `facs`、`hwm`、`arkit`。如果有多个自定义预设，建议明确填写名称以避免选错。

### PAC3 换头面捕

在 Q 菜单的“茶茶捕捉”中，分别使用“面部表情使用 PAC3（Flex）”和“头部骨骼使用 PAC3”两个开关。它们互不影响：例如打开前者、关闭后者，就是 PAC3 头部负责面部表情，而原玩家实体负责头部动作。插件会优先读取 PAC3 部件，并备用扫描玩家头部附近带 Flex 的客户端模型；状态命令会分别显示 `face_target` 和 `pose_target`。高级用户也可以输入：

```text
facetracker_player_pac3_target
```

PAC3 头部模型必须拥有 Flex。头部姿态会同时尝试应用到 PAC3 头部的骨骼；关闭选项后会恢复驱动玩家原始模型。

手动绑定流程：在“PAC3 手动绑定”区域点击“刷新候选模型”，选择具体模型后，再在第二个下拉框选择它的头部骨骼。选择模型只保存目标，不会自动打开任一开关；请按需要单独打开面部或姿态开关。点击“恢复自动选择”即可取消实体和骨骼锁定。

对应的控制台变量是：

```text
facetracker_player_face_pac3 0/1   # 面部 Flex 是否驱动 PAC3
facetracker_player_pose_pac3 0/1   # 头部、颈部、腰部和身体骨骼是否驱动 PAC3
facetracker_player_pac3_target_ent 0   # 0 为自动选择，也可填实体编号
facetracker_player_pac3_head_bone ""   # 姿态目标的头部骨骼名
```

“第三人称正面”使用正式版方向规则：头部左右反向、上下同向；眼睛沿用内置映射，不在正式 UI 中提供额外镜像开关。高级用户仍可通过控制台调整姿态镜像：

```text
facetracker_player_pose_mirror_horizontal 1
facetracker_player_pose_mirror_vertical 0
facetracker_player_eye_mirror_horizontal 1
facetracker_player_eye_mirror_vertical 0
```

头部姿态的轴向已经单独处理：头部/颈部的 X 与 Z 输入会先互换到正确的 GMod 骨骼轴，再同时反向；头部 Y（上下）始终保持同向。这个修正只作用于头部和颈部，不会改变眼睛目标，也不会改变腰部和手臂的轴向规则。

预设格式沿用原项目：

```json
{
  "expressions": {
    "jaw_drop": "jawOpen",
    "left_lid_closer": "eyeBlinkLeft",
    "right_lid_closer": "eyeBlinkRight"
  },
  "eyeExpressions": {
    "x": "0.5 + (mean(eyeLookOutRight,eyeLookInLeft)-mean(eyeLookOutLeft,eyeLookInRight))*0.75",
    "y": "0.5 + (-mean(eyeLookUpRight,eyeLookUpLeft)+mean(eyeLookDownRight,eyeLookDownLeft))*0.75"
  }
}
```

JSON 左侧必须与玩家模型实际的 Flex 名称完全一致。若状态显示 `mapped=0`，说明当前预设不适用于该模型。

## 多人游戏

- 服务端必须安装这个 addon，才能接收和转发表情。
- 想看到表情的客户端也必须安装这个 addon。
- 每个使用面捕的玩家在自己的电脑上运行 Python 程序和 GWSockets。
- 服务器可使用 `sv_facetracker_player_enabled 0` 全局关闭玩家面捕。
- `sv_facetracker_player_maxrate` 控制服务器接受的最高同步帧率，默认 30。

原版工具枪在单人游戏中仍可用于 NPC/布娃娃。多人服务器默认禁止它修改发送者以外的实体；管理员只有明确设置 `sv_facetracker_legacy_entities 1` 才会恢复旧行为。
