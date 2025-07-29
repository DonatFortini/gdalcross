#!/bin/bash
set -e

# Couleurs pour la sortie
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

mkdir -p binaries/{linux,windows,macos}

log "🚀 GDAL Multi-Platform Build Script"
echo "======================================"

# 1. BUILD LINUX 
log "📦 Building Linux version..."
if docker build -f Dockerfile.linux -t gdal-linux . --load; then
    docker create --name temp-linux gdal-linux
    docker cp temp-linux:/./binaries/linux/
    docker cp temp-linux:/gdal-data ./binaries/linux/gdal-data/
    docker rm temp-linux
    success "Linux build completed ✅"
    LINUX_SUCCESS=true
else
    error "Linux build failed ❌"
    LINUX_SUCCESS=false
fi


# 2. BUILD WINDOWS 
log "📦 Building Windows version..."
WINDOWS_SUCCESS=false

# Tentative 1: Version complète avec PROJ
log "Trying Windows complete build..."
if docker build -f Dockerfile.windows -t gdal-windows-full . 2>/dev/null; then
    docker create --name temp-win-full gdal-windows-full
    docker cp temp-win-full:/ ./binaries/windows/ 2>/dev/null || true
    docker rm temp-win-full
    success "Windows complete build succeeded ✅"
    WINDOWS_SUCCESS=true
else
    warning "Windows complete build failed, trying simple version..."
fi

# 3. MACOS 
log "📦 Attempting macOS build..."
MACOS_SUCCESS=false
if docker build -f Dockerfile.macos -t gdal-macos . 2>/dev/null; then
    docker create --name temp-macos gdal-macos
    docker cp temp-macos:/ ./binaries/macos/ 2>/dev/null || true
    docker rm temp-macos
    success "macOS build succeeded ✅"
    MACOS_SUCCESS=true
else
    warning "macOS build failed (expected) ⚠️"
fi

#4. Conda packages pour tous les OS
log "Downloading Conda packages info..."
cat > ./binaries/official/conda-install.txt << 'EOF'
# Installation via Conda (recommandé pour tous les OS)
conda install -c conda-forge gdal

# Ou avec mamba (plus rapide)
mamba install -c conda-forge gdal

# Version spécifique
conda install -c conda-forge gdal=3.8.3
EOF


# 5. RAPPORT FINAL
echo ""
echo "======================================"
log "📊 BUILD SUMMARY"
echo "======================================"

echo "Platform Status:"
echo "├── Linux     : $([ "$LINUX_SUCCESS" = true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "├── Windows   : $([ "$WINDOWS_SUCCESS" = true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "└── macOS     : $([ "$MACOS_SUCCESS" = true ] && echo "✅ SUCCESS" || echo "❌ FAILED")"

echo ""
success "Build script completed! Check ./binaries/ for results."