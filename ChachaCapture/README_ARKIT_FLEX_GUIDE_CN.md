# ARKit 与模型 Flex 对应指南

这份指南说明如何把面捕输出的 ARKit/MediaPipe 通道，映射到模型自己的 Flex。适用于茶茶捕捉的“Flex 制作”工具，也适用于手动编辑 `data/facetracker/presets/*.txt`。

## 先理解两边的名字

映射永远是：

```text
ARKit 输入通道 -> 模型 Flex 输出
```

例如：

```text
jawOpen -> mouth_a
eyeBlinkLeft -> blink_l
```

左边是插件固定提供的标准通道，右边必须填写模型实际存在的 Flex 名称。`mouth_a`、`mouth_i`、`mouth_u` 等不是 ARKit 标准名称，而是模型作者自定义的目标 Flex。

插件当前提供的主要通道包括：

```text
眼睛：eyeBlinkLeft/Right、eyeLookUp/Down/In/OutLeft/Right、eyeWideLeft/Right、eyeSquintLeft/Right
眉毛：browDownLeft/Right、browInnerUp、browOuterUpLeft/Right
下颌：jawOpen、jawForward、jawLeft、jawRight
嘴部：mouthClose、mouthSmileLeft/Right、mouthFrownLeft/Right、mouthStretchLeft/Right
嘴形：mouthFunnel、mouthPucker、mouthPressLeft/Right、mouthDimpleLeft/Right
嘴唇上下：mouthUpperUpLeft/Right、mouthLowerDownLeft/Right、mouthRollUpper/Lower、mouthShrugUpper/Lower
其他：cheekPuff、cheekSquintLeft/Right、noseSneerLeft/Right、tongueOut
```

通道的输出通常是 `0` 到 `1`。制作器中的“权重”和“倍率”可以放大、减弱或反向这个值。

## 最重要的原则

1. 先确认模型 Flex 的真实名称。名称只要差一个字符就不会生效。
2. 先一条一条测试，不要一开始给一个 Flex 添加十几条映射。
3. 左右必须成对测试。模型的 `left`/`right` 有时是角色自身左右，有时是屏幕左右。
4. ARKit 没有直接的日语 `a/i/u/e/o` 通道。五个元音需要组合多个嘴部通道。
5. 同一个 Flex 可以叠加多条映射，但最终值会限制在 `0` 到 `2`；倍率过大容易让嘴形夸张或互相冲突。

## 日语五元音（あいうえお）推荐映射

下面假设模型有以下目标 Flex：`mouth_a`、`mouth_i`、`mouth_u`、`mouth_e`、`mouth_o`。如果模型名称不同，只替换右侧的目标 Flex 名称即可。

| 目标口型 | 推荐 ARKit 组合 | 可直接使用的表达式 | 口型说明 |
| --- | --- | --- | --- |
| `mouth_a` あ | `jawOpen`，可加少量 `mouthStretch` | `jawOpen*0.80 + mean(mouthStretchLeft,mouthStretchRight)*0.15` | 下巴打开，嘴型较宽 |
| `mouth_i` い | `mouthSmile` + `mouthStretch` + 少量 `mouthClose` | `mean(mouthSmileLeft,mouthSmileRight)*0.45 + mean(mouthStretchLeft,mouthStretchRight)*0.45 + mouthClose*0.10` | 嘴角向两侧拉，嘴唇不要过度张开 |
| `mouth_u` う | `mouthPucker` | `mouthPucker*0.85` | 嘴唇向前收圆 |
| `mouth_e` え | `mouthStretch` + `mouthSmile` + 少量 `jawOpen` | `mean(mouthStretchLeft,mouthStretchRight)*0.45 + mean(mouthSmileLeft,mouthSmileRight)*0.25 + jawOpen*0.25` | 比 い 更开、更扁 |
| `mouth_o` お | `mouthFunnel` + `mouthPucker` + 少量 `jawOpen` | `mouthFunnel*0.70 + mouthPucker*0.20 + jawOpen*0.15` | 嘴唇收圆，口腔打开 |

`mouth_a` 常用 `jawOpen` 是正确的起点，但不是绝对规则：有些模型的 A 口型还需要 `mouthStretch` 或 `mouthLowerDownLeft/Right` 才会显得自然。

### 在 Flex 制作器中添加五元音

以 `mouth_a` 为例：

1. 左侧找到并选中目标 Flex `mouth_a`。
2. 底部通道选择 `jawOpen`。
3. 权重先设为 `0.80`，倍率设为 `1.00`，阈值设为 `0.03`。
4. 点击“添加映射”。
5. 如果还要加嘴宽，再选择同一个 `mouth_a`，添加 `mouthStretchLeft` 和 `mouthStretchRight`，各使用 `0.075` 左右的权重。
6. 做出 A、I、U、E、O 后，用摄像头连续念一遍“あいうえお”，再逐个微调。

同一目标 Flex 的左右通道建议平均处理。例如：

```text
mouth_i <- mouthSmileLeft  x 0.225
mouth_i <- mouthSmileRight x 0.225
mouth_i <- mouthStretchLeft  x 0.225
mouth_i <- mouthStretchRight x 0.225
```

也可以在预设表达式中使用 `mean(...)`，两种写法效果相同。

## 眼睛映射

### 闭眼、睁眼和高光

| 模型 Flex | 推荐通道 | 说明 |
| --- | --- | --- |
| `blink_l` / `eye_close_l` | `eyeBlinkLeft` | 左眼闭合 |
| `blink_r` / `eye_close_r` | `eyeBlinkRight` | 右眼闭合 |
| `blink` | `mean(eyeBlinkLeft,eyeBlinkRight)` | 双眼同时闭合 |
| `eye_squint_l/r` | `eyeSquintLeft/Right` | 眯眼，不等同于闭眼 |
| `eye_wide_l/r` | `eyeWideLeft/Right` | 睁大眼 |
| `highlight_off` | `mean(eyeSquintLeft,eyeSquintRight,eyeBlinkLeft,eyeBlinkRight)*0.30` | 关闭或减弱高光的辅助口型 |

常见双眼闭合表达式：

```text
mean(eyeBlinkLeft,eyeBlinkRight)*0.95
```

如果模型的 `blink` 是“高值代表睁眼”而不是“高值代表闭眼”，需要勾选“反向”，或使用：

```text
1-mean(eyeBlinkLeft,eyeBlinkRight)
```

### 眼球视线

视线通常不是一个 Flex，而是模型的眼球骨骼、眼球目标或专用左右视线 Flex。常用通道如下：

```text
eyeLookUpLeft / eyeLookUpRight
eyeLookDownLeft / eyeLookDownRight
eyeLookInLeft / eyeLookInRight
eyeLookOutLeft / eyeLookOutRight
```

如果模型有 `look_up`、`look_down`、`look_left`、`look_right` 这类 Flex，可以先用左右平均值：

```text
look_up   <- mean(eyeLookUpLeft,eyeLookUpRight)
look_down <- mean(eyeLookDownLeft,eyeLookDownRight)
```

左右视线一定要在游戏里实际观察。若左右相反，交换 `eyeLookIn...` 与 `eyeLookOut...`，不要盲目修改 Python 程序。

## 眉毛、鼻子和脸颊

| 表情 | 推荐组合 |
| --- | --- |
| 双眉抬起 | `mean(browInnerUp,browOuterUpLeft,browOuterUpRight)*0.60` |
| 双眉压低/生气 | `mean(browDownLeft,browDownRight)*0.75` |
| 左眉抬起 | `mean(browInnerUp,browOuterUpLeft)*0.60` |
| 右眉抬起 | `mean(browInnerUp,browOuterUpRight)*0.60` |
| 鼻翼收缩 | `mean(noseSneerLeft,noseSneerRight)*0.50` |
| 鼓腮 | `cheekPuff*0.80` |
| 开心眯眼 | `mean(eyeSquintLeft,eyeSquintRight)*0.30` |

眉毛 Flex 往往是“抬起”和“压低”分开的两个形状。若模型只有一个 `brow`，可以分别测试正向和反向：

```text
brow <- browInnerUp*0.70
brow <- browDownLeft*-0.35
brow <- browDownRight*-0.35
```

## 嘴角、牙齿、舌头和下颌

| 模型 Flex | 推荐通道/组合 |
| --- | --- |
| 左嘴角上扬 | `mouthSmileLeft` |
| 右嘴角上扬 | `mouthSmileRight` |
| 双嘴角上扬 | `mean(mouthSmileLeft,mouthSmileRight)` |
| 左嘴角下压 | `mouthFrownLeft` |
| 右嘴角下压 | `mouthFrownRight` |
| 抿嘴 | `mean(mouthPressLeft,mouthPressRight)` |
| 露上牙 | `mean(mouthUpperUpLeft,mouthUpperUpRight)*0.70` |
| 拉宽嘴 | `mean(mouthStretchLeft,mouthStretchRight)` |
| 张嘴/下颌 | `jawOpen` |
| 下巴前伸 | `jawForward` |
| 下巴向左/右 | `jawLeft` / `jawRight` |
| 舌头伸出 | `tongueOut` |

“露牙”不要只用 `jawOpen`。`jawOpen` 表示张嘴，不表示上唇抬起；通常要叠加 `mouthUpperUpLeft/Right`，否则会变成张大黑嘴。

## 推荐制作顺序

1. 先做 `blink_l`、`blink_r` 和 `jaw_drop`，确认输入方向和模型响应正常。
2. 再做 `mouth_a`、`mouth_i`、`mouth_u`、`mouth_e`、`mouth_o` 五元音。
3. 加入嘴角、抿嘴、露牙和悲伤嘴。
4. 最后处理眉毛、眯眼、鼓腮、鼻子和舌头。
5. 每次只改一个目标 Flex，完成后再开始下一个。
6. 保存后用玩家面捕重新加载预设，确认重启游戏后仍然有效。

推荐初始参数：

| 参数 | 起始值 |
| --- | ---: |
| 权重 | `0.50` 到 `1.00` |
| 倍率 | `1.00` |
| 阈值 | `0.03` 到 `0.08` |
| 反向 | 默认关闭 |

## 常见问题

### 输入有数值，但模型完全不动

通常是目标 Flex 名称写错，或者选错了实体。先在制作器左侧用静态滑杆拖动该 Flex；静态滑杆也不动时，问题不在 ARKit 映射。

### 嘴巴总是半开

降低 `jawOpen` 权重，或提高阈值。也要检查是否把 `jawOpen` 同时映射到了 `mouth_a`、`mouth_e` 和普通 `jaw_drop`，多个目标 Flex 可能叠加出过大的开口。

### I 和 E 分不出来

I 应更偏“闭、扁、嘴角拉开”，E 应更偏“张开、扁宽”。降低 I 的 `jawOpen`，给 E 增加少量 `jawOpen`；不要只把同一条 `mouthSmile` 复制给两个口型。

### O 看起来像 U

给 O 增加 `mouthFunnel` 和少量 `jawOpen`，不要只用 `mouthPucker`。U 通常更窄、更向前，O 通常更圆、更打开。

### 左右眼或左右嘴角反了

先确认是在第三人称正面观察，还是在第一人称/镜像画面观察。确认后只交换对应的 `Left` 和 `Right` 通道，或者在制作器中勾选“反向”；不要同时交换所有通道。

### 预设能加载但 `mapped=0`

这表示当前模型没有找到任何同名 Flex。检查 JSON 左侧的 Flex 名称，必须与 `GetFlexName` 返回的名称完全一致，包括大小写、下划线和空格。

## 手动预设示例

下面是一个模型使用 `mouth_a`、`mouth_i`、`mouth_u`、`mouth_e`、`mouth_o` 和双眼闭合 Flex 时的最小示例：

```json
{
  "expressions": {
    "mouth_a": "jawOpen*0.80 + mean(mouthStretchLeft,mouthStretchRight)*0.15",
    "mouth_i": "mean(mouthSmileLeft,mouthSmileRight)*0.45 + mean(mouthStretchLeft,mouthStretchRight)*0.45 + mouthClose*0.10",
    "mouth_u": "mouthPucker*0.85",
    "mouth_e": "mean(mouthStretchLeft,mouthStretchRight)*0.45 + mean(mouthSmileLeft,mouthSmileRight)*0.25 + jawOpen*0.25",
    "mouth_o": "mouthFunnel*0.70 + mouthPucker*0.20 + jawOpen*0.15",
    "blink_l": "eyeBlinkLeft*0.95",
    "blink_r": "eyeBlinkRight*0.95"
  }
}
```

这只是起点，不是所有模型的最终答案。模型的口型拓扑、Flex 方向和作者命名不同，最终应以静态滑杆和实际念音测试为准。
