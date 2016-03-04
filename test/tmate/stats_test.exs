defmodule Tmate.StatsTest do
  use ExUnit.Case, async: true
  alias Tmate.Stats

  setup do
    {:ok, Stats.new}
  end

  def seed(s, input \\ (0..100)) do
    input |> Enum.reduce(s, & Stats.insert(&2, &1))
  end

  test "has_stats?", s do
    assert Stats.has_stats?(s) == false
    s = Stats.insert(s, 1)
    assert Stats.has_stats?(s) == false
    s = Stats.insert(s, 2)
    assert Stats.has_stats?(s) == true
  end

  test "stats", s do
    s = seed(s)
    assert Stats.n(s) == 101
    assert Stats.mean(s) == 50
    assert Stats.stddev(s) |> Float.round(3) == 29.3
    assert Stats.median(s) == 51
    assert Stats.p90(s) == 91
    assert Stats.p99(s) == 100
  end
end
