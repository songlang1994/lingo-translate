# Lingo

macOS 菜单栏翻译工具。全局快捷键唤起浮动面板，调用 Responses 风格的大模型接口完成翻译。

- 使用大模型翻译，系统提示词内置于应用
- 左右两栏：左侧输入、右侧译文，按换行符切分段落并逐段对齐
- 点击任一段落，原文与译文同时高亮（原文浅蓝、译文浅粉），便于对照
- 译文在右侧流式输出，生成过程中可随时停止
- 界面只有语言选择、交换、停止、复制、设置几类控件
- 菜单栏常驻，不占用 Dock
- 原生 Swift + SwiftUI / AppKit，无第三方依赖
- 交互形式参考 [m-inan/mac-translate](https://github.com/m-inan/mac-translate)

## 环境

- macOS 14 或更新版本
- Xcode 16 或更新版本

## 构建与运行

```bash
make run          # 构建 Debug 并启动
make release      # 构建 Release 并打包 dist/Lingo.zip
make install      # 构建 Release 并复制到 /Applications
```

也可以直接用 Xcode 打开 `Lingo.xcodeproj`，选择 Lingo scheme 运行。

## 首次配置

首次启动只显示设置窗口，填入以下三项即可使用：

| 项目 | 说明 | 示例 |
| --- | --- | --- |
| Endpoint | Responses 风格接口地址，也可以只填服务基础地址 | `https://api.openai.com/v1/responses`、`https://api.deepseek.com` |
| Model | 模型名称 | `gpt-4.1-mini` |
| API key | 密钥，本地地址可留空 | `sk-...` |

请求体为 `{ "model", "instructions", "input", "stream": true }`，认证使用 `Authorization: Bearer <API key>`。接口返回 `text/event-stream` 时解析 `response.output_text.delta` 事件；返回普通 JSON 时读取 `output_text` 或 `output[].content[].text`。

Endpoint 会自动补全请求路径，不需要自己拼完整地址：

| 填写 | 实际请求 |
| --- | --- |
| `https://api.deepseek.com` 或 `https://api.deepseek.com/` | `https://api.deepseek.com/v1/responses` |
| `https://api.deepseek.com/v1` | `https://api.deepseek.com/v1/responses` |
| `https://api.deepseek.com/v1/responses` | 保持不变 |
| `localhost:8080` | `http://localhost:8080/v1/responses` |

API key 保存在 `~/Library/Application Support/Lingo/api-key`，文件权限为 `600`，不写入 UserDefaults。若之前因为只填了服务根地址而收到 `not found`，升级后无需修改配置，路径会自动补全。

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

## 使用

| 操作 | 说明 |
| --- | --- |
| 全局快捷键 | 默认 `⌥⌘L`；也可在设置中录制双击 `⌃` `⌥` `⌘` `⇧` 之一 |
| 输入 | 左侧按段落输入或粘贴，停顿后自动翻译 |
| 点击段落 | 左右两侧同段落一起高亮，空行与空白区域不高亮 |
| `Return` | 在当前段落之后新建一个段落 |
| `⌘↩` | 立即翻译 |
| 停止按钮 | 流式输出期间出现在右上角，点击后保留已生成的译文 |
| `Esc` | 关闭面板并回到原应用 |
| 失去焦点 | 切换到其他应用时面板立即关闭，不做延迟等待 |
| 打开设置 | 隐藏面板；若设置是从面板打开的，关闭设置窗口后自动恢复面板 |
| 语言菜单 | 选择源语言与目标语言，源语言支持自动检测 |
| 交换按钮 | 交换语言与左右两段文本 |
| 复制按钮 | 复制完整译文 |
| 菜单栏图标 | 左键唤起面板，右键打开菜单 |

## 全局快捷键

快捷键支持两种形式：

- 组合键：带修饰符（`⌃` `⌥` `⌘` `⇧`）的按键组合，例如 `⌥⌘L`。使用 Carbon 全局热键注册，不需要额外权限。应用默认使用该方案。
- 双击修饰键：在 300ms 内连续按两次同一个修饰键（`⌃`、`⌥`、`⌘`、`⇧`）。

在设置中点击快捷键按钮后，按下组合键即可录制组合键；连续快速按两次同一个修饰键即可录制双击。双击间隔固定为 300ms，不提供配置项。

双击修饰键依赖全局事件监听（修饰键状态与按键），需要在「系统设置 → 隐私与安全性 → 辅助功能」中允许 Lingo。应用启动时不会请求该权限，只有在录制并保存双击修饰键时才发起申请；设置窗口在选中双击方案且缺少权限时会显示提示和打开系统设置的按钮。授权后回到应用即可生效，若仍不生效可重启应用。

## 结构

```
Lingo/
  App/        应用生命周期、面板、设置窗口、快捷键管理、辅助功能权限、状态
  Model/      语言列表、配置、快捷键值类型、双击检测、系统提示词
  Services/   Responses 客户端、Carbon 全局快捷键、双击修饰键监听
  UI/         双栏面板界面、设置界面、快捷键录制控件
  Resources/  应用图标与配色
Support/      Info.plist
scripts/      应用图标生成脚本
```

面板按换行符把输入切成段落，每一行左侧是原文、右侧是译文，行高取两侧较高者，因此段落始终水平对齐。流式回复按换行累积到对应段落，最后一个段落会边生成边增长。

流式输出时视图自动跟随底部。用户一旦滚动（拖动滚动条、触控板或滚轮），跟随立即暂停，滚动位置完全交给用户；滚回底部后自动恢复跟随。

点击某一段落时，左右两栏的同一段一起高亮：原文用浅蓝、译文用浅粉，颜色随浅色/深色外观自动调整。高亮通过本地鼠标监听实现，不拦截点击事件，光标定位、文本选择与编辑都不受影响；点击空白区域清除高亮，内容为空白字符的段落不会高亮。

系统提示词位于 `Lingo/Model/Prompt.swift`，随语言对动态生成，不从属于用户配置。

## 说明

- 应用为 ad-hoc 签名，首次从网络下载后运行可能需要在“隐私与安全性”中允许打开。
- 未开启 App Sandbox，API key 存于用户目录，便于本地直接运行。
- 仅实现 Responses 风格接口，未接入 Chat Completions。
