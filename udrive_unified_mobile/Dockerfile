FROM ghcr.io/cirruslabs/flutter:stable AS builder
WORKDIR /app

# Kept for compatibility with the existing Railway service variable, but no
# longer used: the web build renders maps with flutter_map and never loads the
# Google Maps JavaScript API. The variable can be deleted from Railway.
ARG MAPS_WEB_KEY=""

COPY pubspec.yaml analysis_options.yaml ./
COPY assets ./assets
COPY lib ./lib
COPY web ./web

RUN echo "Web build uses flutter_map; no Google Maps key required."


RUN flutter config --enable-web \
    && flutter pub get \
    && flutter build web --release --no-wasm-dry-run

FROM nginx:1.27-alpine AS runner
COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template
EXPOSE 8080
CMD ["/bin/sh", "-c", "envsubst '$PORT' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
