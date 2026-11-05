import Config

config :bye_bye_bye,
  mbta_api_key: "test_api_key",
  mbta_api_url: "http://test-api.example.com",
  mbta_client_extra_opts: [plug: {Req.Test, :mbta_api}, retry: false]

config :logger, level: :warning
