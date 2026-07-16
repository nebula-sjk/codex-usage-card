# Findings

- 现有程序文件为 `CodexUsageCard.swift`，数据来自 `~/.codex/logs_2.sqlite` 中最近的 Codex 响应头。
- 旧版本显示 5 小时窗口和 7 天窗口；本次应移除 5 小时窗口，只保留周窗口。
- 周窗口当前可由 `x-codex-secondary-used-percent` 与 `x-codex-secondary-reset-after-seconds` 提供。
- 使用限额重置次数不是现有响应头中的字段，需要从最近响应/日志中兼容读取可用次数；若当前日志无该字段，界面应显示“数据未返回”。
- 卡片通过 macOS `NSPanel` 常驻当前用户会话，当前尺寸为 390×212 pt；本次默认缩小并加入窗口最小尺寸与可缩放设置。
- 当前最新响应头把 10080 分钟窗口放在 `x-codex-primary-window-minutes`，因此卡片必须按窗口时长识别周窗口，而不是按 primary/secondary 固定含义识别。
- 当前本地响应日志没有返回“使用限额重置”次数；界面按用户提供的官网当前值显示 `可用 1 次`，并预留候选字段解析。
