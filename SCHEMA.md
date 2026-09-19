# mcp-sonicpi — 型宣言 (Types & Schemes)

MCP サーバーが公開する **ツール型**・**OSC プロトコル**・**音楽→コード変換スキーム** の正。

## MCP ツール

| tool | params (型) | returns (型) |
| --- | --- | --- |
| `se_preview` | `music: string` | `string`（Sonic Pi Ruby コード） |
| `se_render` | `music: string`, `out: string`, `max_seconds: float` | `string`（`code sent to Spider ...` / `Error: ...`） |
| `se_workflow_yaml` | `yaml_file: string` | `string`（結果の結合） |
| `sp_status` | — | `string`（`Sonic Pi Spider (port 4557): OK/not running`） |

全ツールの応答は MCP 規約に従い `result.content[0].text: string` に収まる。

## se_render 引数スキーマ（inputSchema 正）

```json
{
  "type": "object",
  "properties": {
    "music":       { "type": "string", "description": "music-json の path（SG_DESIGN_HOME 相対 or 絶対）" },
    "out":         { "type": "string", "description": "出力 mp3 path" },
    "max_seconds": { "type": "number", "description": "最大長（秒）。既定 3.0" }
  },
  "required": []
}
```

## SG_DESIGN_HOME 解決規則

- `SG_DESIGN_HOME` 環境変数があればそれを正とする。
- 無ければ `~/repo/show-builder`。
- `music` 引数が絶対 path ならそのまま。相対なら `SG_DESIGN_HOME / <path>`。

## Sonic Pi OSC プロトコル

Sonic Pi Server（Spider）は UDP で受信する。既定ポート 4557。

### /run-code（コード送信・実行）

```
osc address: "/run-code"
osc args   : [gui_id: int, code: string]
```

- **2引数**: `gui_id`（int / job id）、`code`（string、utf-8）。
- サーバー実装: `sonic-pi-server.rb` の
  `server.add_method("/run-code") { |args| gui_id = args[0]; code = args[1].force_encoding("utf-8"); sp.__spider_eval code }`
- ⚠️ `[id, id, code]` の3引数は不正（2番目の int に force_encoding が呼ばれ例外）。

### OSC エンコード規則

- アドレス・文字列は 4 バイト境界に `\x00` パディング。
- int: big-endian `N`、float: big-endian `g`。
- タグ文字列は `,` 始まり（例 `,is`）。

### ポート

| 用途 | ポート |
| --- | --- |
| Spider OSC 受信 | 4557 |
| scsynth (SuperCollider) | 4556 |
| OSC cues | 4560 |
| Websocket | 4562 |

### Elixir での送信例

```elixir
payload = <<"/run-code"::binary, 0::size(8), ",is"::binary, 0::size(8),
            gui_id::32, code::binary>>
# + string 4byte パディング（コード本体）
{:ok, s} = :gen_udp.open(0, [:binary, active: false])
:gen_udp.send(s, ~c"127.0.0.1", 4557, payload)
```

完全実装は `examples/elixir_osc_spi.exs`。

## music-json → Sonic Pi コード変換スキーム

```
use_bpm <tempo>
# bar N (<root><quality>, <secs>s)
use_synth :<synth for pad>
play_chord <midi_notes>, release: <secs-0.1>, amp: 0.25
use_synth :sine
play <bass_midi>, release: <secs-0.1>, amp: 0.4
sleep <beats>
```

- 音域: ルートはオクターブ 3（C4=60 基準）、ベースはオクターブ 2。
- 小節を `max_seconds` まで順に詰める（break 条件: `total + secs > max_seconds`）。

## チャート（再掲）: quality → semitones

| quality | semitones |
| --- | --- |
| `maj` | 0,4,7 |
| `min` | 0,3,7 |
| `maj7` | 0,4,7,11 |
| `min7` | 0,3,7,10 |
| `7` | 0,4,7,10 |
| `sus4` | 0,5,7 |
| `dim` | 0,3,6 |
| `aug` | 0,4,8 |

## 音名 → MIDI PC（オクターブ 0 基準）

C=0 C#/Db=1 D=2 D#/Eb=3 E=4 F=5 F#/Gb=6 G=7 G#/Ab=8 A=9 A#/Bb=10 B=11