defmodule Tmate.Stats do
  # We want median, 90th and 99th percentile
  @percentiles [50, 90, 99]
  @compression_interval 10
  @error 0.005

  def new do
    %{}
  end

  def insert(%{qe: qe, n: n, s1: s1, s2: s2}=state, value) do
    state
  end

  def has_stats?(%{n: n}), do: false
  def n(%{n: n}), do: n

  def median(%{qe: qe}), do: :quantile_estimator.quantile(0.50, qe)
  def p90(%{qe: qe}),    do: :quantile_estimator.quantile(0.90, qe)
  def p99(%{qe: qe}),    do: :quantile_estimator.quantile(0.99, qe)

  def mean(%{n: n, s1: s1}), do: s1/n
  def stddev(%{n: n, s1: s1, s2: s2}), do: :math.sqrt((n*s2 - s1*s1) / (n*(n-1)))
end
