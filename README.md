# GDAL Cross-Platform Static Build Project

Don't know if it was done before, I searched for it but didn't find anything, so I made this.

## Project Purpose

This project creates **completely static and standalone** GDAL/OGR executables for multiple platforms using Docker cross-compilation. These executables are fully autonomous and require no external dependencies (verified with `ldd`, `otool`, etc.).

**Note**: to me "Standalone" means the binaries do not rely on any shared libraries or external dependencies at runtime and only depend on OS core libraries.

## Supported Platforms & Executables

### Platforms

- **Linux AMD64** (`linux/amd64`) - Intel/AMD 64-bit Linux
- **Linux ARM64** (`linux/arm64`) - ARM64 Linux (Apple Silicon, ARM servers)
- **macOS ARM64** (`darwin/arm64`) - Apple Silicon (M1/M2/M3/M4)
- **Windows AMD64** (`windows/amd64`) - Intel/AMD 64-bit Windows

### Built Executables

The following GDAL/OGR tools are built for each platform:

- `gdalinfo` - Display information about raster datasets
- `gdal_translate` - Convert raster data between formats  
- `gdalwarp` - Reproject and warp raster datasets
- `ogr2ogr` - Convert vector data between formats
- `ogrinfo` - Display information about vector datasets

### Software Versions

- **GDAL**: 3.11.3
- **PROJ**: 9.6.2  
- **GEOS**: 3.13.0
- **SQLite**: 3.46.1 (3460100)

## Prerequisites

- Linux machine or WSL2
- Docker installed and running
- Git

## Quick Start

```bash
git clone https://github.com/DonatFortini/gdalcross
cd gdalcross
./build.sh
```

## Build Options

### Build All Platforms (Default)

```bash
./build.sh
```

Builds all platforms in parallel using containers named `gdalcross-{os}-{arch}`.

### Build Specific Platforms

```bash
# Build only Linux AMD64
./build.sh linux/amd64

# Build multiple specific platforms  
./build.sh linux/amd64 darwin/arm64 windows/amd64
```

### Clean Build

```bash
# Clean dist directory and Docker cache before building
./build.sh --clean
```

### Get Help

```bash
./build.sh --help
./build.sh --list-executables
```

## Output Structure

The build creates the following directory structure:

```
dist/
├── linux-amd64/
│   └── binaries/
│       ├── gdalinfo-x86_64-unknown-linux-gnu
│       ├── gdal_translate-x86_64-unknown-linux-gnu  
│       ├── gdalwarp-x86_64-unknown-linux-gnu
│       ├── ogr2ogr-x86_64-unknown-linux-gnu
│       └── ogrinfo-x86_64-unknown-linux-gnu
├── linux-arm64/
│   └── binaries/
│       ├── gdalinfo-aarch64-unknown-linux-gnu
│       └── ... (similar pattern)
├── darwin-arm64/  
│   └── binaries/
│       ├── gdalinfo-aarch64-apple-darwin
│       └── ... (similar pattern)
├── windows-amd64/
│   └── binaries/
│       ├── gdalinfo-x86_64-pc-windows-gnu.exe
│       └── ... (similar pattern)  
└── data/
    ├── gdal/     # Shared GDAL format data files
    └── proj/     # Shared PROJ coordinate system data
```

### Binary Naming Convention

Executables are renamed with platform-specific toolchain suffixes:

- Linux AMD64: `-x86_64-unknown-linux-gnu`
- Linux ARM64: `-aarch64-unknown-linux-gnu`
- macOS ARM64: `-aarch64-apple-darwin`
- Windows AMD64: `-x86_64-pc-windows-gnu.exe`

## Usage Examples

### Standalone Usage

⚠️ **Important**: Before running any GDAL or OGR commands, set the environment variables so the tools can locate their required data files. Make sure `GDAL_DATA` and `PROJ_LIB` point to the `dist/data/` directory:

```bash
export GDAL_DATA="$(pwd)/dist/data/gdal"
export PROJ_LIB="$(pwd)/dist/data/proj"
```

This step is required for correct operation of all executables.

```bash
# Linux
./dist/linux-amd64/binaries/gdalinfo-x86_64-unknown-linux-gnu input.tif

# macOS  
./dist/darwin-arm64/binaries/gdal_translate-aarch64-apple-darwin input.tif output.tif

# Windows
./dist/windows-amd64/binaries/ogr2ogr-x86_64-pc-windows-gnu.exe output.shp input.geojson
```

### With Tauri Sidecar

⚠️ **Important**: While the executables are static, they still require access to GDAL and PROJ data files. For Tauri applications, include the `dist/data/` folder in your resources.

```rust
use tauri::Manager;

// Configure environment for GDAL data access
let gdal_data_path = app_handle.path_resolver()
    .resolve_resource("data/gdal")
    .expect("failed to resolve gdal data path");
    
let proj_data_path = app_handle.path_resolver()  
    .resolve_resource("data/proj")
    .expect("failed to resolve proj data path");

// Execute GDAL tool
app_handle.shell()
    .sidecar("gdal_translate-x86_64-unknown-linux-gnu")
    .env("GDAL_DATA", gdal_data_path)
    .env("PROJ_LIB", proj_data_path) 
    .args(["-of", "GTiff", "-co", "COMPRESS=LZW", "input.tif", "output.tif"])
    .output()
    .await?;
```

### Cross-Compilation Features

- **Linux**: Static linking with musl/glibc
- **macOS**: OSXCross toolchain for Apple Silicon  
- **Windows**: MinGW-w64 cross-compiler

## License

This project is released under the **GNU General Public License v3.0 (GPL-3.0)**. This ensures that the software remains free and open source, and any derivative works must also be distributed under the same license terms.

- You are free to use, modify, and distribute this software
- Any modifications or derivative works must be released under GPL-3.0
- Source code must be made available when distributing binaries
- No warranty is provided

See the `LICENSE` file for full license text.

## Contributing

Here's how you can help:

### How to Contribute

- **Bug Reports**: Open an issue describing the problem
- **Feature Requests**: Suggest new features or improvements
- **Code Contributions**: Submit pull requests with bug fixes or enhancements
- **Documentation**: Help improve documentation and examples
- **Testing**: Test builds on different platforms and report issues

### Contribution Guidelines

- Fork the repository and create a feature branch
- Update documentation if needed  
- Test changes across multiple platforms
- Submit a pull request with a clear description of changes

All contributors agree that their contributions will be licensed under the same GPL-3.0 license as the project.

### Development Notes

- Modify `WANTED_EXECUTABLES` array in `build.sh` to change which tools are built
- Update version variables at the top of `build.sh` to use different GDAL/PROJ/GEOS versions
- The Dockerfile supports additional GDAL drivers - modify `GDAL_CMAKE_ARGS` to enable more formats
