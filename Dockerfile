# Build stage
FROM hexpm/elixir:1.20.2-erlang-29.0.4-alpine-3.24.1 AS builder
RUN apk add --no-cache protobuf
WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force


COPY . .
RUN mix deps.get

ENV MIX_ENV=prod

RUN mix compile && \
    mix escript.build

#Runtime stage
FROM hexpm/elixir:1.20.2-erlang-29.0.4-alpine-3.24.1



COPY --from=builder /app/bye_bye_bye /usr/local/bin/bye_bye_bye

ENTRYPOINT ["/usr/local/bin/bye_bye_bye"]
