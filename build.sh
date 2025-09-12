#!/bin/bash

GDAL_VERSION="3.11.3"
PROJ_VERSION="9.6.2"
GEOS_VERSION="3.13.0"
SQLITE_VERSION="3460100"

PLATFORMS=(
    "linux/amd64"
    "linux/arm64"
    "windows/amd64"
    "macos/arm64"
)

log() { echo "ℹ️  $1"; }
success() { echo "✅ $1"; }
error() { echo "❌ $1"; exit 1; }
warn() { echo "⚠️  $1"; }

verify_binary_architecture() {
    local binary_path=$1
    local expected_arch=$2
    local platform=$3
    
    if [[ "$platform" == "linux" ]]; then
        if command -v file >/dev/null 2>&1; then
            local file_output=$(file "$binary_path" 2>/dev/null)
            log "Binary info: $file_output"
            
            case "$expected_arch" in
                "amd64")
                    if echo "$file_output" | grep -q "x86-64\|x86_64"; then
                        success "✓ Architecture verified: x86_64/amd64"
                        return 0
                    else
                        warn "⚠ Architecture mismatch: expected amd64, got: $file_output"
                        return 1
                    fi
                    ;;
                "arm64")
                    if echo "$file_output" | grep -q "aarch64\|ARM64"; then
                        success "✓ Architecture verified: aarch64/arm64"
                        return 0
                    else
                        warn "⚠ Architecture mismatch: expected arm64, got: $file_output"
                        return 1
                    fi
                    ;;
                *)
                    warn "Unknown architecture: $expected_arch"
                    return 1
                    ;;
            esac
        else
            warn "file command not available for verification"
            return 0
        fi
    else
        log "Skipping architecture verification for $platform"
        return 0
    fi
}


get_binary_suffix() {
    local platform=$1
    local arch=$2
    
    case "$platform" in
        "linux")
            case "$arch" in
                "amd64") echo "x86_64-unknown-linux-gnu" ;;
                "arm64") echo "aarch64-unknown-linux-gnu" ;;
                "386") echo "i386-unknown-linux-gnu" ;;
                "arm") echo "arm-unknown-linux-gnu" ;;
                *) echo "unknown-linux-gnu" ;;
            esac
            ;;
        "windows")
            case "$arch" in
                "amd64") echo "x86_64-pc-windows-gnu.exe" ;;
                "386") echo "i686-pc-windows-gnu.exe" ;;
                *) echo "pc-windows-gnu.exe" ;;
            esac
            ;;
        "macos")
            case "$arch" in
                "amd64") echo "x86_64-apple-darwin" ;;
                "arm64") echo "aarch64-apple-darwin" ;;
                *) echo "apple-darwin" ;;
            esac
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

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
    
    if [[ "$platform" == "linux" ]]; then
        build_args+=(--build-arg TARGETARCH="$arch")
        log "Building with TARGETARCH=$arch"
    fi
    
    build_args+=(-t "gdal-$platform-$arch-binaries" .)
    
    log "Running: docker build ${build_args[*]}"
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
    
    log "Verifying extracted binaries for $platform $arch..."
    local expected_suffix=$(get_binary_suffix "$platform" "$arch")
    log "Expected binary suffix: $expected_suffix"
    
    local binary_dir="dist/$platform/$arch/binaries"
    if [[ -d "$binary_dir" ]]; then
        log "Binaries found in $binary_dir:"
        ls -la "$binary_dir"
        
        local verification_passed=true
        for binary in "$binary_dir"/*; do
            if [[ -f "$binary" ]]; then
                local binary_name=$(basename "$binary")
                log "Verifying binary: $binary_name"
                
                if [[ "$binary_name" == *"$expected_suffix"* ]] || [[ "$platform" != "linux" ]]; then
                    success "✓ Binary name format correct: $binary_name"
                else
                    warn "⚠ Binary name format unexpected: $binary_name (expected suffix: $expected_suffix)"
                    verification_passed=false
                fi

                if ! verify_binary_architecture "$binary" "$arch" "$platform"; then
                    verification_passed=false
                fi
            fi
        done
        
        if [[ "$verification_passed" == "true" ]]; then
            success "✅ All binaries verified successfully for $platform $arch"
        else
            warn "⚠️ Some binary verifications failed for $platform $arch"
        fi
    else
        error "No binaries directory found at $binary_dir"
    fi
 
    docker stop "temp-$platform-$arch-container" >/dev/null 2>&1
    docker rm "temp-$platform-$arch-container" >/dev/null 2>&1
    
    success "$platform $arch build completed"
}

show_build_summary() {
    log "Build Summary:"
    echo "=================================="
    
    for platform_arch in "${PLATFORMS[@]}"; do
        IFS='/' read -r platform arch <<< "$platform_arch"
        local binary_dir="dist/$platform/$arch/binaries"
        
        if [[ -d "$binary_dir" ]]; then
            echo "$platform/$arch:"
            for binary in "$binary_dir"/*; do
                if [[ -f "$binary" ]]; then
                    local binary_name=$(basename "$binary")
                    local size=$(du -h "$binary" | cut -f1)
                    echo "  - $binary_name ($size)"
                    
                    if [[ "$platform" == "linux" ]] && command -v file >/dev/null 2>&1; then
                        local arch_info=$(file "$binary" | grep -o "ELF [^,]*" | head -1)
                        echo "    Architecture: $arch_info"
                    fi
                fi
            done
            echo ""
        else
            echo "$platform/$arch: No binaries found"
            echo ""
        fi
    done
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


log "Starting GDAL cross-platform build..."
log "GDAL Version: $GDAL_VERSION"
log "PROJ Version: $PROJ_VERSION"
log "GEOS Version: $GEOS_VERSION"
log "SQLite Version: $SQLITE_VERSION"
echo ""

for platform_arch in "${PLATFORMS[@]}"; do
    build_platform "$platform_arch"
    echo ""
done

show_build_summary
success "All builds completed!"

cleanup_docker