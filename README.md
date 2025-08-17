# GDAL Cross-Platform Static Build Project

Don't know if it was done before, I searched for it but didn't find anything, so I made this.

## Project Purpose
This project's purpose is the creation of **completely static and standalone** GDAL executables for all platforms (Linux, Windows, macOS). These executables are fully autonomous and require no external dependencies (verifiable with `ldd`).

## License
This project is released under the **GNU General Public License v3.0 (GPL-3.0)**. This ensures that the software remains free and open source, and any derivative works must also be distributed under the same license terms.

- You are free to use, modify, and distribute this software
- Any modifications or derivative works must be released under GPL-3.0
- Source code must be made available when distributing binaries
- No warranty is provided

See the `LICENSE` file for full license text.

## Contributing
We welcome contributions from the community! Here's how you can help:

### How to Contribute
- **Bug Reports**: Open an issue describing the problem
- **Feature Requests**: Suggest new features or improvements
- **Code Contributions**: Submit pull requests with bug fixes or enhancements
- **Documentation**: Help improve documentation and examples
- **Testing**: Test builds on different platforms and report issues

### Contribution Guidelines
- Fork the repository and create a feature branch
- Update documentation if needed
- Submit a pull request with a clear description of changes

All contributors agree that their contributions will be licensed under the same GPL-3.0 license as the project.

## Build Methods

From a Linux machine (or using linux containers engine), you can generate executables for all platforms using cross-compilation.
this method produce :
- Linux x86_64_GNU executables
- Windows x86_64_MINGW_GNU executables
- macOS ARM64 executables
#### Prerequisites
- Linux machine or WSL2
- Docker installed
- Git

#### Steps
```bash
git clone <https://github.com/DonatFortini/gdalcross>
cd gdalcross
./build.sh
```

The `build.sh` script automatically generates static executables for:
- Linux
- Windows
- macOS


## Output
The output of the build will be 3 folders containing the static executables for each platform and their associated data files :

```
dist
├── linux
│   ├── amd64
│   └── arm64
├── macos
│   └── arm64
└── windows
    └── amd64
```

## Usage Examples with Tauri Sidecar

⚠️ **Important**: While the executables are static, they still require access to GDAL and PROJ data files that are created during compilation. For Tauri applications, it's recommended to include these in a `resources` folder and load them with the sidecar.

```rust
AppHandle.shell().sidecar("gdal_translate")
    .env("GDAL_DATA", "/path/to/gdal/data")
    .env("PROJ_LIB", "/path/to/proj/data")
    .args(["-of", "GTiff", "-co", "COMPRESS=LZW", "input.tif", "output.tif"])
    .output()
    .await?;
```

