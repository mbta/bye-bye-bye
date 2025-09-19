defmodule ByeByeBye.Utils do
  alias ByeByeBye.MbtaClient
  alias TransitRealtime.FeedEntity
  alias TransitRealtime.TripUpdate
  alias TransitRealtime.TripDescriptor
  alias TransitRealtime.TripUpdate.StopTimeUpdate

  @doc """
  Determines if the given datetime falls within the current service day.
  A service day runs from 3am to 3am the next day.

  The datetime now will be converted to Eastern time if it is not already.
  """
  def current_service_day?(datetime, now) do
    now = now |> DateTime.shift_zone!("America/New_York")
    service_day(datetime) == service_day(now)
  end

  @doc """
  Gets the service day date for a given datetime.
  Times before 3am are considered part of the previous day's service.
  """
  def service_day(datetime) do
    datetime = DateTime.shift_zone!(datetime, "America/New_York")
    time = DateTime.to_time(datetime)

    if Time.before?(time, ~T[03:00:00]) do
      datetime
      |> DateTime.add(-1, :day)
      |> DateTime.to_date()
    else
      DateTime.to_date(datetime)
    end
  end

  @doc """
  Builds a GTFS-RT FeedEntity representing a cancelled trip.

  ## Parameters
    * `{trip_id, schedule}` - A tuple containing:
      * `trip_id` - The ID of the cancelled trip
      * `schedule` - List of schedule entries for the trip
    * `now` - Current timestamp as DateTime

  ## Returns
  A `TransitRealtime.FeedEntity` struct with:
    * The trip marked as CANCELED
    * All stops marked as SKIPPED
  """
  def build_cancellation_entity({trip_id, schedule}, now) do
    route_id = schedule |> List.first() |> get_in(["relationships", "route", "data", "id"])

    start_date = now |> service_day() |> Calendar.strftime("%Y%m%d")

    %FeedEntity{
      id: trip_id,
      trip_update: %TripUpdate{
        timestamp: DateTime.to_unix(now),
        trip: %TripDescriptor{
          trip_id: trip_id,
          route_id: route_id,
          schedule_relationship: "CANCELED",
          start_date: start_date
        },
        stop_time_update: Enum.map(schedule, &schedule_to_stop_time_update/1)
      }
    }
  end

  defp schedule_to_stop_time_update(schedule) do
    %StopTimeUpdate{
      stop_id: schedule["relationships"]["stop"]["data"]["id"],
      stop_sequence: schedule["attributes"]["stop_sequence"],
      schedule_relationship: "SKIPPED"
    }
  end

  @doc """
  Gets schedules affected by a cancellation alert.
  Returns a map of trip_id to schedule entries.

  ## Parameters
    * `alert` - The alert to process
    * `now` - Current time as DateTime, used to determine service day
  """
  def get_affected_schedules(alert, now) do
    period_params =
      alert["attributes"]["active_period"]
      |> Enum.map(&period_params(&1, now))
      |> Enum.filter(& &1)

    trips =
      alert["attributes"]["informed_entity"]
      |> Enum.filter(fn entity -> !entity["stop"] && entity["trip"] end)
      |> Enum.map(& &1["trip"])
      |> then(fn trips ->
        case trips do
          [] -> []
          _ -> [%{trips: trips}]
        end
      end)

    routes =
      alert["attributes"]["informed_entity"]
      |> Enum.filter(fn entity -> !entity["stop"] && !entity["trip"] && entity["route"] end)
      |> Enum.map(& &1["route"])
      |> then(fn routes ->
        case routes do
          [] -> []
          _ -> [%{routes: routes}]
        end
      end)

    params = trips ++ routes

    params
    |> Enum.flat_map(&Enum.map(period_params, fn params -> Map.merge(params, &1) end))
    |> Enum.map(&MbtaClient.get_schedules/1)
    |> Enum.map(fn {:ok, schedules} -> schedules end)
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  @doc """
  Calculates the intersection of two time periods represented as DateTime tuples.

  ## Parameters
    * `{start1, end1}` - First time period as a tuple of DateTime objects
    * `{start2, end2}` - Second time period as a tuple of DateTime objects

  ## Returns
    * `{intersection_start, intersection_end}` - The overlapping period if the periods intersect
    * `nil` - If the periods do not intersect

  ## Examples

      iex> start1 = ~U[2024-01-01T10:00:00Z]
      iex> end1 = ~U[2024-01-01T14:00:00Z]
      iex> start2 = ~U[2024-01-01T12:00:00Z]
      iex> end2 = ~U[2024-01-01T16:00:00Z]
      iex> Utils.period_intersection({start1, end1}, {start2, end2})
      {~U[2024-01-01T12:00:00Z], ~U[2024-01-01T14:00:00Z]}
  """
  def period_intersection({start1, end1}, {start2, end2}) do
    latest_start = Enum.max([start1, start2], DateTime)
    earliest_end = Enum.min([end1, end2], DateTime)

    if DateTime.compare(latest_start, earliest_end) in [:lt, :eq] do
      {latest_start, earliest_end}
    else
      nil
    end
  end

  @doc """
  Recursively converts a Protox-generated struct to a plain Elixir map.

  This function removes Protox-specific fields (like `__uf__`) and converts
  all nested Protox structs to maps as well.

  ## Parameters
    * `struct` - A Protox-generated struct to convert

  ## Returns
    * A plain Elixir map with all nested Protox structs also converted to maps
    * For lists, each element is recursively converted
    * Non-struct values are returned unchanged

  ## Examples
      iex> ByeByeBye.Utils.protox_struct_to_map(%TransitRealtime.FeedEntity{id: "123", trip_update: %TransitRealtime.TripUpdate{}})
      %{
        id: "123",
        trip_update: %{
          delay: nil,
          stop_time_update: [],
          timestamp: nil,
          trip: nil,
          trip_properties: nil,
          vehicle: nil
        },
        alert: nil,
        is_deleted: nil,
        shape: nil,
        stop: nil,
        trip_modifications: nil,
        vehicle: nil
      }
  """
  def protox_struct_to_map(%_type{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__uf__)
    |> Enum.map(fn {k, v} -> {k, protox_struct_to_map(v)} end)
    |> Enum.into(%{})
  end

  def protox_struct_to_map(list) when is_list(list) do
    Enum.map(list, &protox_struct_to_map/1)
  end

  def protox_struct_to_map(other) do
    other
  end

  defp service_day_times(now) do
    service_day = service_day(now)
    start_dt = DateTime.new!(service_day, ~T[03:00:00], "America/New_York")

    end_dt =
      service_day
      |> Date.add(1)
      |> DateTime.new!(~T[02:59:59], "America/New_York")

    {start_dt, end_dt}
  end

  defp to_gtfs_time_string(datetime) do
    time =
      datetime
      |> DateTime.shift_zone!("America/New_York")
      |> DateTime.to_time()

    hour = if time.hour < 3, do: time.hour + 24, else: time.hour

    hour = hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = time.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    second = time.second |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{hour}:#{minute}:#{second}"
  end

  defp period_params(active_period, now) do
    {:ok, start_time, _} = DateTime.from_iso8601(active_period["start"])
    start_time = DateTime.shift_zone!(start_time, "America/New_York")

    end_time =
      if active_period["end"] do
        {:ok, end_time, _} = DateTime.from_iso8601(active_period["end"])
        DateTime.shift_zone!(end_time, "America/New_York")
      end

    {service_start_time, service_end_time} = service_day_times(now)

    end_time = end_time || service_end_time

    case period_intersection({start_time, end_time}, {service_start_time, service_end_time}) do
      nil ->
        nil

      {start_time, end_time} ->
        %{
          min_time: to_gtfs_time_string(start_time),
          max_time: to_gtfs_time_string(end_time)
        }
    end
  end
end
