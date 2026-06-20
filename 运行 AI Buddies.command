#!/bin/bash
# AI Buddies — 双击启动：读取本机 Claude Code 与 Codex 用量，生成仪表盘并在浏览器打开。
cd "$(dirname "$0")"
echo "AI Buddies — 正在读取 ~/.claude 与 ~/.codex 的用量…"
echo
python3 usage_buddy.py --plan-price 200 --html ai_buddies_dashboard.html --open
echo
echo "完成：仪表盘已在浏览器打开（ai_buddies_dashboard.html）。"
read -p "按回车键关闭此窗口…" _
