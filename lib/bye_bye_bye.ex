defmodule ByeByeBye do
  require Logger
  alias ByeByeBye.Utils
  alias TransitRealtime.FeedHeader
  alias TransitRealtime.FeedMessage
  alias ByeByeBye.MbtaClient
  alias ByeByeBye.Config

  @cancellation_effects ["NO_SERVICE", "CANCELLATION"]

  @doc """
  Filters alerts to include only those with cancellation effects.

  ## Parameters
    * `alerts` - List of alert maps from the MBTA API

  ## Returns
    A filtered list containing only the cancellation alerts
  """
  def get_cancellations(alerts) do
    cancellations = Enum.filter(alerts, &(&1["attributes"]["effect"] in @cancellation_effects))
    Logger.info("Found #{length(cancellations)} cancellations")
    cancellations
  end

  def main(_args) do
    Logger.info("Starting ByeByeBye service")

    case MbtaClient.get_alerts() do
      {:ok, alerts} ->
        now = DateTime.utc_now()
        now_unix = DateTime.to_unix(now)

        entities =
          alerts
          |> get_cancellations()
          |> Enum.map(&Utils.get_affected_schedules(&1, now))
          |> Enum.reduce(%{}, &Map.merge(&1, &2))
          |> tap(fn schedules ->
            Logger.info("Generated cancellation entities affected_trips=#{map_size(schedules)}")
          end)
          |> Enum.map(&Utils.build_cancellation_entity(&1, now))

        message = %FeedMessage{
          header: %FeedHeader{
            gtfs_realtime_version: "2.0",
            timestamp: now_unix
          },
          entity: entities
        }

        {json, pb} = encode_feeds(message)
        write_output(Config.s3_bucket(), json, pb)

      {:error, reason} ->
        Logger.error("Failed to fetch alerts error=\"#{inspect(reason)}\"")
    end
  end

  defp s3_put(bucket, path, data) do
    bucket
    |> ExAws.S3.put_object(path, data)
    |> ExAws.request()
  end

  defp encode_feeds(message) do
    with {:ok, json} <- message |> Utils.protox_struct_to_map() |> Jason.encode(),
         {:ok, pb} <- FeedMessage.encode(message),
         json = IO.iodata_to_binary(json),
         pb = IO.iodata_to_binary(pb) do
      {json, pb}
    else
      {:error, reason} ->
        Logger.error("Failed to encode message reason=\"#{inspect(reason)}\"")
        halt(1)
    end
  end

  defp write_output(nil, json, pb) do
    with :ok <- File.write("TripUpdates.json", json),
         :ok <- File.write("TripUpdates.pb", pb) do
      Logger.info("Successfully wrote TripUpdates to disk")
    else
      {:error, reason} ->
        Logger.error("Failed to write to filesystem reason=\"#{inspect(reason)}\"")
        halt(1)
    end
  end

  defp write_output(s3_bucket, json, pb) do
    with {:ok, _} <- s3_put(s3_bucket, "bye-bye-bye/TripUpdates.json", json),
         {:ok, _} <- s3_put(s3_bucket, "bye-bye-bye/TripUpdates.pb", pb) do
      Logger.info("Successfully wrote TripUpdates to S3 bucket=#{s3_bucket}")
    else
      {:error, reason} ->
        Logger.error("Failed to write to S3 error=\"#{inspect(reason)}\" bucket=#{s3_bucket}")

        halt(1)
    end
  end

  defp halt(code) do
    Logger.flush()
    System.halt(code)
  end
end
