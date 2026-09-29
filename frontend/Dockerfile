# --- build ------------------------------------------------------------------
FROM ghcr.io/cirruslabs/flutter:3.41.9 AS build

# Baked into the JS bundle; this is the URL the *browser* uses to reach the API.
ARG API_BASE_URL=http://localhost:8000
# Optional public Mapbox token; empty falls back to OpenStreetMap tiles.
ARG MAPBOX_TOKEN=

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL} \
    --dart-define=MAPBOX_TOKEN=${MAPBOX_TOKEN}

# --- serve ------------------------------------------------------------------
FROM nginx:1.29-alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
