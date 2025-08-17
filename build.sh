#!/bin/bash

GDAL_VERSION="3.11.3"
PROJ_VERSION="9.5.0"
GEOS_VERSION="3.13.0"
SQLITE_VERSION="3460100"

# Platform and architecture matrix
PLATFORMS=(
    "linux/amd64"
    "linux/arm64"
    "windows/amd64"
    "macos/arm64"
)

log() { echo "ℹ️  $1"; }
success() { echo "✅ $1"; }
error() { echo "❌ $1"; exit 1; }

build_platform() {
    local platform_arch=$1
    IFS='/' read -r platform arch <<< "$platform_arch"
    local dockerfile="docker/Dockerfile.$platform"
    
    [[ ! -f "$dockerfile" ]] && { log "Skipping $platform - Dockerfile not found"; return; }
    
    log "Building $platform $arch binaries..."
    
    local build_args=(
        -f "$dockerfile"
        --build-arg GDAL_VERSION="$GDAL_VERSION"
        --build-arg PROJ_VERSION="$PROJ_VERSION"
        --build-arg GEOS_VERSION="$GEOS_VERSION"
        --build-arg SQLITE_VERSION="$SQLITE_VERSION"
    )
    
    # Add architecture arguments
    if [[ "$platform" == "linux" ]]; then
        build_args+=(--build-arg TARGETARCH="$arch")
    fi
    
    build_args+=(-t "gdal-$platform-$arch-binaries" .)
    
    docker build "${build_args[@]}" || error "$platform $arch build failed"

    docker run -d --name "temp-$platform-$arch-container" "gdal-$platform-$arch-binaries" || error "Failed to create $platform container"
    
    mkdir -p "dist/$platform/$arch"/{binaries,data/{gdal,proj}}
    
    log "Extracting $platform $arch binaries..."
    
    if [[ "$platform" == "linux" ]]; then
        docker cp "temp-$platform-$arch-container:/linux/binaries/." "dist/$platform/$arch/binaries/"
        docker cp "temp-$platform-$arch-container:/linux/data/gdal/." "dist/$platform/$arch/data/gdal/"
        docker cp "temp-$platform-$arch-container:/linux/data/proj/." "dist/$platform/$arch/data/proj/"
    else
        docker cp "temp-$platform-$arch-container:/binaries/." "dist/$platform/$arch/binaries/"
        docker cp "temp-$platform-$arch-container:/gdal-data/." "dist/$platform/$arch/data/gdal/"
        docker cp "temp-$platform-$arch-container:/proj-data/." "dist/$platform/$arch/data/proj/"
    fi
    
    docker stop "temp-$platform-$arch-container" >/dev/null 2>&1
    docker rm "temp-$platform-$arch-container" >/dev/null 2>&1
    
    success "$platform $arch build completed"
}

cleanup_docker() {
    log "Cleaning up Docker images and build cache..."
    for platform_arch in "${PLATFORMS[@]}"; do
        IFS='/' read -r platform arch <<< "$platform_arch"
        docker rmi "gdal-$platform-$arch-binaries" >/dev/null 2>&1 || true
    done

    docker image prune -f >/dev/null 2>&1 || true    
    success "Docker cleanup completed"
}

for platform_arch in "${PLATFORMS[@]}"; do
    build_platform "$platform_arch"
done

success "All builds completed!"

cleanup_docker