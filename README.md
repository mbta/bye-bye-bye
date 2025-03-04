# ByeByeBye

## It keeps trips NSYNC!

Since 3rd party consumers handle cancelation alerts inconsistently, this
service monitors our alerts and issues a TripUpdates feed with cancellations
for any trips that are cancelled by an alert. Concentrate consumes this feed
ensuring that 3rd parties, especially trip planners, generate plans using
these cancelled trips.

## Building

The `bye_bye_bye` binary is built by running `mix escript.build`

## Docker

### Building the Docker Image

Build the Docker image with:

```bash
docker build -t bye_bye_bye .
```

### Running the Container

Run the container with:

```bash
# Run the container without the --rm flag to keep it after completion
docker run \
  -e MBTA_API_KEY=your_key \
  -e MBTA_API_URL=https://api-v3.mbta.com \
  --name bye_bye_bye_container \
  bye_bye_bye

# Copy the generated files from the container to your host
docker cp bye_bye_bye_container:/TripUpdates.json ./
docker cp bye_bye_bye_container:/TripUpdates.pb ./

# You can remove the container when done
docker rm bye_bye_bye_container
```

To write files to S3, include the S3 bucket and AWS credentials:

```bash
docker run --rm \
  -e MBTA_API_KEY=your_key \
  -e MBTA_API_URL=https://api-v3.mbta.com \
  -e S3_BUCKET=your-bucket-name \
  -e AWS_ACCESS_KEY_ID=your_aws_access_key \
  -e AWS_SECRET_ACCESS_KEY=your_aws_secret_key \
  bye_bye_bye
```

If no S3 bucket is configured, files will be written to the container's filesystem.
