FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /source
COPY global.json Directory.Build.props HospitalDashboard.slnx ./
COPY src/HospitalDashboard.Core/HospitalDashboard.Core.csproj src/HospitalDashboard.Core/
COPY src/HospitalDashboard.Client/HospitalDashboard.Client.csproj src/HospitalDashboard.Client/
COPY src/HospitalDashboard.Host/HospitalDashboard.Host.csproj src/HospitalDashboard.Host/
RUN dotnet restore src/HospitalDashboard.Host/HospitalDashboard.Host.csproj
COPY src/ src/
RUN dotnet publish src/HospitalDashboard.Host/HospitalDashboard.Host.csproj -c Release --no-restore -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
USER $APP_UID
ENTRYPOINT ["dotnet", "HospitalDashboard.Host.dll"]
