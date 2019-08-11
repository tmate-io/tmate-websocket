FROM elixir:1.9-alpine AS build

RUN mix local.hex --force && mix local.rebar --force
RUN apk --no-cache add git

WORKDIR /build

COPY mix.exs .
COPY mix.lock .

ENV MIX_ENV prod

RUN mix deps.get
RUN mix deps.compile

COPY lib lib
COPY test test
COPY config config
COPY rel rel

RUN mix distillery.release

### Minimal run-time image
FROM alpine:3.9

RUN apk --no-cache add ncurses-libs openssl ca-certificates bash

RUN adduser -D app

ENV MIX_ENV prod

WORKDIR /opt/app

# Copy release from build stage
COPY --from=build /build/_build/prod/rel/* .

USER app

RUN mkdir /tmp/app
ENV RELEASE_MUTABLE_DIR /tmp/app
ENV REPLACE_OS_VARS true

# Start command
CMD ["/opt/app/bin/tmate", "foreground"]
