FROM elixir:1.9-alpine

RUN mix local.hex --force && mix local.rebar --force
RUN apk --no-cache add git

WORKDIR /src/tmate-websocket

COPY mix.exs .
COPY mix.lock .

ENV MIX_ENV dev

RUN mix deps.get
RUN mix deps.compile

COPY lib lib
COPY config config

RUN mix compile

CMD mkfifo console; sleep 1000d > console & cat console | \
  iex --name websocket@session \
      --cookie cookie \
      -S mix
