defmodule Tmate.MasterApi do
  use HTTPoison.Base

  def process_url(url) do
    {:ok, master_options} = Application.fetch_env(:tmate, :master)
    base_url = master_options[:internal_api][:base_url]
    base_url <> url
  end

  def process_request_headers(headers) do
    {:ok, master_options} = Application.fetch_env(:tmate, :master)
    auth_token = master_options[:internal_api][:auth_token]
    headers ++ [{"Authorization", "Bearer #{auth_token}"}]
  end
end
