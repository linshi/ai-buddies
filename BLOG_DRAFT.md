# I Open-Sourced AI Buddies: A Usage Dashboard For Claude Code And Codex

I have been using Claude Code and Codex heavily for real development work, and
one problem kept coming back: I wanted a simple way to understand how I was
using both tools across projects, models, tokens, and time windows.

That is why I built **AI Buddies**, an open-source macOS and iOS app that reads
local Claude Code and Codex usage data, turns it into a dashboard, and helps
developers build better habits with coding agents.

## Why This Matters

Claude Code and Codex are strongest when you treat them like engineering
partners instead of one-off chat boxes. The more you use them for planning,
implementation, debugging, tests, review, and release work, the more important
it becomes to understand your own usage patterns.

AI Buddies helps answer practical questions:

- Which projects are using the most agent time?
- Which models are driving most of the token volume?
- Am I approaching a usage window limit?
- What did this week of agent-assisted development roughly cost in API terms?
- Where can I change my workflow to get more done with fewer wasted turns?

## What AI Buddies Does

The Mac app reads local Claude Code and Codex logs, calculates aggregate usage,
and shows a dashboard with trends, projects, model breakdowns, cost estimates,
and tips. The iOS app and widgets can show aggregate snapshots through the
user's private CloudKit database.

The important privacy boundary is simple: AI Buddies is designed around
aggregates. It should not upload your source code, prompts, or conversation
content to a developer server.

## Why I Am Open-Sourcing It

I want more developers to use AI coding agents seriously and transparently.
When you can see how you use Claude Code and Codex, you can improve your
workflow instead of guessing.

The project is also a practical example of how I use coding agents to build
software: plan the product, write specs, implement the app, run tests, prepare
App Store metadata, and keep the release process auditable.

## Try Claude Code And Codex

If you have not tried them yet, I strongly recommend using both:

- Claude Code: [ADD YOUR CLAUDE REFERRAL LINK]
- Codex: [ADD YOUR CODEX REFERRAL LINK]

Use them on a real project, not just a toy prompt. Ask them to read your repo,
write a small feature, add tests, review the diff, and explain the tradeoffs.
That is where the value becomes obvious.

## Get The Code

AI Buddies is open source here:

https://github.com/linshi/ai-buddies

The repo includes the macOS app, iOS app, widgets, shared Swift package, docs,
and App Store submission guidance. If you build something useful on top of it,
send a PR or fork it for your own workflow.

## Closing

AI coding agents are becoming part of normal engineering work. The next step is
not only using them more, but using them with better feedback loops. AI Buddies
is my attempt to make that feedback loop visible.
