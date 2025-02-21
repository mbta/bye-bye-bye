defmodule ByeByeBye.Utils do
  alias ByeByeBye.MbtaClient
  alias TransitRealtime.FeedEntity
  alias TransitRealtime.TripUpdate
  alias TransitRealtime.TripDescriptor
  alias TransitRealtime.TripUpdate.StopTimeUpdate

  @doc """
  Determines if the given datetime falls within the current service day.
  A service day runs from 3am to 3am the next day.

  Accepts an optional function to get the current time, primarily for testing.
  The datetime from now_fn should be in UTC and will be converted to Eastern time.
  """
  def current_service_day?(datetime, now_fn \\ &DateTime.utc_now/0) do
    now = now_fn.() |> DateTime.shift_zone!("America/New_York")
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

  def build_cancellation_entity({trip_id, schedule}, now) do
    route_id = schedule |> List.first() |> get_in(["relationships", "route", "data", "id"])

    %FeedEntity{
      id: trip_id,
      trip_update: %TripUpdate{
        timestamp: now,
        trip: %TripDescriptor{
          trip_id: trip_id,
          route_id: route_id,
          schedule_relationship: "CANCELED"
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

  defp service_day_times(now) do
    now = DateTime.shift_zone!(now, "America/New_York")
    time = DateTime.to_time(now)

    if Time.before?(time, ~T[03:00:00]) do
      {
        now
        |> DateTime.add(-1, :day)
        |> DateTime.to_date()
        |> DateTime.new!(~T[03:00:00], "America/New_York"),
        now |> DateTime.to_date() |> DateTime.new!(~T[02:59:59], "America/New_York")
      }
    else
      {
        DateTime.to_date(now) |> DateTime.new!(~T[03:00:00], "America/New_York"),
        DateTime.add(now, 1, :day)
        |> DateTime.to_date()
        |> DateTime.new!(~T[02:59:59], "America/New_York")
      }
    end
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

    {:ok, end_time, _} = DateTime.from_iso8601(active_period["end"])
    end_time = DateTime.shift_zone!(end_time, "America/New_York")

    if current_service_day?(start_time, fn -> now end) or
         current_service_day?(end_time, fn -> now end) do
      {service_day_start_time, service_day_end_time} = service_day_times(now)

      start_time =
        if DateTime.before?(start_time, service_day_start_time),
          do: service_day_start_time,
          else: start_time

      end_time =
        if DateTime.after?(end_time, service_day_end_time),
          do: service_day_end_time,
          else: end_time

      %{
        min_time: to_gtfs_time_string(start_time),
        max_time: to_gtfs_time_string(end_time)
      }
    else
      nil
    end
  end
end
