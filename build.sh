#!/bin/bash

GDAL_VERSION="3.11.3"
PROJ_VERSION="9.5.0"
GEOS_VERSION="3.13.0"
SQLITE_VERSION="3460100"

PLATFORMS=("linux" "windows" "macos")

log() { echo "ℹ️  $1"; }
success() { echo "✅ $1"; }
error() { echo "❌ $1"; exit 1; }



build_platform() {
    local platform=$1
    local dockerfile="docker/Dockerfile.$platform"
    
    log "Building $platform binaries..."
    
    # Build and load the image into Docker
    if ! docker build -f "$dockerfile" \
        --build-arg GDAL_VERSION="$GDAL_VERSION" \
        --build-arg PROJ_VERSION="$PROJ_VERSION" \
        --build-arg GEOS_VERSION="$GEOS_VERSION" \
        --build-arg SQLITE_VERSION="$SQLITE_VERSION" \
        --load \
        -t "gdal-$platform-binaries" .; then
        error "$platform build failed"
    fi

    # Create and prepare container
    if ! docker run -d --name "temp-$platform-container" "gdal-$platform-binaries"; then
        error "Failed to create $platform container"
    fi
    
    mkdir -p "$platform"
    mkdir -p "$platform/binaries"
    mkdir -p "$platform/data"
    mkdir -p "$platform/data/gdal"
    mkdir -p "$platform/data/proj"
    
    # Extract binaries with error checking
    log "Extracting $platform binaries..."
    if ! docker cp "temp-$platform-container:/binaries/." "$platform/binaries/"; then
        log "Warning: Failed to extract binaries for $platform"
    fi
    
    # Extract data files with error checking
    if ! docker cp "temp-$platform-container:/gdal-data" "$platform/data/gdal/"; then
        log "Warning: Failed to extract GDAL data for $platform"
    fi

    if ! docker cp "temp-$platform-container:/proj-data" "$platform/data/proj/"; then
        log "Warning: Failed to extract PROJ data for $platform"
    fi
    
    # Cleanup
    docker stop "temp-$platform-container" || log "Warning: Failed to stop container"
    docker rm "temp-$platform-container" || log "Warning: Failed to remove container"
    
    success "$platform build completed"
}


for platform in "${PLATFORMS[@]}"; do
    if [[ -f "docker/Dockerfile.$platform" ]]; then
        build_platform "$platform"
    else
        log "Skipping $platform - Dockerfile not found"
    fi
done

success "All builds completed! Binaries available in: binaries/"