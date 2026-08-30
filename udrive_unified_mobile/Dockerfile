FROM ghcr.io/cirruslabs/flutter:stable AS builder
WORKDIR /app

# Google Maps JavaScript API key.
#
# Passed in at build time, never committed. On Railway set a service variable
# named MAPS_WEB_KEY; Railway forwards it to the build as an ARG of the same
# name when it is declared here.
#
# Leaving it unset is safe: the placeholder stays in index.html, the map area
# renders blank, and everything else in the app still works.
ARG MAPS_WEB_KEY=""

COPY pubspec.yaml analysis_options.yaml ./
COPY assets ./assets
COPY lib ./lib
COPY web ./web

RUN if [ -n "$MAPS_WEB_KEY" ]; then \
        sed -i "s|YOUR_WEB_MAPS_API_KEY|$MAPS_WEB_KEY|g" web/index.html && \
        echo "Maps web key injected."; \
    else \
        echo "MAPS_WEB_KEY not set - map will render blank."; \
    fi

RUN flutter config --enable-web \
    && flutter pub get \
    && flutter build web --release --no-wasm-dry-run

FROM nginx:1.27-alpine AS runner
COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template
EXPOSE 8080
CMD ["/bin/sh", "-c", "envsubst '$PORT' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
