FROM ghcr.io/cirruslabs/flutter:stable AS builder
WORKDIR /app
COPY . .
RUN flutter config --enable-web \
    && flutter create . --platforms=web --project-name=udrive_customer --org=com.udrive \
    && flutter pub get \
    && flutter build web --release

FROM node:20-bookworm-slim AS runner
RUN npm install --global serve@14.2.4
COPY --from=builder /app/build/web /site
EXPOSE 3000
CMD ["sh", "-c", "serve -s /site -l tcp://0.0.0.0:${PORT:-3000}"]
