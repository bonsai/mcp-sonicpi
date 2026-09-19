# elixir_osc_spi.exs — Elixir から Sonic Pi に OSC 送信するデモ
#
# 使い方:  elixir elixir_osc_spi.exs
#
# プロトコル: UDP 127.0.0.1:4557, osc address "/run-code"
# 引数: [gui_id:int, code:string]  ※ Sonic Pi は args[1] を utf-8 として __spider_eval する

defmodule SpiOSC do
  @port 4557
  @host ~c"127.0.0.1"

  # OSC エンコード（string: 4byte パディング、int: big-endian）
  defp pad(s), do: s <> String.duplicate("\0", rem(4 - rem(byte_size(s), 4), 4))

  def encode(address, args) do
    tags = "," <> Enum.map_join(args, fn
      %{t: :int} -> "i"
      %{t: :str} -> "s"
    end)

    payload =
      pad(address) <>
      pad(tags) <>
      Enum.map_join(args, fn
        %{t: :int, v: v} -> <<v::32>>
        %{t: :str, v: s} -> pad(s)
      end)

    payload
  end

  def run_code(code, gui_id \\ 1) do
    payload = encode("/run-code", [%{t: :int, v: gui_id}, %{t: :str, v: code}])
    {:ok, sock} = :gen_udp.open(0, [:binary, active: false])
    :ok = :gen_udp.send(sock, @host, @port, payload)
    :gen_udp.close(sock)
    IO.puts("sent #{byte_size(payload)} bytes to #{@host}:#{@port}")
  end
end

# 実際に音を出すコード
code = """
use_bpm 100
4.times do |i|
  use_synth :beep
  play 60 + i * 4, release: 0.15
  sleep 0.5
end
"""

SpiOSC.run_code(code, 1)
IO.puts("done")