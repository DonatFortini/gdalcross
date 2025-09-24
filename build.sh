#!/bin/bash
set -euo pipefail

export GDAL_VERSION="3.11.3"
export PROJ_VERSION="9.6.2"
export GEOS_VERSION="3.13.0"
export SQLITE_VERSION="3460100"

AVAILABLE_PLATFORMS="linux/amd64 linux/arm64 darwin/arm64 windows/amd64"

WANTED_EXECUTABLES=(
	"gdalinfo"
	"gdal_translate"
	"gdalwarp"
	"ogr2ogr"
	"ogrinfo"
)

get_rust_toolchain() {
	local platform="$1"
	case "$platform" in
	"linux/amd64") echo "x86_64-unknown-linux-gnu" ;;
	"linux/arm64") echo "aarch64-unknown-linux-gnu" ;;
	"darwin/arm64") echo "aarch64-apple-darwin" ;;
	"windows/amd64") echo "x86_64-pc-windows-gnu" ;;
	*) echo "unknown" ;;
	esac
}

get_container_name() {
	local platform="$1"
	local platform_parts
	platform_parts=$(parse_platform "$platform")
	local os="${platform_parts%% *}"
	local arch="${platform_parts##* }"
	echo "gdalcross-${os}-${arch}"
}

log() { echo "ℹ️  $1"; }
success() { echo "✅ $1"; }
error() {
	echo "❌ ERROR: $1" >&2
	exit 1
}
warn() { echo "⚠️  WARNING: $1" >&2; }

show_help() {
	cat <<EOF
GDAL Cross-Platform Build Script

USAGE:
	$0 [OPTIONS] [PLATFORM/ARCH...]

OPTIONS:
	-h, --help          Show this help message
	-c, --clean         Clean dist directory before building
	-v, --verbose       Enable verbose output with organized sections

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

CONTAINER NAMING:
	Each build creates a container with a specific name:
	• gdalcross-{os}-{arch}
	
	Examples:
	• linux/amd64  → gdalcross-linux-amd64
	• darwin/arm64 → gdalcross-darwin-arm64

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

validate_platform() {
	local platform="$1"
	local valid=false

	for p in $AVAILABLE_PLATFORMS; do
		if [ "$p" = "$platform" ]; then
			valid=true
			break
		fi
	done

	if [ "$valid" = false ]; then
		error "Unknown platform: $platform. Use --help to see available platforms."
	fi
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

clean_dist() {
	if [ -d "dist" ]; then
		log "Cleaning dist directory..."
		rm -rf dist/
	fi
	mkdir -p dist/data/{gdal,proj}
}

build_platform() {
	local platform="$1"
	local platform_parts
	platform_parts=$(parse_platform "$platform")
	local os="${platform_parts%% *}"
	local arch="${platform_parts##* }"
	local target="${platform//\//-}"

	local container_name
	container_name=$(get_container_name "$platform")

	echo "🚀 Starting build for $platform..."
	echo "   Container: $container_name"

	mkdir -p "dist/$target/binaries"

	echo "Building Docker image for $platform..."
	local build_result=0
	docker build \
		--build-arg GDAL_VERSION="$GDAL_VERSION" \
		--build-arg PROJ_VERSION="$PROJ_VERSION" \
		--build-arg GEOS_VERSION="$GEOS_VERSION" \
		--build-arg SQLITE_VERSION="$SQLITE_VERSION" \
		--build-arg TARGETOS="$os" \
		--build-arg TARGETARCH="$arch" \
		--target extractor \
		-t "$container_name" \
		. || build_result=1

	if [ $build_result -ne 0 ]; then
		echo "❌ $platform: Docker build failed"
		return 1
	fi

	echo "📦 Extracting binaries for $platform..."

	local temp_container
	temp_container=$(docker create "$container_name")

	local temp_bin_dir="dist/$target/.temp-binaries"
	mkdir -p "$temp_bin_dir"

	if ! docker cp "$temp_container:/output/binaries/." "$temp_bin_dir/" 2>/dev/null; then
		echo "⚠️  $platform: No binaries found"
	else
		local rust_toolchain
		rust_toolchain=$(get_rust_toolchain "$platform")

		local kept_count=0

		for exe_name in "${WANTED_EXECUTABLES[@]}"; do
			local exe_pattern="$exe_name"

			if [ "$os" = "windows" ]; then
				exe_pattern="${exe_name}.exe"
			fi

			for exe_file in "$temp_bin_dir"/$exe_pattern*; do
				if [ -f "$exe_file" ]; then
					local original_name
					original_name=$(basename "$exe_file")
					local base_name="${original_name%.*}"
					local extension="${original_name##*.}"

					local new_name
					if [ "$extension" = "exe" ]; then
						new_name="${base_name}-${rust_toolchain}.exe"
					else
						new_name="${base_name}-${rust_toolchain}"
					fi

					cp "$exe_file" "dist/$target/binaries/$new_name"
					kept_count=$((kept_count + 1))
				fi
			done
		done

		if [ "$VERBOSE" = "true" ]; then
			echo "📊 $platform: Kept $kept_count/${#WANTED_EXECUTABLES[@]} executables"
		fi
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
		echo "✅ $platform: SUCCESS ($bin_count binaries) → Container: $container_name"
		return 0
	else
		echo "❌ $platform: FAILED (no binaries produced)"
		return 1
	fi
}

show_build_summary() {
	echo ""
	log "📊 Build Summary"
	log "=================================="

	local total_binaries=0
	local successful_platforms=0
	local total_platforms=0

	echo "🏗️  Container Names Used:"
	for platform in "${platforms_built[@]}"; do
		local container_name
		container_name=$(get_container_name "$platform")
		echo "   $platform → $container_name"
	done
	echo ""

	for platform in "${platforms_built[@]}"; do
		total_platforms=$((total_platforms + 1))
		local target="${platform//\//-}"
		local bin_dir="dist/$target/binaries"

		if [ -d "$bin_dir" ]; then
			local bin_count
			bin_count=$(find "$bin_dir" -type f 2>/dev/null | wc -l)
			if [ "$bin_count" -gt 0 ]; then
				echo "📦 $platform: $bin_count binaries"
				total_binaries=$((total_binaries + bin_count))
				successful_platforms=$((successful_platforms + 1))

				find "$bin_dir" -type f | head -3 | while read -r binary; do
					local filename
					filename=$(basename "$binary")
					local size
					size=$(ls -lh "$binary" | awk '{print $5}')
					echo "   $filename ($size)"
				done
				local remaining
				remaining=$((bin_count - 3))
				[ "$remaining" -gt 0 ] && echo "   ... and $remaining more"
			else
				echo "❌ $platform: No binaries"
			fi
		else
			echo "❌ $platform: Build failed"
		fi
		echo ""
	done

	local gdal_count proj_count
	gdal_count=$(find "dist/data/gdal" -type f 2>/dev/null | wc -l)
	proj_count=$(find "dist/data/proj" -type f 2>/dev/null | wc -l)

	echo "📄 Shared Data:"
	echo "   GDAL formats: $gdal_count files"
	echo "   PROJ datums: $proj_count files"
	echo ""

	echo "🎯 Overall Results:"
	echo "   Successful platforms: $successful_platforms/$total_platforms"
	echo "   Total binaries: $total_binaries"
	echo "   Output directory: $(pwd)/dist/"

	if [ "$successful_platforms" -eq "$total_platforms" ]; then
		success "🎉 All builds completed successfully!"
	elif [ "$successful_platforms" -gt 0 ]; then
		warn "Some builds completed successfully"
	else
		error "All builds failed"
	fi
}

docker_full_clean() {
	log "Performing Docker full clean..."
	docker container prune -f
	docker image prune -f
	docker builder prune -f
	log "Docker clean completed."
}

main() {
	local platforms_to_build=()
	local clean_first=false
	VERBOSE=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			show_help
			exit 0
			;;
		--list-executables)
			echo "📋 GDAL/OGR Executables that will be built:"
			echo "============================================"
			for exe in "${WANTED_EXECUTABLES[@]}"; do
				echo "  • $exe"
			done
			echo ""
			echo "These will be renamed with Rust toolchain suffixes:"
			for platform in $AVAILABLE_PLATFORMS; do
				local rust_name
				rust_name=$(get_rust_toolchain "$platform")
				echo "  $platform → ${WANTED_EXECUTABLES[0]}-$rust_name"
			done
			echo ""
			echo "Container naming pattern:"
			for platform in $AVAILABLE_PLATFORMS; do
				local container_name
				container_name=$(get_container_name "$platform")
				echo "  $platform → $container_name"
			done
			echo ""
			echo "To modify this list, edit WANTED_EXECUTABLES array in $0"
			exit 0
			;;
		-c | --clean)
			clean_first=true
			shift
			;;
		-v | --verbose)
			VERBOSE=true
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

	if [ ${#platforms_to_build[@]} -eq 0 ]; then
		log "No platforms specified, building all platforms..."
		for platform in $AVAILABLE_PLATFORMS; do
			platforms_to_build+=("$platform")
		done
	fi

	platforms_built=("${platforms_to_build[@]}")

	if ! command -v docker >/dev/null 2>&1; then
		error "Docker is required but not installed"
	fi

	if ! docker info >/dev/null 2>&1; then
		error "Docker daemon is not running"
	fi

	if [ "$clean_first" = true ]; then
		clean_dist
	else
		mkdir -p dist/data/{gdal,proj}
	fi

	log "Starting GDAL cross-platform build..."
	log "Versions: GDAL=$GDAL_VERSION PROJ=$PROJ_VERSION GEOS=$GEOS_VERSION"
	log "Building platforms: ${platforms_to_build[*]}"
	log "Target executables: ${WANTED_EXECUTABLES[*]}"
	echo ""

	echo "🏷️  Container names for this build:"
	for platform in "${platforms_to_build[@]}"; do
		local container_name
		container_name=$(get_container_name "$platform")
		echo "   $platform → $container_name"
	done
	echo ""

	local build_pids=()
	local build_results=()

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
			build_results[i]="success"
			completed=$((completed + 1))
			echo "✅ $platform build completed successfully"
		else
			build_results[i]="failed"
			echo "❌ $platform build failed"
		fi
	done

	echo ""
	log "All builds finished. Completed: $completed/${#platforms_to_build[@]}"

	show_build_summary
	docker_full_clean
}

trap 'echo ""; error "Build interrupted by user"' INT TERM

cd "$(dirname "$0")"

platforms_built=()

main "$@"
