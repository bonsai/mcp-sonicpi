---
name: mcp-sonicpi
description: >
  SONIC Pi ワークフロー用 MCP サーバー (Ruby)。music-json (design repo) を読み、
  Sonic Pi コード (Ruby DSL) を生成し、OSC (UDP 4557) で Sonic Pi Spider へ
  送信・録音する。MCP (JSON-RPC 2.0 over stdio) として opencode / Claude 等から
  se_preview / se_render を呼べる。
  「sonic pi」「sonicpi」「音楽生成」「music-json」「OSC」
  「se_preview」「se_render」「mcp-sonicpi」「レコーディング」などのキーワードで発動。
  実行: `ruby lib/sonic_pi_mcp.rb`
---

# mcp-sonicpi — Sonic Pi MCP サーバー (Ruby)

music-json → Sonic Pi コード生成 → OSC 送信 / 録音。

## 構成

```
mcp-sonicpi/
├── lib/sonic_pi_mcp.rb   # MCP サーバー本体 (Ruby)
└── recipe/se.yaml        # YAML 指示ファイル例
```

## 使い方

```bash
ruby lib/sonic_pi_mcp.rb
```

JSON-RPC リクエストを stdio に流す:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"se_preview","arguments":{"music":"music/lo-fi-radio-amin.json"}}}
```

## MCP ツール

| tool | 説明 |
| --- | --- |
| `se_preview` | music-json → Sonic Pi コード文字列を返す（レンダリングなし） |
| `se_render` | music-json → Sonic Pi コード → 3秒 mp3 レンダリング（Spider OSC） |
| `se_workflow_yaml` | YAML 指示ファイルから Sonic Pi ワークフロー実行 |
| `sp_status` | Sonic Pi Spider の稼働状態を確認 |

## music-json

music-json スキーマ等は **show-builder repo**（`~/repo/show-builder`）がソース・オブ・トゥルース。

## Elixir からも制御可

`examples/elixir_osc_spi.exs` — 最小 OSC クライアント（`:gen_udp` のみ、外部パッケージ不要）。
この OSC エンコーダは mcp-sonicpi の Ruby 実装と同一プロトコル。
