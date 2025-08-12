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
- Ensure your code follows existing style conventions
- Test your changes thoroughly
- Update documentation if needed
- Submit a pull request with a clear description of changes

All contributors agree that their contributions will be licensed under the same GPL-3.0 license as the project.

## Build Methods

### Method 1: Cross-compilation from Linux (Recommended)
From a Linux machine, you can generate executables for all platforms using cross-compilation.
this method produce :
- Linux x86_64_GNU executables
- Windows x86_64_MINGW_GNU executables
- macOS x86_64 (still in development)
#### Prerequisites
- Linux machine
- Docker installed
- Git

#### Steps
```bash
git clone <repository-url>
cd gdalcross
./build.sh
```

The `build.sh` script automatically generates static executables for:
- Linux
- Windows
- macOS

### Method 2: Windows Host (Special Case)

⚠️ **Only usable from a physical Windows machine**

This method is specifically designed for native Windows environments and requires particular configuration.
Produce MSVC static executables for Windows.

#### Windows Host Prerequisites
- **Windows 11 Pro** (required)
- **Hyper-V enabled**
- **WSL2 Engine disabled in Docker Desktop**

#### Required Configuration
1. Enable Hyper-V in Windows features
2. In Docker Desktop: Settings → General → Uncheck "Use the WSL 2 based engine"
3. Restart Docker Desktop

#### Build Process
```bash
docker build -f <dockerfile-windows> -t <tag-windows>
```

## Output
The generated executables are completely self-contained and can be deployed on any target platform machine without dependency installation.

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

