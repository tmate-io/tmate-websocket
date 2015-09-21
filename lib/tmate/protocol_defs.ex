# tmate-protocol.h

defmodule Tmate.ProtocolDefs.Define do
  defmacro define(name, value) do
    quote do: (defmacro unquote(name), do: unquote(value))
  end

  defmacro enum(_enum_name, values) do
    values |> Enum.with_index |> Enum.map fn {name, index} ->
      quote do: (defmacro unquote(name), do: unquote(index))
    end
  end
end

defmodule Tmate.ProtocolDefs do
  import __MODULE__.Define

  define tmate_max_message_size, (17*1024)

  define control_protocol_version, 1

  enum tmate_control_out_msg_types, [
    tmate_ctl_auth,
    tmate_ctl_deamon_out_msg,
    tmate_ctl_keyframe,
  ]

  enum tmate_control_in_msg_types, [
    tmate_ctl_deamon_fwd_msg,
  ]

  enum tmate_daemon_out_msg_types, [
    tmate_out_header,
    tmate_out_sync_layout,
    tmate_out_pty_data,
    tmate_out_exec_cmd,
    tmate_out_failed_cmd,
    tmate_out_status,
    tmate_out_sync_copy_mode,
    tmate_out_write_copy_mode,
  ]

  enum tmate_daemon_in_msg_types, [
    tmate_in_notify,
    tmate_in_pane_key,
    tmate_in_resize,
    tmate_in_exec_cmd,
    tmate_in_set_env,
    tmate_in_ready,
  ]
end
