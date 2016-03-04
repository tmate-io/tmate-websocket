defmodule Tmate.Stats do
  # We want median, 90th and 99th percentile
  @percentiles [50, 90, 99]
  @compression_interval 10
  @error 0.005

  def new do
    iv = :quantile_estimator.f_targeted(Enum.map(@percentiles, & {&1/100, @error}))
    %{qe: :quantile_estimator.new(iv),
      n: 0, s1: 0, s2: 0}
  end

  def insert(%{qe: qe, n: n, s1: s1, s2: s2}=state, value) do
    qe = :quantile_estimator.insert(value, qe)
    if (qe.inserts_since_compression >= @compression_interval) do
      qe = :quantile_estimator.compress(qe)
    end

    n  = n + 1
    s1 = s1 + value
    s2 = s2 + value*value

    %{state | qe: qe, n: n, s1: s1, s2: s2}
  end

  def insert(_state, value) do
    # Legacy code upgrade
    insert(new, value)
  end

  def has_stats?(%{n: n}), do: n >= 2
  def n(%{n: n}), do: n

  def median(%{qe: qe}), do: :quantile_estimator.quantile(0.50, qe)
  def p90(%{qe: qe}),    do: :quantile_estimator.quantile(0.90, qe)
  def p99(%{qe: qe}),    do: :quantile_estimator.quantile(0.99, qe)

  def mean(%{n: n, s1: s1}), do: s1/n
  def stddev(%{n: n, s1: s1, s2: s2}), do: :math.sqrt((n*s2 - s1*s1) / (n*(n-1)))
end
