# 轻舟助手 · 微信 AI 客服

在 Mac 上替你回微信客户消息的小工具。它**看屏幕**读消息（截图 + 本机识字），按你的知识库让 AI 写回复，再像人一样点输入框、打字、发送。不用微信接口，不改微信，不需要登录别的账号。

> 只支持 **macOS 14 以上 + Mac 版微信**。Windows、企业微信、其他聊天软件还不支持。

## 两分钟视频教程

视频文件：[教程视频.mp4](https://github.com/paperlantern-dev/qingzhou-assistant/blob/main/docs/%E6%95%99%E7%A8%8B%E8%A7%86%E9%A2%91.mp4?raw=true)

https://github.com/user-attachments/assets/f8bb3fe9-ccbc-49f0-a34b-027b423585c9

## 它能做什么

- **自动回复私聊**：只按你放进知识库的资料回答；资料里没有的不乱编，交给你处理。
- **两种方式**：全自动发，或者“我确认后发”（草稿先给你看，你点了才发）。
- **关键词规则**：售后、讲价、要付款、找真人 → 不让 AI 回，直接提醒你。
- **价格表**：客人问“有什么卖”，把你的价格表原样排好发出去。
- **商品照片**：客人问“有图吗”“多大”，回完自动发一张你放好的照片。
- **客户记忆**：记得每位客人之前聊过什么（只存在你自己的电脑里）。
- **隐私屏蔽**：地址、电话、姓名、证件号在发给 AI 之前先换成占位符。
- **安全刹车**：默认不回群聊；每小时有发送上限；连按两下 Esc 立刻暂停；读屏不对就自动停下。
- **模拟微信**：自带一个假的微信窗口，可以先在上面练手，不碰真微信。

## 快速开始

### 方法一：直接下载（不用懂编程）

1. 到 [下载页](https://github.com/paperlantern-dev/qingzhou-assistant/releases/latest) 下载 `qingzhou-assistant-0.1.0.zip`，双击解压。
2. 把 **轻舟助手** 拖到“应用程序”文件夹，双击打开。
3. 第一次打开，Mac 会提示“无法验证开发者”（这个应用没有花钱买苹果的开发者签名）。打开 系统设置 › 隐私与安全性，往下拉，点 **仍要打开**。只需要做一次。

知识库会自动放在 `文稿/轻舟助手知识库`，里面先有一份示例。

### 方法二：自己编译

需要：macOS 14+，Xcode 命令行工具（终端里运行 `xcode-select --install`）。

```bash
git clone https://github.com/paperlantern-dev/qingzhou-assistant.git
cd qingzhou-assistant
./scripts/build_app.sh
open build/模拟微信.app build/轻舟助手.app
```

然后按 **[使用教程](docs/使用教程.md)** 一步步来：给权限 → 填你自己的 API Key → 放知识库 → 在模拟微信上试 → 再用到真微信。

## AI 模型和 API Key

本项目**不带任何 API Key**，要用你自己的：

- 设置 › 模型 › 回复模型选“API 直连”，再选一家（内置 DeepSeek、通义千问、OpenAI 的预设），粘贴你的 Key，点“测试”。
- 也可以“添加 API”，接任何兼容 OpenAI 格式的接口。
- 想完全不上云：装 [Ollama](https://ollama.com)，在“回复模型”里选 Ollama。
- Key 只存在你 Mac 的“钥匙串”里，不写进任何文件，也不会进 git。

## 知识库

把你店里的资料放进 `knowledge/` 文件夹（或在应用里换一个文件夹），支持 txt、md、csv、pdf、docx、rtf，改了自动重新加载。

- `knowledge/` 里现在是一家虚构水果店的**示例**，请换成你自己的。
- 价格表用 csv，表头：`品名,规格,价格,说明`。
- 商品照片放在知识库文件夹里的 `商品照片/`，用品名起文件名（如 `红富士.jpg`）。
- 知识库是空的时候，完全不自动回复。

## 隐私和数据

- 截图只在本机处理，不上传。发给 AI 的只有聊天文字（地址电话已屏蔽）、相关的知识库片段，以及不含隐私文字的客户图片（可关）。
- 客户记忆在 `~/Library/Application Support/轻舟助手/`，只在你的电脑上。
- **不要**把你的真实知识库、客户记忆、API Key 提交到公开仓库。

## 使用须知

- 这是通过模拟点击和键盘来操作微信的工具，不是官方接口。请自行判断是否符合微信的使用规则，风险自负；建议先用“我确认后发”。
- 已在自带的模拟微信上完整测试；真实微信只在 4.1.15 上做过小范围测试。微信升级后版面可能变化，应用会先自检，读得不对就停。
- 自动寻找窗口分隔线的功能目前只在模拟微信上验证过。

## 开发

```bash
swift test                # 单元测试
./scripts/build_app.sh    # 生成 build/轻舟助手.app 和 build/模拟微信.app
```

- `Sources/QingzhouCore`：读屏解析、知识库、回复、规则、隐私屏蔽（不含界面，全部有测试）
- `Sources/QingzhouApp`：SwiftUI 界面和自动回复流程
- `Sources/MockWeChat`：模拟微信，用来安全地测试
- `test-fixtures/`：测试用的图片和资料（都是程序画的、虚构的）

端到端自动测试（不碰真微信）：

```bash
open -n build/模拟微信.app --args --script "--log=$PWD/test-reports/mock.json"
open -n build/轻舟助手.app --args --autotest "$PWD/test-reports/auto.json" --duration 170
```

## 许可

[MIT](LICENSE)
