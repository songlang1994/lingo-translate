# Lingo Translate

macOS 菜单栏翻译工具。全局快捷键唤起浮动面板，调用 Responses 风格的大模型接口完成翻译。

- 使用大模型翻译，系统提示词内置于应用
- 左右两栏：左侧是可自由编辑的原文，排版保持原样；右侧是译文，由模型划分逻辑段落并逐段对齐
- 点击任一段落，原文与对应译文同时以淡色高亮（原文浅蓝、译文浅粉），便于对照
- 在别的应用选中文本后唤起面板，自动把选中的文字填入原文并翻译
- 原文为空或全选后粘贴会自动开始翻译；手动编辑原文不会自动翻译，正在进行的请求也不会中断
- 译文在右侧流式输出，生成过程中可随时停止；原文被编辑后译文以浅色显示，等待手动翻译
- 开始翻译时视图回到顶部，粘贴长文后也能从第一段看到译文实时输出
- 同一时间只有一侧保留选中的文本：在一侧选择或放置光标，另一侧的选中立即取消
- 界面只有语言选择、交换、翻译/停止/清空、复制、设置几类控件
- 菜单栏常驻，不占用 Dock
- 原生 Swift + SwiftUI / AppKit，无第三方依赖
- 交互形式参考 [m-inan/mac-translate](https://github.com/m-inan/mac-translate)

## 环境

- macOS 14 或更新版本
- Xcode 16 或更新版本

## 构建与运行

```bash
make run          # 构建 Debug 并启动
make test         # 运行单元测试
make release      # 构建 Release 并打包 dist/Lingo Translate.zip
make install      # 构建 Release 并复制到 /Applications
```

也可以直接用 Xcode 打开 `Lingo.xcodeproj`，选择 Lingo scheme 运行。

## 首次配置

首次启动只显示设置窗口，填入以下内容即可使用：

| 项目 | 说明 | 示例 |
| --- | --- | --- |
| Endpoint | Responses 风格接口地址，也可以只填服务基础地址 | `https://api.openai.com/v1/responses`、`https://api.deepseek.com` |
| Model | 模型名称 | `gpt-4.1-mini` |
| API key | 密钥，本地地址可留空 | `sk-...` |
| Reasoning effort | 思考级别，默认 `None`（关闭思考） | `None`、`Low`、`Medium`、`High` |

请求体为 `{ "model", "instructions", "input", "stream": true, "reasoning": { "effort": "none" } }`（选择 `Default` 时省略 `reasoning`），认证使用 `Authorization: Bearer <API key>`。接口返回 `text/event-stream` 时解析 `response.output_text.delta` 事件；返回普通 JSON 时读取 `output_text` 或 `output[].content[].text`。

`Reasoning effort` 直接映射到 Responses API 的 `reasoning.effort`：`None` 对应 `"none"`，即禁用思考；`Default` 不发送该字段，由服务端决定。若所选模型不支持该字段（返回 HTTP 400），客户端会自动去掉 `reasoning` 重试一次。

Endpoint 会自动补全请求路径，不需要自己拼完整地址：

| 填写 | 实际请求 |
| --- | --- |
| `https://api.deepseek.com` 或 `https://api.deepseek.com/` | `https://api.deepseek.com/v1/responses` |
| `https://api.deepseek.com/v1` | `https://api.deepseek.com/v1/responses` |
| `https://api.deepseek.com/v1/responses` | 保持不变 |
| `localhost:8080` | `http://localhost:8080/v1/responses` |

API key 保存在系统钥匙串（Login Keychain，service 为应用 Bundle ID，account `api-key`），不写入 UserDefaults，也不落盘为明文文件。

## 测试真实接口

仓库根目录的 `.env`（已被 git 忽略，不要提交）保存了联调用的真实接口信息：

| 变量 | 说明 | 示例 |
| --- | --- | --- |
| `LINGO_API_ENDPOINT` | 服务地址，可填基础地址 | `https://api.deepseek.com/` |
| `LINGO_MODEL` | 模型名称 | `deepseek-flash` |
| `LINGO_API_KEY` | 密钥，只保存在本地 `.env` | `sk-...` |

在应用中按上表填写 Endpoint、Model 和 API key 即可；Model 填 `deepseek-flash`，Endpoint 填 `https://api.deepseek.com/` 会自动请求 `https://api.deepseek.com/v1/responses`。

也可以直接用 curl 验证接口（在仓库根目录执行，命令本身不包含密钥）：

```bash
set -a && . ./.env && set +a
curl -sS -N "${LINGO_API_ENDPOINT%/}/v1/responses" \
  -H "Authorization: Bearer $LINGO_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$LINGO_MODEL\",\"instructions\":\"Translate to Chinese. Output only the translation.\",\"input\":\"test\",\"stream\":true}"
```

返回 `text/event-stream`，其中 `response.output_text.delta` 的 `delta` 为译文（`test` → `测试`），并以 `response.completed` 结束。

单元测试中有一个默认跳过的真实接口测试（`LingoTests/LiveTranslationTests.swift`），用 `.env` 运行：

```bash
set -a && . ./.env && set +a
TEST_RUNNER_LINGO_API_ENDPOINT="$LINGO_API_ENDPOINT" TEST_RUNNER_LINGO_MODEL="$LINGO_MODEL" \
  TEST_RUNNER_LINGO_API_KEY="$LINGO_API_KEY" make test
```

## 使用

| 操作 | 说明 |
| --- | --- |
| 全局快捷键 | 默认 `⌥⌘L`；也可在设置中录制双击 `⌃` `⌥` `⌘` `⇧` 之一 |
| 自动填充 | 在别的应用选中文本后唤起面板，选中的内容会自动填入原文并立即翻译（需要辅助功能权限） |
| 输入 | 左侧是普通文本编辑区，可跨行选择、撤销、粘贴多行文本；编辑原文不会自动翻译，也不会打断正在输出的请求，译文会以浅色显示 |
| 粘贴 | 原文为空或全选后粘贴时，自动开始翻译；其他位置的粘贴只修改原文 |
| 翻译按钮 | 原文被编辑、译文版本不一致且原文非空时出现在右上角，点击后按当前原文翻译 |
| 清空按钮 | 原文与译文版本一致时出现在右上角，点击后清空两侧内容并将焦点放回原文区 |
| 点击段落 | 左右两侧同一段一起高亮；再次点击已高亮的段落取消高亮；开始选中文本时立即取消高亮；点击原文空行或没有段落的位置清除高亮 |
| 选中文本 | 同一时间只有一侧保留选中：在一侧选择文字或移动光标，另一侧的选中会立即取消 |
| 开始翻译 | 滚动位置回到最上方，从第一段开始显示实时译文；滚到底部附近后恢复跟随 |
| `Return` | 普通换行 |
| `⌘↩` | 立即翻译 |
| 停止按钮 | 流式输出期间出现在右上角，点击后保留已生成的译文 |
| `Esc` | 隐藏面板并回到原应用 |
| `⌘W` / `⌘Q` | 隐藏面板，不会关闭窗口或退出应用 |
| 关闭面板 | 点击面板外的任意位置、切换到其他应用或按 `Esc` |
| 移动面板 | 拖动标题栏或顶部控件之间的空白区域 |
| 打开设置 | 隐藏面板；若设置是从面板打开的，关闭设置窗口后自动恢复面板 |
| 语言菜单 | 选择源语言与目标语言，源语言支持自动检测 |
| 交换按钮 | 交换语言与左右两段文本 |
| 复制按钮 | 复制完整译文 |
| 菜单栏图标 | 左键唤起面板，右键打开菜单 |

### 翻译时机

原文框只在两种情况下自动开始翻译：在空内容或全选状态下粘贴，以及从其他应用带回选中文本。手动编辑原文（输入、删除、撤销等）不会触发翻译，正在流式输出的请求也不会被打断；此时原文与译文版本不一致，译文以稍浅的颜色渲染。

没有进行中的请求时，右上角的操作按钮随状态切换：版本一致时显示「清空」，版本不一致且原文非空时显示「翻译」，原文为空时不显示按钮；请求进行中始终显示「停止」。

## 面板焦点

面板是非激活浮层（`.nonactivatingPanel`）：唤出时只把键盘焦点交给面板，不激活 Lingo，因此前台应用、它的菜单栏和所在的 Space 都保持不变，关闭面板后键盘焦点自动回到原来的窗口。

全局快捷键、菜单栏图标和菜单项都是用户明确的操作，唤出后可以直接输入。若某个系统版本收回了后台应用请求的键盘焦点，应用会在唤出后的几秒内检测到并退回到「激活 Lingo 再取焦点」的方式，保证输入始终可用；此时关闭面板会把焦点还给唤出前的应用。

## 全局快捷键

快捷键支持两种形式：

- 组合键：带修饰符（`⌃` `⌥` `⌘` `⇧`）的按键组合，例如 `⌥⌘L`。使用 Carbon 全局热键注册，不需要额外权限。应用默认使用该方案。
- 双击修饰键：在 300ms 内连续按两次同一个修饰键（`⌃`、`⌥`、`⌘`、`⇧`）。

在设置中点击快捷键按钮后，按下组合键即可录制组合键；连续快速按两次同一个修饰键即可录制双击。双击间隔固定为 300ms，不提供配置项。

双击修饰键依赖全局事件监听（修饰键状态与按键），需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Lingo Translate。应用启动时不会请求该权限，只有在录制并保存双击修饰键时才发起申请；设置窗口在缺少权限时会显示提示和打开系统设置的按钮。授权后回到应用即可生效，若仍不生效可重启应用。

自动读取其他应用里选中的文本也依赖同一项辅助功能权限。唤出面板时，应用先通过 Accessibility API 读取当前应用的选中内容；对少数不暴露选中内容的视图（部分网页、Electron 应用），退回「向该应用发送 ⌘C，再从剪贴板读取」的方式，读取完成后会把剪贴板内容原样恢复。没有选中文本时不会改动输入框。

## 结构

```
Lingo/
  App/        应用生命周期、面板、设置窗口、快捷键管理、辅助功能权限、状态
  Model/      语言列表、配置、快捷键值类型、双击检测、系统提示词、行切分、回复解析、规则分段
  Services/   Responses 客户端、Carbon 全局快捷键、双击修饰键监听、选中文本读取（Accessibility + 剪贴板兜底）、钥匙串密钥存储
  UI/         双栏面板界面（左右两个文本视图）、设置界面、快捷键录制控件
  Resources/  应用图标与配色
LingoTests/   单元测试（解析器、规则分段、对齐、翻译流程、视图交互）
Support/      Info.plist
scripts/      应用图标生成脚本
```

### 分段与对齐

原文完全由用户编辑，模型不会改写原文。翻译时，原文按行（与文本视图的段落规则一致）编号成 `N| text` 发给模型；模型自行把相邻的行归成逻辑段落（例如 man 手册、PDF 里被硬换行拆开的句子），每段返回 `<s lines="A-B">译文</s>`，不复述原文。

- 解析器（`Lingo/Model/SegmentParser.swift`）对流式回复的累积文本反复全量解析，不显示半截标签；区间会被校验：顺序错乱、重叠、越界都会被修正，宁可把内容并入上一段也不丢失。
- 模型漏掉的非空行会用原行号补译一次；仍然缺失的行在右侧显示浅色的 `Not translated`。
- 模型完全不按格式返回时，改用本地规则分段（`Lingo/Model/LayoutSegmenter.swift`）加 `<s id="N">` 编号协议重新请求；再失败就不对齐地显示整篇译文。

左右两栏是两个 TextKit 1 文本视图。第 k 段译文的顶部与原文中该段第一行的顶部对齐，高度差通过 `NSLayoutManagerDelegate` 在段首补间距实现，不改动任何文本内容；文本、宽度或外观变化后重新计算。

开始翻译时视图回到文档顶部，粘贴长文后也能从第一段看到译文实时输出。流式输出期间用户滚到底部附近后视图自动跟随新内容；一旦向上滚动（拖动滚动条、触控板或滚轮），跟随立即暂停，滚动位置完全交给用户。

点击某一段落时，左右两栏的同一段一起高亮：原文用浅蓝、译文用浅粉，颜色随浅色/深色外观自动调整。高亮是不带圆角的矩形，在文本栏两侧各留出一段内边距后铺满整个栏宽，文字不贴高亮边缘；两侧取同一段垂直区间（行间距不同也不影响），上下边缘始终齐平。每段在两侧共用一条从该段顶部到下一段顶部的“行带”，点击行带内任意位置即选中该段；点击原文空行或没有段落的位置清除高亮。点击先判断高亮再交给文本视图处理，光标定位、文本选择与编辑都不受影响。左右两栏不会同时显示选中的文本：在一侧选中文字或放置光标时，另一侧的选中会立即取消并保留其光标位置。

复制得到按顺序拼接的完整译文，原文中段与段之间有空行的地方，译文里也保留空行。交换语言时若已有完整译文，直接互换左右内容并保持对齐，不重新请求；正在翻译或没有译文时，交换后重新翻译。

系统提示词位于 `Lingo/Model/Prompt.swift`，随语言对动态生成，不从属于用户配置。

## 说明

- 应用使用 Apple Development 证书（Team `9K85QF2H9R`）签名，未做公证；仅适合本机/开发机使用，分发给他人仍需在“隐私与安全性”中允许打开。
- 未开启 App Sandbox；API key 存于登录钥匙串（service 为 Bundle ID / account `api-key`），需要时可手动删除。
- 仅实现 Responses 风格接口，未接入 Chat Completions。
