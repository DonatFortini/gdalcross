# Stage 1: Build GDAL and its dependencies
FROM ubuntu:22.04 AS builder

ARG TARGETARCH
ARG TARGETOS
ARG GDAL_VERSION
ARG PROJ_VERSION
ARG GEOS_VERSION
ARG SQLITE_VERSION

ENV DEBIAN_FRONTEND=noninteractive

ENV PREFIX_LINUX="/usr/local"
ENV PREFIX_DARWIN="/opt/macos-build"
ENV PREFIX_WINDOWS="/usr/x86_64-w64-mingw32"
ENV HOST_PREFIX="/usr/local"

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential cmake curl pkg-config autoconf automake libtool && \
    if [ "$TARGETOS" = "linux" ]; then \
    apt-get install -y \
    tar zlib1g-dev; \
    elif [ "$TARGETOS" = "darwin" ]; then \
    apt-get install -y \
    wget git sqlite3 zlib1g-dev file python3 xz-utils clang llvm-dev \
    libz-dev libmpc-dev libmpfr-dev libgmp-dev libssl-dev ; \
    elif [ "$TARGETOS" = "windows" ]; then \
    apt-get install -y \
    sqlite3 gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix binutils-mingw-w64-x86-64; \
    fi && \
    rm -rf /var/lib/apt/lists/*

# OSXCross setup for macOS cross-compilation
RUN if [ "$TARGETOS" = "darwin" ]; then \
    cd /opt && \
    git clone https://github.com/tpoechtrager/osxcross.git && \
    cd /opt/osxcross && \
    wget -O tarballs/MacOSX12.3.sdk.tar.xz \
    "https://github.com/joseluisq/macosx-sdks/releases/download/12.3/MacOSX12.3.sdk.tar.xz" || \
    wget -O tarballs/MacOSX12.3.sdk.tar.xz \
    "https://github.com/phracker/MacOSX-SDKs/releases/download/12.3/MacOSX12.3.sdk.tar.xz" && \
    UNATTENDED=1 ./build.sh && \
    mkdir -p /opt/cmake && \
    CLANG_CC=$(ls /opt/osxcross/target/bin/*apple-darwin*-clang | grep -v clang++ | head -1) && \
    CLANG_CXX=$(ls /opt/osxcross/target/bin/*apple-darwin*-clang++ | head -1) && \
    CLANG_AR=$(ls /opt/osxcross/target/bin/*apple-darwin*-ar | head -1) && \
    CLANG_RANLIB=$(ls /opt/osxcross/target/bin/*apple-darwin*-ranlib | head -1) && \
    echo 'set(CMAKE_SYSTEM_NAME Darwin)' > /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_SYSTEM_PROCESSOR arm64)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_OSX_ARCHITECTURES arm64)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0")' >> /opt/cmake/osxcross-arm64.cmake && \
    echo "set(CMAKE_C_COMPILER $CLANG_CC)" >> /opt/cmake/osxcross-arm64.cmake && \
    echo "set(CMAKE_CXX_COMPILER $CLANG_CXX)" >> /opt/cmake/osxcross-arm64.cmake && \
    echo "set(CMAKE_AR $CLANG_AR)" >> /opt/cmake/osxcross-arm64.cmake && \
    echo "set(CMAKE_RANLIB $CLANG_RANLIB)" >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_C_COMPILER_WORKS 1)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_CXX_COMPILER_WORKS 1)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo "set(CMAKE_FIND_ROOT_PATH \${PREFIX})" >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_FIND_LIBRARY_SUFFIXES ".a" ".dylib")' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(BUILD_SHARED_LIBS OFF)' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(CMAKE_PROGRAM_PATH "/usr/bin:/usr/local/bin")' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'set(EXE_SQLITE3 "/usr/bin/sqlite3")' >> /opt/cmake/osxcross-arm64.cmake && \
    echo 'export OSXCROSS_TARGET_DIR="/opt/osxcross/target"' >> ~/.bashrc && \
    echo 'export PATH="/opt/osxcross/target/bin:$PATH"' >> ~/.bashrc ; \
    fi

WORKDIR /build

# Download sources
RUN curl -L https://www.sqlite.org/2024/sqlite-autoconf-${SQLITE_VERSION}.tar.gz | tar xz && \
    curl -L https://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz | tar xz && \
    curl -L https://download.osgeo.org/geos/geos-${GEOS_VERSION}.tar.bz2 | tar xj && \
    curl -L https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz | tar xz

# Build SQLite
RUN cd sqlite-autoconf-${SQLITE_VERSION} && \
    SQLITE_CFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1 -DSQLITE_ENABLE_RTREE=1 -DSQLITE_THREADSAFE=1 -DSQLITE_ENABLE_FTS3=1 -DSQLITE_ENABLE_FTS4=1 -DSQLITE_ENABLE_FTS5=1 -O2 -w" && \
    if [ "$TARGETOS" = "linux" ]; then \
    ./configure --prefix=$PREFIX_LINUX --enable-static --disable-shared CFLAGS="$SQLITE_CFLAGS" && \
    make -j$(nproc) && make install ; \
    elif [ "$TARGETOS" = "darwin" ]; then \
    export PATH=/opt/osxcross/target/bin:$PATH && \
    ./configure --prefix=$HOST_PREFIX --disable-shared --enable-static --disable-dynamic-extensions \
    CFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1 -DSQLITE_ENABLE_RTREE=1 -DSQLITE_THREADSAFE=1 -O2" && \
    make -j$(nproc) && make install && make clean && \
    OSXCROSS_CC=$(ls /opt/osxcross/target/bin/*apple-darwin*-clang | grep -v clang++ | head -1) && \
    OSXCROSS_AR=$(ls /opt/osxcross/target/bin/*apple-darwin*-ar | head -1) && \
    OSXCROSS_RANLIB=$(ls /opt/osxcross/target/bin/*apple-darwin*-ranlib | head -1) && \
    ./configure --host=aarch64-apple-darwin --prefix=$PREFIX_DARWIN --disable-shared --enable-static \
    --disable-dynamic-extensions CC="$OSXCROSS_CC" AR="$OSXCROSS_AR" RANLIB="$OSXCROSS_RANLIB" \
    CFLAGS="-DSQLITE_ENABLE_COLUMN_METADATA=1 -DSQLITE_ENABLE_RTREE=1 -DSQLITE_THREADSAFE=1 -O2" && \
    make -j$(nproc) && make install && \
    $OSXCROSS_RANLIB $PREFIX_DARWIN/lib/libsqlite3.a ; \
    elif [ "$TARGETOS" = "windows" ]; then \
    ./configure --host=x86_64-w64-mingw32 --prefix=$PREFIX_WINDOWS --disable-shared --enable-static \
    CC=x86_64-w64-mingw32-gcc-posix CFLAGS="$SQLITE_CFLAGS" && \
    make -j$(nproc) && make install ; \
    fi && \
    cd /build && rm -rf sqlite-autoconf-${SQLITE_VERSION}

# Build GEOS
RUN cd geos-${GEOS_VERSION} && mkdir build && cd build && \
    if [ "$TARGETOS" = "linux" ]; then \
    CFLAGS="-O2 -w" CXXFLAGS="-O2 -w" \
    cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_LINUX -DBUILD_TESTING=OFF -DBUILD_DOCUMENTATION=OFF ; \
    elif [ "$TARGETOS" = "darwin" ]; then \
    export PATH=/opt/osxcross/target/bin:$PATH && \
    cmake .. -DCMAKE_TOOLCHAIN_FILE=/opt/cmake/osxcross-arm64.cmake -DCMAKE_INSTALL_PREFIX=$PREFIX_DARWIN \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_TESTING=OFF -DBUILD_DOCUMENTATION=OFF -DCMAKE_CXX_FLAGS="-O2 -w" -DCMAKE_C_FLAGS="-O2 -w" ; \
    elif [ "$TARGETOS" = "windows" ]; then \
    cmake .. -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix \
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix -DCMAKE_INSTALL_PREFIX=$PREFIX_WINDOWS \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_TESTING=OFF -DBUILD_DOCUMENTATION=OFF -DCMAKE_CXX_FLAGS="-O2 -w" -DCMAKE_C_FLAGS="-O2 -w" ; \
    fi && \
    make -j$(nproc) && make install && \
    cd /build && rm -rf geos-${GEOS_VERSION}

# Build PROJ
RUN cd proj-${PROJ_VERSION} && mkdir build && cd build && \
    CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_TESTING=OFF \
    -DENABLE_TIFF=OFF \
    -DENABLE_CURL=OFF \
    -DBUILD_PROJSYNC=OFF \
    -DBUILD_PROJINFO=ON \
    -DBUILD_PROJ=ON \
    -DBUILD_GEOD=ON \
    -DBUILD_CS2CS=ON \
    -DBUILD_CCT=ON \
    -DBUILD_GIE=OFF \
    -DBUILD_APPS=ON \
    -DPROJ_DB_EXTRA_VALIDATION=OFF" && \
    if [ "$TARGETOS" = "linux" ]; then \
    CFLAGS="-O2 -w" CXXFLAGS="-O2 -w" \
    cmake .. $CMAKE_ARGS \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_LINUX ; \
    elif [ "$TARGETOS" = "darwin" ]; then \
    export PATH=/opt/osxcross/target/bin:$PATH && \
    cmake .. $CMAKE_ARGS \
    -DCMAKE_TOOLCHAIN_FILE=/opt/cmake/osxcross-arm64.cmake \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_DARWIN \
    -DSQLITE3_INCLUDE_DIR=$PREFIX_DARWIN/include \
    -DSQLITE3_LIBRARY=$PREFIX_DARWIN/lib/libsqlite3.a \
    -DEXE_SQLITE3=/usr/bin/sqlite3 \
    -DUSE_EXTERNAL_GTEST=OFF ; \
    elif [ "$TARGETOS" = "windows" ]; then \
    cmake .. $CMAKE_ARGS \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix \
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_WINDOWS \
    -DSQLITE3_INCLUDE_DIR=$PREFIX_WINDOWS/include \
    -DSQLITE3_LIBRARY=$PREFIX_WINDOWS/lib/libsqlite3.a \
    -DCMAKE_CXX_FLAGS="-O2 -w" \
    -DCMAKE_C_FLAGS="-O2 -w" ; \
    fi && \
    make -j$(nproc) && make install && cd /build && rm -rf proj-${PROJ_VERSION}

# Build GDAL
RUN cd gdal-${GDAL_VERSION} && \
    if [ "$TARGETOS" != "darwin" ]; then \
    sed -i 's/&pszSrcBuf/(char**)\&pszSrcBuf/g' port/cpl_recode_iconv.cpp || true ; \
    fi && \
    mkdir build && cd build && \
    GDAL_CMAKE_ARGS=" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    # Internal/External dependencies
    -DGDAL_USE_INTERNAL_LIBS=ON \
    -DGDAL_USE_SQLITE3=ON \
    -DGDAL_USE_PROJ=ON \
    -DGDAL_USE_GEOS=ON \
    # Compression and image libraries
    -DGDAL_USE_ZSTD=OFF \
    -DGDAL_USE_LZMA=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_LibLZMA=ON \
    -DGDAL_USE_DEFLATE=OFF \
    -DGDAL_USE_ZLIB_INTERNAL=ON \
    -DGDAL_USE_LIBPNG_INTERNAL=ON \
    -DGDAL_USE_JPEG_INTERNAL=ON \
    -DGDAL_USE_GEOTIFF_INTERNAL=ON \
    -DGDAL_USE_TIFF_INTERNAL=ON \
    -DGDAL_USE_WEBP=OFF \
    -DGDAL_USE_GIF=OFF \
    # Optional system libraries
    -DGDAL_USE_ICONV=OFF \
    -DGDAL_USE_CURL=OFF \
    -DGDAL_USE_LIBXML2=OFF \
    -DGDAL_USE_EXPAT=OFF \
    -DGDAL_USE_OPENSSL=OFF \
    -DGDAL_USE_CRYPTO=OFF \
    # Build options
    -DBUILD_APPS=ON \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_JAVA_BINDINGS=OFF \
    -DBUILD_CSHARP_BINDINGS=OFF \
    -DBUILD_TESTING=OFF \
    # GDAL drivers
    -DGDAL_BUILD_OPTIONAL_DRIVERS=ON \
    -DGDAL_ENABLE_DRIVER_GTIFF=ON \
    -DGDAL_ENABLE_DRIVER_VRT=ON \
    -DGDAL_ENABLE_DRIVER_GPKG=ON \
    -DGDAL_ENABLE_DRIVER_SHAPEFILE=ON \
    -DGDAL_ENABLE_DRIVER_GEOJSON=ON \
    -DGDAL_ENABLE_DRIVER_MEM=ON \
    -DGDAL_ENABLE_DRIVER_EHDR=ON \
    -DGDAL_ENABLE_DRIVER_ENVI=ON \
    # SQLite3 options
    -DACCEPT_MISSING_SQLITE3_MUTEX_ALLOC=ON \
    -DACCEPT_MISSING_SQLITE3_RTREE=ON \
    " && \
    if [ "$TARGETOS" = "linux" ]; then \
    PKG_CONFIG_PATH=$PREFIX_LINUX/lib/pkgconfig \
    CFLAGS="-O2 -w" CXXFLAGS="-O2 -w -Wno-old-style-cast -Wno-error" \
    cmake .. $GDAL_CMAKE_ARGS \
    -DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++" \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_LINUX \
    -DSQLite3_ROOT=$PREFIX_LINUX \
    -DPROJ_ROOT=$PREFIX_LINUX \
    -DGEOS_ROOT=$PREFIX_LINUX ;\
    elif [ "$TARGETOS" = "darwin" ]; then \
    export PATH=/opt/osxcross/target/bin:$PATH && \
    cmake .. $GDAL_CMAKE_ARGS \
    -DCMAKE_TOOLCHAIN_FILE=/opt/cmake/osxcross-arm64.cmake \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_DARWIN \
    -DSQLite3_ROOT=$PREFIX_DARWIN \
    -DPROJ_ROOT=$PREFIX_DARWIN \
    -DGEOS_ROOT=$PREFIX_DARWIN ;\
    elif [ "$TARGETOS" = "windows" ]; then \
    PKG_CONFIG_PATH=$PREFIX_WINDOWS/lib/pkgconfig \
    cmake .. $GDAL_CMAKE_ARGS \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc-posix \
    -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++-posix \
    -DCMAKE_INSTALL_PREFIX=$PREFIX_WINDOWS \
    -DSQLite3_ROOT=$PREFIX_WINDOWS \
    -DPROJ_ROOT=$PREFIX_WINDOWS \
    -DGEOS_ROOT=$PREFIX_WINDOWS \
    -DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++" \
    -DCMAKE_SHARED_LINKER_FLAGS="-static -static-libgcc -static-libstdc++" \
    -DCMAKE_CXX_FLAGS="-O2 -w -Wno-old-style-cast -Wno-error" \
    -DCMAKE_C_FLAGS="-O2 -w" ;\
    fi && \
    make -j$(nproc) && make install && cd /build && rm -rf gdal-${GDAL_VERSION}

# Stage 2: Extract GDAL/OGR binaries and data files only
FROM ubuntu:22.04 AS extractor

ARG TARGETOS
ARG TARGETARCH

RUN mkdir -p /output/binaries /output/data-gdal /output/data-proj

COPY --from=builder / /tmp/build/

RUN set -e && \
    case "$TARGETOS" in \
    "linux")   SRC="/tmp/build/usr/local" ;; \
    "darwin")  SRC="/tmp/build/opt/macos-build" ;; \
    "windows") SRC="/tmp/build/usr/x86_64-w64-mingw32" ;; \
    *) echo "ERROR: Unknown TARGETOS: $TARGETOS" && exit 1 ;; \
    esac && \
    echo "=== Extracting GDAL/OGR tools from $SRC ===" && \
    \
    # Extract shared data files (same for all platforms)
    if [ -d "$SRC/share/gdal" ] && [ "$(ls -A "$SRC/share/gdal" 2>/dev/null)" ]; then \
    cp -r "$SRC/share/gdal"/* /output/data-gdal/ && \
    echo "✓ GDAL data: $(find /output/data-gdal -type f | wc -l) files"; \
    else \
    echo "⚠️  No GDAL data found"; \
    fi && \
    \
    if [ -d "$SRC/share/proj" ] && [ "$(ls -A "$SRC/share/proj" 2>/dev/null)" ]; then \
    cp -r "$SRC/share/proj"/* /output/data-proj/ && \
    echo "✓ PROJ data: $(find /output/data-proj -type f | wc -l) files"; \
    else \
    echo "⚠️  No PROJ data found"; \
    fi && \
    \
    # Extract GDAL/OGR binaries only (no PROJ tools)
    if [ -d "$SRC/bin" ] && [ "$(ls -A "$SRC/bin" 2>/dev/null)" ]; then \
    echo "📦 Extracting GDAL/OGR binaries for $TARGETOS..." && \
    if [ "$TARGETOS" = "windows" ]; then \
    find "$SRC/bin" -name "gdal*.exe" -type f -exec cp {} /output/binaries/ \; 2>/dev/null || true && \
    find "$SRC/bin" -name "ogr*.exe" -type f -exec cp {} /output/binaries/ \; 2>/dev/null || true && \
    BIN_COUNT=$(find /output/binaries -name "*.exe" | wc -l) && \
    echo "✓ Windows GDAL/OGR executables: $BIN_COUNT"; \
    else \
    find "$SRC/bin" -name "gdal*" -type f ! -name "*.exe" -exec cp {} /output/binaries/ \; 2>/dev/null || true && \
    find "$SRC/bin" -name "ogr*" -type f ! -name "*.exe" -exec cp {} /output/binaries/ \; 2>/dev/null || true && \
    BIN_COUNT=$(find /output/binaries -type f | wc -l) && \
    echo "✓ Unix GDAL/OGR binaries: $BIN_COUNT"; \
    fi && \
    chmod +x /output/binaries/* 2>/dev/null || true; \
    else \
    echo "❌ No binaries found at $SRC/bin"; \
    fi && \
    \
    rm -rf /tmp/build

CMD ["echo", "Extraction completed"]