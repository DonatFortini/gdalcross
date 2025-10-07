#!/bin/bash
set -euo pipefail

export GDAL_VERSION="3.11.3"
export PROJ_VERSION="9.6.2"
export GEOS_VERSION="3.13.0"
export SQLITE_VERSION="3460100"

AVAILABLE_PLATFORMS=("linux/amd64" "linux/arm64" "darwin/arm64" "windows/amd64")
WANTED_EXECUTABLES=(
	"gdalinfo"
	"gdal_translate"
	"gdalwarp"
	"gdal_create"
	"gdal_rasterize"
	"ogr2ogr"
	"ogrinfo"
	"gdalbuildvrt"
	"gdaldem"
)

log() { echo "ℹ️  $1"; }
success() { echo "✅ $1"; }
error() {
	echo "❌ ERROR: $1" >&2
	exit 1
}
warn() { echo "⚠️  WARNING: $1" >&2; }

get_rust_toolchain() {
	local platform="$1"
	case "$platform" in
	"linux/amd64") echo "x86_64-unknown-linux-gnu" ;;
	"linux/arm64") echo "aarch64-unknown-linux-gnu" ;;
	"darwin/arm64") echo "aarch64-apple-darwin" ;;
	"windows/amd64") echo "x86_64-pc-msvc" ;;
	*) echo "unknown" ;;
	esac
}

get_expected_arch() {
	local platform="$1"
	case "$platform" in
	"linux/amd64" | "windows/amd64") echo "x86-64" ;;
	"linux/arm64") echo "aarch64" ;;
	"darwin/arm64") echo "arm64" ;;
	*) echo "unknown" ;;
	esac
}

parse_platform() {
	local platform="$1"
	case "$platform" in
	"linux/amd64") echo "linux amd64" ;;
	"linux/arm64") echo "linux arm64" ;;
	"darwin/arm64") echo "darwin arm64" ;;
	"windows/amd64") echo "windows amd64" ;;
	*) error "Unknown platform: $platform" ;;
	esac
}

validate_platform() {
	local platform="$1"
	for p in "${AVAILABLE_PLATFORMS[@]}"; do
		[ "$p" = "$platform" ] && return 0
	done
	error "Unknown platform: $platform. Use --help to see available platforms."
}

clean_dist() {
	[ -d "dist" ] && rm -rf dist/
	mkdir -p dist/data/{gdal,proj}
}

docker_clean_build_artifacts() {
	log "Cleaning up build containers and images..."
	for platform in "${platforms_built[@]}"; do
		docker ps -a --filter "ancestor=gdalcross" --format "{{.ID}}" | xargs -r docker rm -f
		docker images "gdalcross" --format "{{.ID}}" | xargs -r docker rmi -f
	done
	log "Docker build artifacts cleaned."
}

docker_full_clean() {
	log "Performing full Docker system prune..."
	docker container prune -f
	docker image prune -f
	docker builder prune -f
	log "Docker system clean completed."
}

verify_binary_architecture() {
	local binary="$1"
	local expected_platform="$2"

	[ ! -f "$binary" ] && return 1

	local file_output
	file_output=$(file "$binary" 2>/dev/null || echo "")

	local ok=1
	case "$expected_platform" in
	linux/amd64 | windows/amd64)
		echo "$file_output" | grep -Eq "x86-64|x86_64|AMD64" && ok=0
		;;
	linux/arm64)
		echo "$file_output" | grep -Eq "aarch64|ARM aarch64|arm64" && ok=0
		;;
	darwin/arm64)
		echo "$file_output" | grep -Eq "Mach-O 64-bit executable arm64|aarch64|arm64" && ok=0
		;;
	*)
		ok=1
		;;
	esac

	if [ $ok -eq 0 ]; then
		return 0
	else
		echo "❌ ARCH MISMATCH: Expected $expected_platform, got:"
		echo "   File output: $file_output"
		return 1
	fi
}

verify_platform_binaries() {
	local platform="$1"
	local target="${platform//\//-}"
	local bin_dir="dist/$target/binaries"

	[ ! -d "$bin_dir" ] && return 1

	local binaries
	binaries=$(find "$bin_dir" -type f 2>/dev/null)
	[ -z "$binaries" ] && return 1

	echo "Checking binaries integrity for $platform..."

	local all_correct=true
	local verified_count=0
	local failed_count=0

	for binary in $binaries; do
		local filename
		filename=$(basename "$binary")
		if verify_binary_architecture "$binary" "$platform"; then
			verified_count=$((verified_count + 1))
			echo "   ✓ $filename → $(get_expected_arch "$platform")"
		else
			all_correct=false
			failed_count=$((failed_count + 1))
			echo "   ✗ $filename → WRONG ARCHITECTURE!"
		fi
		if [ $verified_count -ge 3 ] && [ $failed_count -eq 0 ]; then
			local remaining=$(($(echo "$binaries" | wc -l) - 3))
			[ $remaining -gt 0 ] && echo "   ... and $remaining more (all verified ✓)"
			break
		fi
	done

	if [ "$all_correct" = true ]; then
		echo "✅ $platform: All binaries have correct architecture ($(get_expected_arch "$platform"))"
		return 0
	else
		echo "❌ $platform: Some binaries have INCORRECT architecture!"
		return 1
	fi
}

build_platform() {
	local platform="$1"
	local os arch
	read os arch <<<"$(parse_platform "$platform")"
	local target="${platform//\//-}"

	echo "Starting build for $platform..."
	echo "   Expected architecture: $(get_expected_arch "$platform")"

	mkdir -p "dist/$target/binaries"

	local platform_flag=""
	[ "$os" = "linux" ] && platform_flag="--platform $platform"

	if ! docker build \
		$platform_flag \
		--build-arg GDAL_VERSION="$GDAL_VERSION" \
		--build-arg PROJ_VERSION="$PROJ_VERSION" \
		--build-arg GEOS_VERSION="$GEOS_VERSION" \
		--build-arg SQLITE_VERSION="$SQLITE_VERSION" \
		--build-arg TARGETOS="$os" \
		--build-arg TARGETARCH="$arch" \
		--target extractor \
		-t "gdalcross" \
		.; then
		echo "❌ $platform: Docker build failed"
		return 1
	fi

	echo "📦 Extracting binaries for $platform..."
	local temp_container
	temp_container=$(docker create "gdalcross")
	local temp_bin_dir="dist/$target/.temp-binaries"
	mkdir -p "$temp_bin_dir"

	if docker cp "$temp_container:/output/binaries/." "$temp_bin_dir/" 2>/dev/null; then
		local rust_toolchain
		rust_toolchain=$(get_rust_toolchain "$platform")
		local kept_count=0
		for exe_name in "${WANTED_EXECUTABLES[@]}"; do
			local exe_pattern="$exe_name"
			[ "$os" = "windows" ] && exe_pattern="${exe_name}.exe"
			for exe_file in "$temp_bin_dir"/$exe_pattern*; do
				[ -f "$exe_file" ] || continue
				local original_name
				original_name=$(basename "$exe_file")
				local base_name="${original_name%.*}"
				local extension="${original_name##*.}"
				local new_name
				[ "$extension" = "exe" ] && new_name="${base_name}-${rust_toolchain}.exe" || new_name="${base_name}-${rust_toolchain}"
				cp "$exe_file" "dist/$target/binaries/$new_name"
				kept_count=$((kept_count + 1))
			done
		done
	fi

	rm -rf "$temp_bin_dir"

	if [ ! -f "dist/data/.extracted" ]; then
		docker cp "$temp_container:/output/data-gdal/." "dist/data/gdal/" 2>/dev/null || true
		docker cp "$temp_container:/output/data-proj/." "dist/data/proj/" 2>/dev/null || true
		touch "dist/data/.extracted"
	fi

	docker rm "$temp_container" >/dev/null 2>&1

	local bin_count
	bin_count=$(find "dist/$target/binaries" -type f 2>/dev/null | wc -l)
	if [ "$bin_count" -gt 0 ]; then
		echo ""
		if verify_platform_binaries "$platform"; then
			echo "✅ $platform: SUCCESS ($bin_count binaries, architecture verified)"
			return 0
		else
			echo "❌ $platform: ARCHITECTURE VERIFICATION FAILED!"
			return 1
		fi
	else
		echo "❌ $platform: FAILED (no binaries produced)"
		return 1
	fi
}

show_help() {
	cat <<EOF
GDAL Cross-Platform Build Script

USAGE:
	$0 [OPTIONS] [PLATFORM/ARCH...]

OPTIONS:
	-h, --help          Show this help message
	-c, --clean         Clean dist directory and docker before building

PLATFORMS:
	linux/amd64        Linux x86_64 (Intel/AMD 64-bit)
	linux/arm64        Linux ARM64 (Apple Silicon, ARM servers)
	darwin/arm64       macOS Apple Silicon (M1/M2/M3)
	windows/amd64      Windows x86_64 (Intel/AMD 64-bit)

EXAMPLES:
	$0                          # Build all platforms in parallel
	$0 linux/amd64             # Build only Linux x86_64
	$0 linux/amd64 darwin/arm64 # Build Linux x86_64 and macOS ARM64
	$0 --clean darwin/arm64     # Clean and build macOS ARM64
	$0 --help                   # Show this help

OUTPUT:
	dist/PLATFORM-ARCH/binaries/    Platform-specific executables
	dist/data/gdal/                 Shared GDAL format data
	dist/data/proj/                 Shared PROJ coordinate data

VERSIONS:
	GDAL: $GDAL_VERSION
	PROJ: $PROJ_VERSION
	GEOS: $GEOS_VERSION
	SQLite: $SQLITE_VERSION
EOF
}

show_build_summary() {
	echo ""
	log "📊 Build Summary"
	log "=================================="

	local successful_platforms=0
	local total_platforms=0

	for platform in "${platforms_built[@]}"; do
		total_platforms=$((total_platforms + 1))
		local target="${platform//\//-}"
		local bin_dir="dist/$target/binaries"

		if [ -d "$bin_dir" ]; then
			local bin_count
			bin_count=$(find "$bin_dir" -type f 2>/dev/null | wc -l)
			if [ "$bin_count" -gt 0 ]; then
				local sample_binary
				sample_binary=$(find "$bin_dir" -type f | head -1)
				if verify_binary_architecture "$sample_binary" "$platform" >/dev/null 2>&1; then
					echo "✅ $platform: binaries OK, architecture $(get_expected_arch "$platform")"
					successful_platforms=$((successful_platforms + 1))
				else
					echo "❌ $platform: binaries WRONG ARCH"
				fi
			else
				echo "❌ $platform: No binaries"
			fi
		else
			echo "❌ $platform: Build failed"
		fi
	done

	echo ""
	echo "🎯 Results: $successful_platforms/$total_platforms platforms succeeded"
}

main() {
	local platforms_to_build=()
	local clean_first=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			show_help
			exit 0
			;;
		-c | --clean)
			clean_first=true
			shift
			;;
		-*)
			error "Unknown option: $1. Use --help for usage."
			;;
		*/*)
			validate_platform "$1"
			platforms_to_build+=("$1")
			shift
			;;
		*)
			error "Invalid argument: $1. Platforms must be in format 'os/arch'. Use --help for usage."
			;;
		esac
	done

	[ ${#platforms_to_build[@]} -eq 0 ] && platforms_to_build=("${AVAILABLE_PLATFORMS[@]}")
	platforms_built=("${platforms_to_build[@]}")

	! command -v docker >/dev/null 2>&1 && error "Docker is required but not installed"
	! docker info >/dev/null 2>&1 && error "Docker daemon is not running"
	! command -v file >/dev/null 2>&1 && warn "'file' command not found - architecture verification will be limited"

	if [ "$clean_first" = true ]; then
		clean_dist
		docker_clean_build_artifacts
		success "Cleaned dist directory and Docker build artifacts"
	else
		mkdir -p dist/data/{gdal,proj}
	fi

	log "Starting GDAL cross-platform build..."
	log "Versions: GDAL=$GDAL_VERSION PROJ=$PROJ_VERSION GEOS=$GEOS_VERSION"
	log "Building platforms: ${platforms_to_build[*]}"
	log "Target executables: ${WANTED_EXECUTABLES[*]}"
	echo ""

	local build_pids=()
	for platform in "${platforms_to_build[@]}"; do
		build_platform "$platform" &
		build_pids+=($!)
	done

	log "Waiting for builds to complete..."
	local completed=0
	for i in "${!build_pids[@]}"; do
		local pid="${build_pids[i]}"
		local platform="${platforms_to_build[i]}"
		if wait "$pid"; then
			echo "✅ $platform build completed successfully"
			completed=$((completed + 1))
		else
			echo "❌ $platform build failed"
		fi
	done

	echo ""
	log "All builds finished. Completed: $completed/${#platforms_to_build[@]}"

	show_build_summary
	docker_clean_build_artifacts
}

trap 'echo ""; error "Build interrupted by user"' INT TERM

cd "$(dirname "$0")"
platforms_built=()
main "$@"
