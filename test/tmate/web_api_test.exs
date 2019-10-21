defmodule Tmate.WebApiTest do
  use ExUnit.Case
  use Plug.Test

  defp expect_error(func) do
    try do
      func.()
      raise "No error raised"
    catch
      _, _ -> nil
    end
  end

  defp register_new_session(registry, id, stoken, stoken_ro) do
    {registry_mod, registry_pid} = registry
    pid = spawn(fn -> receive do end end)
    registry_mod.register_session(registry_pid, pid, id, stoken, stoken_ro)
  end

  setup do
    registry = {Tmate.SessionRegistry, Tmate.SessionRegistry.WebApiTest}
    Tmate.SessionRegistry.start_link([name: Tmate.SessionRegistry.WebApiTest])

    session_opts = [webhooks: [], registry: registry]
    router = fn conn -> Tmate.WebApi.Router.call(conn, session_opts) end
    {:ok, router: router, registry: registry}
  end

  describe "/internal_api/get_stale_sessions" do
    test "authentication required", %{router: router} do
      conn = conn(:post, "/internal_api/get_stale_sessions", %{})
      expect_error(fn -> router.(conn) end)
      {status, _, _} = sent_resp(conn)
      assert status == 401

      conn = conn(:post, "/internal_api/get_stale_sessions", %{auth_key: "xxx"})
      expect_error(fn -> router.(conn) end)
      {status, _, _} = sent_resp(conn)
      assert status == 401
    end

    test "get stale sessions", %{router: router, registry: registry} do
      s1 = UUID.uuid1()
      s2 = UUID.uuid1()
      s3 = UUID.uuid1()
      s4 = UUID.uuid1()

      register_new_session(registry, s1, "s1", "s1ro")
      register_new_session(registry, s2, "s2", "s2ro")

      payload = %{auth_key: "internal_api_auth_token", session_ids: [s3, s4]}
      conn = conn(:post, "/internal_api/get_stale_sessions", payload)
      |> router.()

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body == %{"stale_ids" => [s3, s4]}
    end
  end
end
