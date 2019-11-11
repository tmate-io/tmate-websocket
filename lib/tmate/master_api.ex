defmodule Tmate.MasterApi do
  def internal_api_opts do
    # XXX We can't pass the auth token directly, it is not
    # necessarily defined at compile time.
    Application.fetch_env!(:tmate, :master)[:internal_api]
  end
  use Tmate.Util.JsonApi, fn_opts: &__MODULE__.internal_api_opts/0

  def enabled? do
    !!internal_api_opts()
  end

  def get_session(token) do
    case get("/session", [], params: %{token: token}) do
      {:ok, session} ->
        session =
          session
          |> with_atom_keys()
          |> as_timestamp(:disconnected_at)
          |> as_timestamp(:created_at)
        {:ok, session}
      {:error, 404} ->
        {:error, :not_found}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_named_session_tokens(api_key, stoken, stoken_ro) do
    params = %{api_key: api_key, stoken: stoken, stoken_ro: stoken_ro}
    # it's a post, so it's easier to use JSON (we want to use nil values)
    case post("/named_session_tokens", params) do
      {:ok, result} ->
        {:ok, {result["stoken"], result["stoken_ro"], result["generation"]}}
      {:error, 404} ->
        {:error, :not_found}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
