"""Codex Usage Card for Windows.

The app reads Codex's local SQLite log only. It makes no network requests.
"""

from __future__ import annotations

import ctypes
import os
import re
import sqlite3
import sys
import time
import tkinter as tk
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


APP_TITLE = "Codex 使用量卡片"
BALL_SIZE = 50
CARD_WIDTH = 320
CARD_HEIGHT = 200
REFRESH_MS = 30_000
VISIBILITY_MS = 500
EXPAND_MS = 500
COLLAPSE_MS = 120
TRANSPARENT = "#010203"


@dataclass
class Snapshot:
    weekly_used: int
    weekly_reset_after: int
    weekly_reset_at: int
    resets_available: int
    reset_card_expiry_at: int
    plan: str


class UsageReader:
    def __init__(self) -> None:
        self.database_path = Path.home() / ".codex" / "logs_2.sqlite"

    @staticmethod
    def _capture(key: str, text: str) -> str | None:
        escaped = re.escape(key)
        patterns = (
            rf'"{escaped}"\s*:\s*"([^"]+)"',
            rf'{escaped}\s*(?:=>|[=:])\s*"?([^,}}"\s]+)',
        )
        for pattern in patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                return match.group(1)
        return None

    @classmethod
    def _integer(cls, key: str, text: str) -> int | None:
        value = cls._capture(key, text)
        try:
            return int(value) if value is not None else None
        except ValueError:
            return None

    @classmethod
    def _timestamps(cls, key: str, text: str) -> list[int]:
        escaped = re.escape(key)
        patterns = (
            rf'"{escaped}"\s*:\s*"([^"]+)"',
            rf'{escaped}\s*(?:=>|[=:])\s*"?([^,}}"\s]+)',
        )
        output: list[int] = []
        for pattern in patterns:
            for raw in re.findall(pattern, text, re.IGNORECASE):
                try:
                    value = int(raw)
                    output.append(value // 1000 if value > 2_000_000_000_000 else value)
                    continue
                except ValueError:
                    pass
                try:
                    output.append(int(datetime.fromisoformat(raw.replace("Z", "+00:00")).timestamp()))
                except ValueError:
                    pass
        return output

    def read(self) -> Snapshot | None:
        if not self.database_path.exists():
            return None
        query = (
            "SELECT feedback_log_body FROM logs "
            "WHERE ((feedback_log_body LIKE '%\"x-codex-primary-window-minutes\":%' "
            "AND feedback_log_body LIKE '%\"x-codex-primary-used-percent\":%') "
            "OR (feedback_log_body LIKE '%x-codex-primary-window-minutes =>%' "
            "AND feedback_log_body LIKE '%x-codex-primary-used-percent =>%')) "
            "ORDER BY id DESC LIMIT 80"
        )
        try:
            connection = sqlite3.connect(f"file:{self.database_path}?mode=ro", uri=True, timeout=2)
            try:
                text = "\n".join(str(row[0]) for row in connection.execute(query))
            finally:
                connection.close()
        except (sqlite3.Error, OSError):
            return None

        primary_window = self._integer("x-codex-primary-window-minutes", text) or 0
        secondary_window = self._integer("x-codex-secondary-window-minutes", text) or 0
        primary_used = self._integer("x-codex-primary-used-percent", text)
        secondary_used = self._integer("x-codex-secondary-used-percent", text)
        primary_after = self._integer("x-codex-primary-reset-after-seconds", text) or 0
        secondary_after = self._integer("x-codex-secondary-reset-after-seconds", text) or 0
        primary_at = self._integer("x-codex-primary-reset-at", text) or 0
        secondary_at = self._integer("x-codex-secondary-reset-at", text) or 0

        if primary_window >= 10_000:
            used, reset_after, reset_at = primary_used, primary_after, primary_at
        elif secondary_window >= 10_000:
            used, reset_after, reset_at = secondary_used, secondary_after, secondary_at
        elif primary_window >= secondary_window:
            used, reset_after, reset_at = primary_used, primary_after, primary_at
        else:
            used, reset_after, reset_at = secondary_used, secondary_after, secondary_at
        if used is None:
            return None

        reset_keys = (
            "x-codex-usage-reset-available", "x-codex-resets-available",
            "x-codex-reset-credits", "usage_reset_count", "usage_limit_reset_count",
            "rate_limit_reset_available", "resets_available",
        )
        resets_available = next((value for key in reset_keys if (value := self._integer(key, text)) is not None), 1)
        expiry_keys = (
            "x-codex-usage-reset-expiry", "x-codex-usage-reset-expires-at",
            "x-codex-usage-reset-expiration-at", "x-codex-reset-expires-at",
            "x-codex-reset-expiration-at", "x-codex-credit-reset-expiry",
            "x-codex-credit-reset-expires-at", "x-codex-credits-reset-at",
            "x-codex-credits-expiry", "x-codex-credits-expiration",
            "x-codex-credits-expires-at", "x-codex-credits-expiration-at",
            "x-codex-full-reset-expiry", "x-codex-full-reset-expires-at",
            "x-codex-reset-expiry-at", "usage_reset_expiry", "usage_reset_expires_at",
            "usage_reset_expire_at", "usage_limit_reset_expires_at",
            "reset_card_expiry_at", "reset_card_expires_at",
        )
        expiries = [stamp for key in expiry_keys for stamp in self._timestamps(key, text) if stamp > 0]
        plan = (self._capture("x-codex-plan-type", text) or "Codex").upper()
        return Snapshot(used, reset_after, reset_at, max(0, resets_available), min(expiries, default=0), plan)


def has_visible_codex_window() -> bool:
    if os.name != "nt":
        return True
    user32 = ctypes.windll.user32
    kernel32 = ctypes.windll.kernel32
    process_query_limited_information = 0x1000
    found = ctypes.c_bool(False)

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def callback(hwnd: int, _: int) -> bool:
        if not user32.IsWindowVisible(hwnd) or user32.IsIconic(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        title_buffer = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, title_buffer, length + 1)
        title = title_buffer.value.lower()
        pid = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        executable = ""
        handle = kernel32.OpenProcess(process_query_limited_information, False, pid.value)
        if handle:
            try:
                size = ctypes.c_ulong(1024)
                path_buffer = ctypes.create_unicode_buffer(size.value)
                if kernel32.QueryFullProcessImageNameW(handle, 0, path_buffer, ctypes.byref(size)):
                    executable = Path(path_buffer.value).stem.lower()
            finally:
                kernel32.CloseHandle(handle)
        is_codex = "codex" in executable or executable == "chatgpt" or "codex" in title
        is_self = "usagecard" in executable or "使用量卡片" in title
        if is_codex and not is_self:
            found.value = True
            return False
        return True

    user32.EnumWindows(callback, 0)
    return bool(found.value)


class UsageCard:
    palettes = {
        "充足": ("#DCEFFA", "#2FC95C", "#187538"),
        "适中": ("#F2EBCB", "#E4931B", "#92520B"),
        "告急": ("#F1DFD7", "#DD4842", "#A42622"),
    }

    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title(APP_TITLE)
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.attributes("-transparentcolor", TRANSPARENT)
        self.canvas = tk.Canvas(self.root, highlightthickness=0, bg=TRANSPARENT)
        self.canvas.pack(fill="both", expand=True)
        self.reader = UsageReader()
        self.snapshot: Snapshot | None = None
        self.remaining = 0
        self.collapsed = True
        self.expand_job: str | None = None
        self.collapse_job: str | None = None
        self.dragging = False
        self.drag_x = 0
        self.drag_y = 0
        self.anchor_right = self.root.winfo_screenwidth() - 24
        self.anchor_top = 24
        self._set_geometry(BALL_SIZE, BALL_SIZE)
        self._bind_events()
        self._draw()
        self.refresh()
        self.check_visibility()

    def _bind_events(self) -> None:
        self.canvas.bind("<Enter>", self._enter)
        self.canvas.bind("<Leave>", self._leave)
        self.canvas.bind("<ButtonPress-1>", self._press)
        self.canvas.bind("<B1-Motion>", self._drag)
        self.canvas.bind("<ButtonRelease-1>", self._release)
        self.canvas.bind("<Button-3>", self._menu)

    def _set_geometry(self, width: int, height: int) -> None:
        x = max(0, self.anchor_right - width)
        y = max(0, self.anchor_top)
        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.canvas.config(width=width, height=height)

    @staticmethod
    def _status(remaining: int) -> str:
        return "告急" if remaining < 30 else "适中" if remaining < 60 else "充足"

    def _rounded(self, x1: int, y1: int, x2: int, y2: int, radius: int, **kwargs: object) -> int:
        points = [x1 + radius, y1, x2 - radius, y1, x2, y1, x2, y1 + radius,
                  x2, y2 - radius, x2, y2, x2 - radius, y2, x1 + radius, y2,
                  x1, y2, x1, y2 - radius, x1, y1 + radius, x1, y1]
        return self.canvas.create_polygon(points, smooth=True, splinesteps=24, **kwargs)

    def _draw(self) -> None:
        self.canvas.delete("all")
        status = self._status(self.remaining)
        background, accent, status_color = self.palettes[status]
        if self.collapsed:
            self.canvas.create_oval(3, 3, 47, 47, fill=background, outline=accent, width=2)
            self.canvas.create_oval(37, 7, 43, 13, fill=accent, outline="")
            self.canvas.create_text(25, 27, text=f"{self.remaining}%", fill="#20242A", font=("Segoe UI", 9, "bold"))
            return

        self._rounded(1, 1, CARD_WIDTH - 1, CARD_HEIGHT - 1, 22, fill=background, outline=accent, width=1)
        plan = self.snapshot.plan if self.snapshot else "…"
        self.canvas.create_text(24, 23, text=f"CODEX · {plan}", anchor="w", fill="#20242A", font=("Consolas", 9))
        self.canvas.create_text(296, 23, text=status, anchor="e", fill=status_color, font=("Segoe UI", 9, "bold"))
        self.canvas.create_text(24, 51, text="每周使用限额", anchor="w", fill="#5D646B", font=("Segoe UI", 9))
        self.canvas.create_text(24, 84, text=f"{self.remaining}%", anchor="w", fill="#20242A", font=("Segoe UI", 27))
        self._rounded(24, 106, 296, 113, 4, fill="#F8FAFA", outline="")
        fill_width = max(7, int(272 * self.remaining / 100))
        self._rounded(24, 106, 24 + fill_width, 113, 4, fill=accent, outline="")
        self.canvas.create_text(24, 125, text=self._weekly_reset_text(), anchor="w", fill="#6B7278", font=("Segoe UI", 8))
        self._rounded(20, 139, 300, 184, 12, fill="#FFFFFF", outline="#FFFFFF", stipple="gray75")
        self.canvas.create_text(32, 155, text="限额重置次数（仅显示作用）", anchor="w", fill="#30353A", font=("Segoe UI", 8, "bold"))
        self.canvas.create_text(32, 174, text=self._expiry_text(), anchor="w", fill="#70767C", font=("Segoe UI", 7))
        count = self.snapshot.resets_available if self.snapshot else 1
        self._rounded(198, 149, 266, 175, 13, fill="#087F45", outline="")
        self.canvas.create_text(232, 162, text=f"可用{count}次", fill="white", font=("Segoe UI", 8, "bold"))
        self.canvas.create_text(282, 162, text="⌄", fill="#30353A", font=("Segoe UI", 11))
        stamp = datetime.now().strftime("%H:%M") if self.snapshot else "--:--"
        self.canvas.create_text(24, 192, text=f"最近更新 {stamp}  ·  每 30 秒自动刷新", anchor="w", fill="#737A80", font=("Segoe UI", 7))

    def _weekly_reset_text(self) -> str:
        if not self.snapshot:
            return "重置日期读取中…"
        if self.snapshot.weekly_reset_at > 0:
            return datetime.fromtimestamp(self.snapshot.weekly_reset_at).strftime("将于 %m月%d日 重置").replace(" 0", " ")
        seconds = self.snapshot.weekly_reset_after
        if seconds > 0:
            days, hours = seconds // 86400, (seconds % 86400) // 3600
            return f"约 {days} 天 {hours} 小时后重置" if days else f"约 {max(1, hours)} 小时后重置"
        return "重置日期以服务端返回为准"

    def _expiry_text(self) -> str:
        if self.snapshot and self.snapshot.reset_card_expiry_at > 0:
            return datetime.fromtimestamp(self.snapshot.reset_card_expiry_at).strftime("最近一次重置将于 %m月%d日到期").replace(" 0", " ")
        return "重置次数过期：暂未读取"

    def refresh(self) -> None:
        snapshot = self.reader.read()
        if snapshot:
            self.snapshot = snapshot
            self.remaining = 100 - min(100, max(0, snapshot.weekly_used))
            self._draw()
        self.root.after(REFRESH_MS, self.refresh)

    def refresh_now(self) -> None:
        snapshot = self.reader.read()
        if snapshot:
            self.snapshot = snapshot
            self.remaining = 100 - min(100, max(0, snapshot.weekly_used))
        self._draw()

    def check_visibility(self) -> None:
        if has_visible_codex_window():
            self.root.deiconify()
            self.root.lift()
        else:
            self._collapse()
            self.root.withdraw()
        self.root.after(VISIBILITY_MS, self.check_visibility)

    def _enter(self, _: tk.Event) -> None:
        if self.collapsed and not self.dragging and self.expand_job is None:
            self.expand_job = self.root.after(EXPAND_MS, self._expand)

    def _leave(self, _: tk.Event) -> None:
        if self.expand_job:
            self.root.after_cancel(self.expand_job)
            self.expand_job = None
        if not self.collapsed:
            self.collapse_job = self.root.after(COLLAPSE_MS, self._collapse)

    def _expand(self) -> None:
        self.expand_job = None
        if self.dragging:
            return
        self.collapsed = False
        self._set_geometry(CARD_WIDTH, CARD_HEIGHT)
        self._draw()

    def _collapse(self) -> None:
        if self.expand_job:
            self.root.after_cancel(self.expand_job)
            self.expand_job = None
        self.collapse_job = None
        if self.collapsed:
            self._set_geometry(BALL_SIZE, BALL_SIZE)
            return
        self.collapsed = True
        self._set_geometry(BALL_SIZE, BALL_SIZE)
        self._draw()

    def _press(self, event: tk.Event) -> None:
        self.dragging = True
        self.drag_x, self.drag_y = event.x_root, event.y_root
        if self.expand_job:
            self.root.after_cancel(self.expand_job)
            self.expand_job = None

    def _drag(self, event: tk.Event) -> None:
        dx, dy = event.x_root - self.drag_x, event.y_root - self.drag_y
        self.anchor_right += dx
        self.anchor_top += dy
        self.drag_x, self.drag_y = event.x_root, event.y_root
        width = BALL_SIZE if self.collapsed else CARD_WIDTH
        height = BALL_SIZE if self.collapsed else CARD_HEIGHT
        self._set_geometry(width, height)

    def _release(self, _: tk.Event) -> None:
        self.dragging = False

    def _menu(self, event: tk.Event) -> None:
        menu = tk.Menu(self.root, tearoff=0)
        menu.add_command(label="刷新", command=self.refresh_now)
        menu.add_separator()
        menu.add_command(label="退出", command=self.root.destroy)
        menu.tk_popup(event.x_root, event.y_root)

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    if sys.platform != "win32":
        print("This entry point is intended for Windows.", file=sys.stderr)
    UsageCard().run()
