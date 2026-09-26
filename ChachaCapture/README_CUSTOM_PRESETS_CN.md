# Tomorin / Anon 灵动表情预设

已附带两个独立预设：

- `data_static/facetracker/presets/tomorin_expressive.txt`
- `data_static/facetracker/presets/anon_expressive.txt`

安装插件后，将对应文件复制到：

```text
garrysmod/data/facetracker/presets/
```

然后在玩家面捕界面的预设输入框填写 `tomorin_expressive` 或 `anon_expressive`，也可以在控制台输入：

```text
facetracker_player_preset tomorin_expressive
```

这些预设使用 ARKit/MediaPipe 的 53 个标准通道计算模型自己的 Flex。左右眼方向、上下视线和 `eyeExpressions` 使用同一套镜头坐标逻辑；如果某个模型的左右眼显示相反，只需要在预设中交换 `eye left` / `eye right` 两行，不需要改 Python 捕捉程序。

实际效果仍取决于模型 Flex 的语义：截图中名称是作者自定义的，所以“mouth e”“goofy smile”等是根据名称和常见 VRM/Live2D 命名推断的组合，强度可在文件中把末尾倍率调高或调低。
