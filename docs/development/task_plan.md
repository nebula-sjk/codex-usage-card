# Codex 使用量卡片改版

## Goal

将卡片改成官网当前的 7 天使用限额 + 使用限额重置布局，缩小默认尺寸，并支持用户自由调整窗口大小。

## Phases

- [complete] 1. 检查现有实现与最新数据字段
- [complete] 2. 修改界面布局、数据读取与窗口缩放
- [complete] 3. 编译、重启常驻进程并进行视觉验证
- [complete] 4. 交互体验优化与点击命中验证

## Errors Encountered

| Swift optional tuple 类型不匹配 | 1 | 改为分别处理窗口、用量和重置字段的可选值 |
| NSEvent 没有 leftMouseCancelled | 1 | 使用 leftMouseUp 结束缩放状态 |
| 模拟点击触发 macOS System Events 权限提示 | 1 | 未授予权限；改以视觉、编译和常驻状态验证，避免修改系统隐私设置 |
