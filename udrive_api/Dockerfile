FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY UDrive.Api.csproj ./
RUN dotnet restore UDrive.Api.csproj
COPY . .
RUN dotnet publish UDrive.Api.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime

# `util-linux` supplies setpriv, which the entrypoint uses to drop privileges.
# Both packages are installed before the lists are deleted — installing after
# the `rm` would fail, because there would be nothing left to resolve against.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgssapi-krb5-2 util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 udrive \
    && useradd --system --uid 10001 --gid udrive --home-dir /app udrive

WORKDIR /app
COPY --from=build --chown=udrive:udrive /app/publish .
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false

# Defaults to the mounted volume, not a directory inside the image.
#
# It used to default to /app/uploads, which lives in the image and is destroyed
# on every deploy — taking every driver document, vehicle photograph and payment
# screenshot with it. Override it in Railway if the volume is mounted elsewhere.
ENV UPLOAD_ROOT=/data/uploads

# No `USER udrive` here.
#
# The entrypoint has to start as root to set ownership on the volume Railway
# mounts at /data — a chown at build time is hidden the moment the volume covers
# it — and then drops to uid 10001 before starting the API. The process still
# runs unprivileged; only the two lines that prepare the directory do not.
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
