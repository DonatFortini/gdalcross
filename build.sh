#!/bin/bash


mkdir -p binaries/linux

log() {
    echo "ℹ️  $1"
}

success() {
    echo "✅ $1"
}

error() {
    echo "❌ $1"
}

# Build Linux version
log "Building Linux static binaries for GDAL tools..."
if docker build -f Dockerfile.linux -t gdal-binaries .; then
    log "Creating container to extract binaries..."
    docker run -d --name temp-container gdal-binaries
    
    log "Copying binaries..."
    docker cp temp-container:/binaries/gdalinfo binaries/linux/
    docker cp temp-container:/binaries/ogr2ogr binaries/linux/
    docker cp temp-container:/binaries/ogrinfo binaries/linux/
    docker cp temp-container:/binaries/gdal_rasterize binaries/linux/
    
    log "Copying data files..."
    docker cp temp-container:/gdal-data binaries/linux/gdal-data
    docker cp temp-container:/proj-data binaries/linux/proj-data
    
    log "Cleaning up..."
    docker stop temp-container
    docker rm temp-container
    
    success "Static binaries built successfully!"
    echo "Binaries located in: binaries/linux"
    echo "Data files located in: binaries/linux/gdal-data and binaries/linux/proj-data"
else
    error "Build failed"
    exit 1
fi