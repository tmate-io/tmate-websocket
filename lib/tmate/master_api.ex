defmodule Tmate.MasterApi do
  def internal_api_opts do
    # XXX We can't pass the auth token directly, it is not
    # necessarily defined at compile time.
    Application.fetch_env!(:tmate, :master)[:internal_api]
  end
  use Tmate.Util.JsonApi, fn_opts: &__MODULE__.internal_api_opts/0

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
end
