---
title: MakeTools · Markdown 预览示例
author: make
version: 1.0.0
---

# MakeTools · Markdown 预览示例

这是 **MakeTools** 个人效率工具集内置的 **Quick Look 快速预览扩展** 示例文档。选中任意 `.md` 文件后按下 **空格键**，即可直接查看排版后的内容，并支持代码块一键复制、复制原文或纯文本。

> [!NOTE]
> 数据型 Quick Look 扩展（`QLPreviewProvider`）在沙盒 HTML 视图中不执行外部 JavaScript，因此本项目在扩展进程内使用纯 Swift 完成解析、代码高亮与主题渲染，**零网络请求、零外部依赖**。

> [!TIP]
> 界面自动适配 macOS 的 **浅色模式** 与 **深色模式**。

## 支持的语法特性

- **文本样式**：**加粗**、*斜体*、***粗斜体***、~~删除线~~、行内代码 `let quickLook = true`
- **链接与自动链接**：[Apple Quick Look 文档](https://developer.apple.com/documentation/quicklook) 与 <https://swift.org>
- **任务列表**：
  - [x] 支持标题 `H1` – `H6` 与分隔线
  - [x] 支持 GFM 表格与列对齐
  - [x] 支持代码块语言标签与基础语法高亮
  - [ ] 继续扩展更多自定义主题配色

### 有序与嵌套列表

1. 在访达（Finder）中选中 `.md` 文件
2. 按下键盘 **空格键**
   1. 系统通过 `net.daringfireball.markdown` 匹配本扩展
   2. `PreviewProvider` 读取文件并生成离线 HTML
3. 享受流畅的原生理性排版预览

## 代码块示例

```swift
import QuickLookUI
import UniformTypeIdentifiers

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 860, height: 1000)) { _ in
            // 离线渲染 Markdown 为 HTML
            return Data("<h1>Hello Quick Look</h1>".utf8)
        }
        handler(reply, nil)
    }
}
```

```bash
# 注册并刷新 Quick Look 插件缓存
pluginkit -a /Applications/MarkdownQuickLook.app/Contents/PlugIns/MarkdownPreviewExtension.appex
qlmanage -r
```

## 表格对齐示例

| 模块 | 职责 | 耗时 |
| :--- | :---: | ---: |
| `MarkdownRenderer` | 块级与行内纯 Swift 解析 | < 2ms |
| `ThemeCSS` | 浅色 / 深色响应式样式 | 内置 |
| `PreviewProvider` | `QLPreviewReply` 数据输出 | 按需 |

> [!WARNING]
> 本项目默认采用 Ad-hoc 签名方便本地直接运行；如需分发给其他用户或上架 App Store，请在 Xcode 中配置 Apple Developer 签名证书。
