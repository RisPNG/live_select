ExUnit.start()

Application.put_env(:phoenix, :json_library, JSON)

Application.put_env(:live_select, LiveSelect.TestEndpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("live_select_test", 4),
  live_view: [signing_salt: "live_select_test"],
  pubsub_server: LiveSelect.TestPubSub,
  server: false
)

{:ok, _supervisor} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: LiveSelect.TestPubSub},
      LiveSelect.TestEndpoint
    ],
    strategy: :one_for_one
  )
