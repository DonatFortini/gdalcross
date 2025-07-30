#!/bin/bash

# Centralized version configuration
GDAL_VERSION="3.11.3"
PROJ_VERSION="9.5.0"
GEOS_VERSION="3.13.0"
SQLITE_VERSION="3460100"

# Platform targets
PLATFORMS=("linux" "windows")

# Logging functions
log() { echo "ℹ️  $1"; }
success() { echo "✅ $1"; }
error() { echo "❌ $1"; exit 1; }

# Create output directory
mkdir -p binaries

build_platform() {
    local platform=$1
    local dockerfile="docker/Dockerfile.$platform"
    
    log "Building $platform binaries..."
    
    if ! docker build -f "$dockerfile" \
        --build-arg GDAL_VERSION="$GDAL_VERSION" \
        --build-arg PROJ_VERSION="$PROJ_VERSION" \
        --build-arg GEOS_VERSION="$GEOS_VERSION" \
        --build-arg SQLITE_VERSION="$SQLITE_VERSION" \
        -t "gdal-$platform-binaries" .; then
        error "$platform build failed"
    fi

    # Create and prepare container
    docker run -d --name "temp-$platform-container" "gdal-$platform-binaries"
    mkdir -p "binaries/$platform"
    
    # Extract binaries
    log "Extracting $platform binaries..."
    docker cp "temp-$platform-container:/binaries/" "binaries/$platform/"
    
    # Extract data files
    docker cp "temp-$platform-container:/gdal-data" "binaries/$platform/"
    docker cp "temp-$platform-container:/proj-data" "binaries/$platform/"
    
    # Cleanup
    docker stop "temp-$platform-container"
    docker rm "temp-$platform-container"
    
    success "$platform build completed"
}

# Main build process
for platform in "${PLATFORMS[@]}"; do
    if [[ -f "docker/Dockerfile.$platform" ]]; then
        build_platform "$platform"
    else
        log "Skipping $platform - Dockerfile not found"
    fi
done

success "All builds completed! Binaries available in: binaries/"