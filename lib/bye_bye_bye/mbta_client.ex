defmodule ByeByeBye.MbtaClient do
  @moduledoc """
  Client for interacting with the MBTA API.
  """

  alias ByeByeBye.Config
  require Logger

  @doc """
  Gets all current alerts from the MBTA API.

  ## Examples

      iex> MbtaClient.get_alerts()
      {:ok, alerts}
      {:error, reason}
  """
  def get_alerts do
    path = "/alerts"
    do_get_request(path)
  end

  @doc """
  Gets schedules filtered by trips or routes and optionally filtered by time window.

  ## Parameters
    * `opts` - Map or keyword list of options:
      * `:trips` - Filter by list of trip IDs
      * `:routes` - Filter by list of route IDs
      * `:min_time` - Filter schedule after this time (HH:MM format)
      * `:max_time` - Filter schedule before this time (HH:MM format)

  Only one of trips or routes must be provided, not both.

  ## Examples

      iex> MbtaClient.get_schedules(trips: ["123", "456"])
      {:ok, schedules}

      iex> MbtaClient.get_schedules(%{routes: ["Red", "Blue"], min_time: "2024-01-20T10:00:00-05:00"})
      {:ok, schedules}
  """
  def get_schedules(opts) when is_map(opts) do
    opts
    |> Enum.into([])
    |> get_schedules()
  end

  def get_schedules(opts) when is_list(opts) do
    with {:ok, params} <- validate_schedule_params(opts) do
      path = "/schedules"

      # Stop sequence is the only field we need to generate correct STUs
      params = Map.put(params, "fields[schedule]", "stop_sequence")

      case do_get_request(path, params: params) do
        {:ok, data} -> {:ok, schedules_by_trip(data)}
        error -> error
      end
    end
  end

  defp validate_schedule_params(opts) do
    trips = Keyword.get(opts, :trips)
    routes = Keyword.get(opts, :routes)

    cond do
      trips && routes ->
        {:error, "Cannot specify both trips and routes"}

      is_nil(trips) && is_nil(routes) ->
        {:error, "Must specify either trips or routes"}

      true ->
        params =
          opts
          |> Keyword.take([:min_time, :max_time])
          |> Enum.into(%{})
          |> maybe_add_filter("trip", trips)
          |> maybe_add_filter("route", routes)

        {:ok, params}
    end
  end

  defp maybe_add_filter(params, _key, nil), do: params

  defp maybe_add_filter(params, key, values) when is_list(values) do
    Map.put(params, key, Enum.join(values, ","))
  end

  defp schedules_by_trip(schedules) do
    schedules
    |> Enum.group_by(& &1["relationships"]["trip"]["data"]["id"])
    |> Enum.map(fn {trip_id, schedules} ->
      {trip_id, Enum.sort_by(schedules, & &1["attributes"]["stop_sequence"])}
    end)
    |> Enum.into(%{})
  end

  defp do_get_request(path, opts \\ []) do
    params_str = if params = opts[:params], do: " params=\"#{inspect(params)}\"", else: ""
    Logger.debug("Making MBTA API request path=#{path}#{params_str}")

    case Req.get("#{Config.mbta_api_url()}#{path}", request_options(opts)) do
      {:ok, %{status: 200, body: body}} ->
        Logger.debug(
          "Successful MBTA API response path=#{path} data_count=#{length(body["data"])}"
        )

        {:ok, body["data"]}

      {:ok, response} ->
        Logger.warning(
          "Unexpected MBTA API response path=#{path} status=#{response.status} body=\"#{inspect(response.body)}\""
        )

        {:error, "Unexpected response: #{inspect(response)}"}

      {:error, reason} = error ->
        Logger.error("MBTA API request failed path=#{path} error=\"#{inspect(reason)}\"")
        error
    end
  end

  defp request_options(opts) do
    opts = Keyword.put(opts, :headers, [{"x-api-key", Config.mbta_api_key()}])

    if Mix.env() == :test do
      opts ++ [plug: {Req.Test, :mbta_api}, retry: false]
    else
      opts
    end
  end
end
