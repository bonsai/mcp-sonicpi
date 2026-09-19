# mcp-sonicpi

SONIC Pi ワークフロー用 **MCP サーバー (Ruby)**。

music-json (design repo) を読み、**Sonic Pi コード (Ruby DSL)** を生成し、
OSC (UDP 4557) で Sonic Pi Spider へ送信 / 録音する。
MCP (JSON-RPC 2.0 over stdio) として動作するので、opencode / Claude 等の
MCP クライアントから `se_preview` / `se_render` を呼べる。

## 構成

```
mcp-sonicpi/
├── lib/sonic_pi_mcp.rb   # MCP サーバー本体 (Ruby)
└── recipe/se.yaml        # YAML 指示ファイル例
```

## 使い方（ローカル）

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

## Sonic Pi Spider 起動

```bash
ruby /usr/lib/sonic-pi/app/server/ruby/bin/sonic-pi-server.rb
```

- ポート: OSC 4557 / scsynth 4556 / 録音は Sonic Pi の `recording_start` 経由
- 環境変数: `SPIDER_OSC_PORT` (4557), `SG_DESIGN_HOME` (design repo)

## 依存

- Ruby (標準ライブラリのみ: json / socket / timeout / yaml)
- Sonic Pi（スパイダー・サーバー）
- 音声デバイス（WSL では PulseAudio 等の仮想デバイスが必要）

## design repo

music-json スキーマ等は **show-builder repo**（`~/repo/show-builder`）が
ソース・オブ・トゥルース。

## Elixir からも制御可

`examples/elixir_osc_spi.exs` — Elixir で書いた最小 OSC クライアント。
Sonic Pi の `/run-code` [gui_id:int, code:string] を UDP 4557 へ送信する。

```bash
elixir examples/elixir_osc_spi.exs
```

- 依存: Elixir/Erlang のみ（`:gen_udp`、外部パッケージ不要）
- この OSC エンコーダは mcp-sonicpi の Ruby 実装と同一プロトコル