FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY UDrive.Api.csproj ./
RUN dotnet restore UDrive.Api.csproj
COPY . .
RUN dotnet publish UDrive.Api.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 udrive \
    && useradd --system --uid 10001 --gid udrive --home-dir /app udrive

WORKDIR /app
COPY --from=build --chown=udrive:udrive /app/publish .
RUN mkdir -p /app/uploads && chown -R udrive:udrive /app/uploads

ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
ENV UPLOAD_ROOT=/app/uploads
USER udrive
EXPOSE 8080
ENTRYPOINT ["dotnet", "UDrive.Api.dll"]
