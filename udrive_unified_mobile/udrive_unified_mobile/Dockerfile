FROM ghcr.io/cirruslabs/flutter:stable AS builder
WORKDIR /app

# No build arguments are needed.
#
# MAPS_WEB_KEY used to be declared here and was flagged by Docker's
# SecretsUsedInArgOrEnv rule — ARG values are recorded in the image history, so
# a key passed that way is readable by anyone who pulls the image. It is gone
# because the web build no longer uses a Google key at all: maps render through
# flutter_map, and tiles come from the API, which holds the key server-side.
#
# The MAPS_WEB_KEY variable can be deleted from the Railway service.

COPY pubspec.yaml analysis_options.yaml ./
COPY assets ./assets
COPY lib ./lib
COPY web ./web


RUN flutter config --enable-web \
    && flutter pub get \
    && flutter build web --release --no-wasm-dry-run

FROM nginx:1.27-alpine AS runner
COPY --from=builder /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/templates/default.conf.template
EXPOSE 8080
CMD ["/bin/sh", "-c", "envsubst '$PORT' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"]
