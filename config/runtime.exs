import Config

config :bye_bye_bye,
  mbta_api_key: System.get_env("MBTA_API_KEY"),
  mbta_api_url: System.get_env("MBTA_API_URL", "https://api-v3.mbta.com"),
  s3_bucket: System.get_env("S3_BUCKET")
