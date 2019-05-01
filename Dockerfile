FROM elixir:1.8-alpine AS build

RUN mix local.hex --force && mix local.rebar --force
RUN apk --no-cache add git

WORKDIR /build

COPY mix.exs .
COPY mix.lock .
COPY deps deps

ARG MIX_ENV=prod
ARG APP_VERSION=0.0.0
ENV MIX_ENV ${MIX_ENV}
ENV APP_VERSION ${APP_VERSION}

RUN mix deps.get

COPY lib lib
COPY test test
COPY config config
COPY rel rel

RUN mix release --env=${MIX_ENV}

### Minimal run-time image
FROM alpine:latest

RUN apk --no-cache add ncurses-libs openssl ca-certificates bash

RUN adduser -D app

ARG MIX_ENV=prod
ARG APP_VERSION=0.0.0

ENV MIX_ENV ${MIX_ENV}
ENV APP_VERSION ${APP_VERSION}

WORKDIR /opt/app

# Copy release from build stage
COPY --from=build /build/_build/${MIX_ENV}/rel/* ./

USER app

# Mutable Runtime Environment
RUN mkdir /tmp/app
ENV RELEASE_MUTABLE_DIR /tmp/app
ENV START_ERL_DATA /tmp/app/start_erl.data

# Start command
# NB 'myapp' should be replaced by your application name, as per mix.exs
CMD ["/opt/app/bin/tmate", "foreground"]
