defmodule ByeByeBye.Config do
  @moduledoc """
  Provides access to application configuration values.
  """

  @doc """
  Gets the MBTA API key from configuration
  """
  def mbta_api_key do
    Application.get_env(:bye_bye_bye, :mbta_api_key)
  end

  @doc """
  Gets the MBTA API URL from configuration
  """
  def mbta_api_url do
    Application.get_env(:bye_bye_bye, :mbta_api_url)
  end

  @doc """
  Gets the S3 bucket name from configuration. If blank should write files locally.
  """
  def s3_bucket do
    Application.get_env(:bye_bye_bye, :s3_bucket)
  end
end
