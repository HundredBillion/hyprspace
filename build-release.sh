#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="hyprspace-codesign-certificate"
archs=()
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        # Repeatable. Releases are universal (x86_64 and arm64). A single architecture is half the size,
        # e.g. '--arch arm64' for a build that only runs on the Mac that builds it
        --arch)
            case "$2" in
                arm64|x86_64) archs+=("$2"); shift 2;;
                *) echo "Unsupported --arch $2. Possible values: arm64, x86_64" > /dev/stderr; exit 1 ;;
            esac;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done
if test ${#archs[@]} -eq 0; then archs=(x86_64 arm64); fi
export HYPRSPACE_RELEASE_ARCHS="${archs[*]}" # validate-release-binaries.sh checks exactly these architectures

#############
### BUILD ###
#############

./build-docs.sh --release
./build-shell-completion.sh

./generate.sh
./script/check-uncommitted-files.sh

build_info_file="$PWD/.build-info.txt"
printf '%s\n%s\n%s\n' "$build_version" "$(git rev-parse HEAD)" "$(git rev-parse --short HEAD)" > "$build_info_file"

# -Osize: the window manager spends its time waiting for other apps, not computing. Smaller binaries are worth more
swift_build_cli=(build -c release --product hyprspace -Xswiftc -Osize)
for arch in "${archs[@]}"; do swift_build_cli+=(--arch "$arch"); done
swift "${swift_build_cli[@]}" -Xswiftc -warnings-as-errors \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __hypr_build \
    -Xlinker "$build_info_file"
cli_bin_path="$(swift "${swift_build_cli[@]}" --show-bin-path)"

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme HyprSpace \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build \
        ARCHS="${archs[*]}" \
        ONLY_ACTIVE_ARCH=NO \
        MARKETING_VERSION="$build_version" \
        HYPRSPACE_CODE_SIGN_IDENTITY="$codesign_identity" \
        SWIFT_OPTIMIZATION_LEVEL=-Osize \
        DEPLOYMENT_POSTPROCESSING=YES \
        STRIP_INSTALLED_PRODUCT=YES \
        STRIP_STYLE=non-global \
        STRIP_SWIFT_SYMBOLS=YES \
        HYPRSPACE_BUILD_INFO_LDFLAGS="-sectcreate __TEXT __hypr_build $build_info_file"
cd -

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/HyprSpace.app" .release
cp -r "$cli_bin_path/hyprspace" .release

# Binary reproducibility: strip non-portable rpaths
# https://github.com/swiftlang/swift-package-manager/issues/10760
xcrun objdump --macho --rpaths --no-leading-headers --arch all .release/hyprspace | grep -vE '^(@|/usr/lib/swift$)' | sort -u |
    while IFS= read -r rpath; do
        install_name_tool -delete_rpath "$rpath" .release/hyprspace
    done

# More than a half of the unstripped binary is symbols
strip -rSTx .release/hyprspace

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/hyprspace

################
### VALIDATE ###
################

./script/validate-release-binaries.sh

############
### PACK ###
############

mkdir -p ".release/HyprSpace-v$build_version/manpage" && cp .man/*.1 ".release/HyprSpace-v$build_version/manpage"
cp -r ./legal ".release/HyprSpace-v$build_version/legal"
cp -r .shell-completion ".release/HyprSpace-v$build_version/shell-completion"
cd .release
    mkdir -p "HyprSpace-v$build_version/bin" && cp -r hyprspace "HyprSpace-v$build_version/bin"
    cp -r HyprSpace.app "HyprSpace-v$build_version"
    zip -r "HyprSpace-v$build_version.zip" "HyprSpace-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in hyprspace hyprspace-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/HyprSpace-v$build_version.zip" \
        --build-version "$build_version"
done
