# Build stage
FROM dart:stable AS build

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart compile exe bin/server.dart -o bin/server

# Production stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/bin/server /app/server

ENV PIXEZ_HOST=0.0.0.0
ENV PIXEZ_PORT=8080
ENV PIXEZ_DATA_DIR=/data

VOLUME ["/data"]
EXPOSE 8080

ENTRYPOINT ["/app/server"]
