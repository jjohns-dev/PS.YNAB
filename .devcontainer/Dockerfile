# use the 730MB sdk image to build
FROM mcr.microsoft.com/dotnet/sdk AS builder

# install the latest version of PowerShell
RUN dotnet tool install -g PowerShell

# install git (required by the Build/build.ps1 shim, which fetches the harness)
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# run powershell
ENTRYPOINT ["pwsh"]
