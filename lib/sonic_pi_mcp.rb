#!/usr/bin/env ruby
# frozen_string_literal: true

# sonic_pi_mcp.rb — Sonic Pi ワークフロー用 MCP サーバー (Ruby)
#
# music-json (design repo) を読み、Sonic Pi のコード (Ruby DSL) を生成し、
# OSC (UDP 4557) で Sonic Pi Spider へ送信 / 録音する。
# MCP (JSON-RPC 2.0 over stdio) として動作。
#
# Tools:
#   se_preview         — music-json → Sonic Pi コード文字列を返す (レンダリングなし)
#   se_render          — music-json → Sonic Pi コード生成 → 3秒 mp3 レンダリング
#   se_workflow_yaml   — YAML 指示ファイルからワークフロー実行
#   sp_status          — Sonic Pi Spider の稼働状態を確認

require "json"
require "socket"
require "timeout"
require "yaml"

DESIGN_HOME = ENV.fetch("SG_DESIGN_HOME", File.expand_path("~/repo/show-builder"))
SONIC_PI_DIR = "/usr/lib/sonic-pi/app/server/ruby"
SPIDER_OSC_PORT = Integer(ENV.fetch("SPIDER_OSC_PORT", "4557"))
SOLO_OSC_PORT = Integer(ENV.fetch("SOLO_OSC_PORT", "4558"))
SAMPLE_RATE = ENV.fetch("SAMPLE_RATE", "44100").to_i

# ---- MCP base (JSON-RPC 2.0 over stdio) ----

class MCPServer
  def initialize(name:, version: "0.1.0")
    @name = name
    @version = version
    @tools = {}
  end

  def register_tool(name, description, input_schema, &handler)
    @tools[name] = { description: description, schema: input_schema, handler: handler }
  end

  def handle(req)
    method = req["method"]
    id = req["id"]
    params = req["params"] || {}

    case method
    when "initialize"
      { "jsonrpc" => "2.0", "id" => id, "result" => {
          "protocolVersion" => "2024-11-05",
          "capabilities" => { "tools" => {} },
          "serverInfo" => { "name" => @name, "version" => @version } } }
    when "tools/list"
      { "jsonrpc" => "2.0", "id" => id, "result" => {
          "tools" => @tools.map { |name, t|
            { "name" => name, "description" => t[:description],
              "inputSchema" => { "type" => "object",
                                 "properties" => t[:schema]["properties"],
                                 "required" => t[:schema]["required"] } } } } }
    when "tools/call"
      name = params["name"]
      args = params["arguments"] || {}
      tool = @tools[name]
      if tool.nil?
        return { "jsonrpc" => "2.0", "id" => id, "result" => {
                   "content" => [{ "type" => "text", "text" => "Error: unknown tool #{name}" }] } }
      end
      begin
        text = tool[:handler].call(args)
        { "jsonrpc" => "2.0", "id" => id, "result" => {
            "content" => [{ "type" => "text", "text" => text.to_s }] } }
      rescue StandardError => e
        { "jsonrpc" => "2.0", "id" => id, "result" => {
            "content" => [{ "type" => "text", "text" => "Error: #{e.message}" }] } }
      end
    when "initialized"
      nil
    else
      nil
    end
  end

  def run
    $stdin.each_line do |line|
      line = line.strip
      next if line.empty?
      begin
        req = JSON.parse(line)
        resp = handle(req)
        if resp
          $stdout.puts JSON.generate(resp, ascii_only: false)
          $stdout.flush
        end
      rescue JSON::ParserError
        nil
      end
    end
  end
end

# ---- Sonic Pi utilities ----

module SonicPiHelper
  module_function

  # OSC メッセージを UDP で送る (簡易 OSC エンコーダ)
  def send_osc(host, port, address, *args)
    bytes = osc_pack(address, args)
    UDPSocket.new.tap do |s|
      s.connect(host, port)
      s.send(bytes, 0)
      s.close
    end
  end

  def osc_pad(str)
    str + "\x00" * ((4 - (str.bytesize % 4)) % 4)
  end

  def osc_address(str)
    osc_pad(str).bytes
  end

  def osc_types(types)
    osc_pad("," + types).bytes
  end

  def osc_arg_int(val)
    [val].pack("N").bytes
  end

  def osc_arg_float(val)
    [val].pack("g").bytes
  end

  def osc_arg_string(val)
    osc_pad(val).bytes
  end

  def osc_pack(address, args)
    out = osc_address(address)
    types = []
    data = []
    args.each do |a|
      case a
      when Integer
        types << "i"
        data.concat osc_arg_int(a)
      when Float
        types << "f"
        data.concat osc_arg_float(a)
      when String
        types << "s"
        data.concat osc_arg_string(a)
      end
    end
    out.concat osc_types(types.join)
    out.concat data
    out.pack("C*")
  end

  def load_music(rel)
    path = File.expand_path(rel, DESIGN_HOME)
    raise "music-json not found: #{path}" unless File.exist?(path)
    JSON.parse(File.read(path))
  end

  NOTE_TO_MIDI = {
    "C" => 0, "C#" => 1, "Db" => 1, "D" => 2, "D#" => 3, "Eb" => 3,
    "E" => 4, "F" => 5, "F#" => 6, "Gb" => 6, "G" => 7, "G#" => 8,
    "Ab" => 8, "A" => 9, "A#" => 10, "Bb" => 10, "B" => 11
  }.freeze

  CHORD_INTERVALS = {
    "maj" => [0, 4, 7], "min" => [0, 3, 7], "maj7" => [0, 4, 7, 11],
    "min7" => [0, 3, 7, 10], "7" => [0, 4, 7, 10], "sus4" => [0, 5, 7],
    "dim" => [0, 3, 6], "aug" => [0, 4, 8]
  }.freeze

  def midi_from_root(root, octave = 3)
    pc = NOTE_TO_MIDI.fetch(root.to_s.capitalize, 0)
    (octave + 1) * 12 + pc # C4 = 60
  end

  def chord_midi(root, quality, octave = 3)
    base = midi_from_root(root, octave)
    CHORD_INTERVALS.fetch(quality.to_s, CHORD_INTERVALS["maj"]).map { |iv| base + iv }
  end

  # music-json → Sonic Pi Ruby コード
  def music_to_sp(music, max_seconds: nil)
    tempo = music["tempo"] || 72
    bars = music["bars"] || []
    lines = []
    lines << "# #{music["title"]}"
    lines << "use_bpm #{tempo}"
    total = 0.0
    bars.each do |bar|
      chord = bar["chord"] || {}
      root = chord["root"]
      quality = chord["quality"] || "maj"
      beats = chord["beats"] || 4
      secs = beats * 60.0 / tempo
      break if max_seconds && total + secs > max_seconds
      total += secs
      notes = chord_midi(root, quality, 3)
      bass = chord_midi(root, quality, 2).first
      lines << "# bar #{bar["bar"]} (#{root}#{quality}, #{secs.round(2)}s)"
      lines << "use_synth :saw"
      lines << "play_chord #{notes.inspect}, release: #{(secs - 0.1).round(2)}, amp: 0.25"
      lines << "use_synth :sine"
      lines << "play #{bass}, release: #{(secs - 0.1).round(2)}, amp: 0.4"
      lines << "sleep #{beats}"
    end
    lines.join("\n") + "\n"
  end

  def spider_alive?(host = "127.0.0.1")
    Timeout.timeout(1) do
      begin
        s = UDPSocket.new
        s.connect(host, SPIDER_OSC_PORT)
        s.send([0].pack("N"), 0) # ping-ish
        s.close
        true
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
        false
      end
    end
  rescue Timeout::Error
    false
  end

  def send_code(code, host = "127.0.0.1", id = 1)
    # OSC 規約: /run-code は [gui_id:int, code:string] の2引数。
    # Sonic Pi の sonic-pi-server.rb は args[0]→gui_id, args[1]→string として eval する。
    send_osc(host, SPIDER_OSC_PORT, "/run-code", id, code)
  end
end

# ---- tool implementations ----

server = MCPServer.new(name: "sonic-pi-mcp", version: "0.1.0")

server.register_tool(
  "se_preview",
  "music-json → Sonic Pi コード文字列を返す (レンダリングなし)",
  { "properties" => {
      "music" => { "type" => "string", "description" => "design repo 内 music-json path" } },
    "required" => [] }
) do |args|
  music = SonicPiHelper.load_music(args["music"] || "music/lo-fi-radio-amin.json")
  SonicPiHelper.music_to_sp(music)
end

server.register_tool(
  "se_render",
  "music-json → Sonic Pi コード → 3秒 mp3 レンダリング (Spider OSC)",
  { "properties" => {
      "music" => { "type" => "string", "description" => "design repo 内 music-json path" },
      "out" => { "type" => "string", "description" => "出力 mp3 path" } },
    "required" => [] }
) do |args|
  music = SonicPiHelper.load_music(args["music"] || "music/lo-fi-radio-amin.json")
  out = File.expand_path(args["out"] || "out/se/se.mp3")
  max_sec = (args["max_seconds"] || 3).to_f
  code = SonicPiHelper.music_to_sp(music, max_seconds: max_sec)

  unless SonicPiHelper.spider_alive?
    raise "Sonic Pi Spider is not running. Start: ruby #{SONIC_PI_DIR}/bin/sonic-pi-server.rb --headless"
  end

  SonicPiHelper.send_code(code)

  # 録音待ち (Spider 側の録音コマンドは別途。一旦コード送信までを返す)
  FileUtils.mkdir_p(File.dirname(out))
  rb_out = out.sub(/\.mp3\z/, ".rb")
  File.write(rb_out, code)
  "code sent to Spider (#{max_sec}s)\nwrote code: #{rb_out}\nNOTE: mp3 化は Sonic Pi の録音機能 (record) 経由。Spider が alive なら手動で再録音可。"
end

server.register_tool(
  "sp_status",
  "Sonic Pi Spider の稼働状態を確認",
  { "properties" => {}, "required" => [] }
) do |_args|
  alive = SonicPiHelper.spider_alive?
  "Sonic Pi Spider (port #{SPIDER_OSC_PORT}): #{alive ? "OK" : "not running"}"
end

server.register_tool(
  "se_workflow_yaml",
  "YAML 指示ファイルから Sonic Pi ワークフローを実行 (recipe/se.yaml)",
  { "properties" => { "yaml_file" => { "type" => "string" } }, "required" => [] }
) do |args|
  yf = File.expand_path(args["yaml_file"] || "recipe/se.yaml")
  raise "yaml not found: #{yf}" unless File.exist?(yf)
  cfg = YAML.safe_load(File.read(yf))
  music_path = cfg.dig("music", "path") || "music/lo-fi-radio-amin.json"
  max_sec = cfg.dig("music", "max_seconds") || 3.0
  out = cfg.dig("publish", "out") || "out/se/se.mp3"
  music = SonicPiHelper.load_music(music_path)
  code = SonicPiHelper.music_to_sp(music, max_seconds: max_sec.to_f)
  old = SonicPiHelper.spider_alive?
  msgs = ["music: #{music_path}", "code lines: #{code.lines.size}"]
  msgs << (old ? "spider: OK (code 準備完了)" : "spider: not running — 起動後に #se_render で送信")
  msgs.join("\n")
end

server.run