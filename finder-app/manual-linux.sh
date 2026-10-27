#!/bin/bash

# Build the Linux kernel, BusyBox, and root filesystem for Assignment 3.
# Target architecture: ARM64.

set -Eeuo pipefail

OUTDIR="${1:-/tmp/aeld}"

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [output_directory]" >&2
    exit 1
fi

if ! mkdir -p "$OUTDIR"; then
    echo "Error: cannot create output directory: $OUTDIR" >&2
    exit 1
fi

OUTDIR="$(realpath "$OUTDIR")"

FINDER_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$FINDER_APP_DIR")"

KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_VERSION="v5.15.163"
KERNEL_DIR="$OUTDIR/linux-stable"

BUSYBOX_REPO="https://git.busybox.net/busybox"
BUSYBOX_VERSION="1_33_1"
BUSYBOX_DIR="$OUTDIR/busybox"

ROOTFS="$OUTDIR/rootfs"

ARCH="arm64"
CROSS_COMPILE="aarch64-none-linux-gnu-"
JOBS="${JOBS:-2}"

SYSROOT="$("${CROSS_COMPILE}gcc" -print-sysroot)"

echo "============================================"
echo "Assignment 3 Part 2: Linux system builder"
echo "Output directory: $OUTDIR"
echo "Architecture: $ARCH"
echo "Kernel version: $KERNEL_VERSION"
echo "BusyBox version: $BUSYBOX_VERSION"
echo "============================================"

# --------------------------------------------------
# 1. Download the Linux kernel
# --------------------------------------------------

if [ ! -d "$KERNEL_DIR/.git" ]; then
    echo "Downloading Linux kernel $KERNEL_VERSION..."
    rm -rf "$KERNEL_DIR"

    git clone \
        --depth 1 \
        --branch "$KERNEL_VERSION" \
        "$KERNEL_REPO" \
        "$KERNEL_DIR"
else
    echo "Linux kernel repository already exists."
    git -C "$KERNEL_DIR" fetch --depth 1 origin \
        "refs/tags/$KERNEL_VERSION:refs/tags/$KERNEL_VERSION"
    git -C "$KERNEL_DIR" checkout "$KERNEL_VERSION"
fi

# --------------------------------------------------
# 2. Build the ARM64 kernel
# --------------------------------------------------

if [ ! -f "$OUTDIR/Image" ]; then
    echo "Configuring Linux kernel..."

    make -C "$KERNEL_DIR" \
        ARCH="$ARCH" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        defconfig

    echo "Building Linux kernel..."

    make -C "$KERNEL_DIR" \
        -j"$JOBS" \
        ARCH="$ARCH" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        Image

    if [ ! -f "$KERNEL_DIR/arch/arm64/boot/Image" ]; then
        echo "Error: kernel Image was not generated." >&2
        exit 1
    fi

    cp "$KERNEL_DIR/arch/arm64/boot/Image" "$OUTDIR/Image"
else
    echo "Kernel Image already exists; skipping kernel build."
fi

# --------------------------------------------------
# 3. Download BusyBox
# --------------------------------------------------

if [ ! -d "$BUSYBOX_DIR/.git" ]; then
    echo "Downloading BusyBox $BUSYBOX_VERSION..."
    rm -rf "$BUSYBOX_DIR"

    git clone \
        --depth 1 \
        --branch "$BUSYBOX_VERSION" \
        "$BUSYBOX_REPO" \
        "$BUSYBOX_DIR"
else
    echo "BusyBox repository already exists."
    git -C "$BUSYBOX_DIR" fetch --depth 1 origin \
        "refs/tags/$BUSYBOX_VERSION:refs/tags/$BUSYBOX_VERSION"
    git -C "$BUSYBOX_DIR" checkout "$BUSYBOX_VERSION"
fi

# --------------------------------------------------
# 4. Configure and build BusyBox for ARM64
# --------------------------------------------------

echo "Configuring BusyBox..."

make -C "$BUSYBOX_DIR" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    defconfig

echo "Building BusyBox..."

make -C "$BUSYBOX_DIR" \
    -j"$JOBS" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE"

# --------------------------------------------------
# 5. Create the root filesystem
# --------------------------------------------------

echo "Creating root filesystem..."

if [ -d "$ROOTFS" ]; then
    sudo rm -rf -- "$ROOTFS"
fi

mkdir -p "$ROOTFS"

mkdir -p \
    "$ROOTFS/bin" \
    "$ROOTFS/sbin" \
    "$ROOTFS/etc" \
    "$ROOTFS/dev" \
    "$ROOTFS/proc" \
    "$ROOTFS/sys" \
    "$ROOTFS/tmp" \
    "$ROOTFS/usr/bin" \
    "$ROOTFS/usr/sbin" \
    "$ROOTFS/home/conf" \
    "$ROOTFS/lib" \
    "$ROOTFS/lib64"

sudo chmod 1777 "$ROOTFS/tmp"

# Install BusyBox and its applet links.
make -C "$BUSYBOX_DIR" \
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CONFIG_PREFIX="$ROOTFS" \
    install

# --------------------------------------------------
# 6. Copy runtime libraries for ARM64 executables
# --------------------------------------------------

copy_runtime_dependencies()
{
    local binary="$1"
    local interpreter
    local library
    local library_path
    local destination

    echo "Checking runtime dependencies: $binary"

    interpreter=$(
        "${CROSS_COMPILE}readelf" -l "$binary" |
        sed -n 's/.*interpreter: \(.*\)]/\1/p' |
        head -n 1
    )

    if [ -n "$interpreter" ]; then
        destination="$ROOTFS$interpreter"

        sudo mkdir -p "$(dirname "$destination")"

        if [ -f "$SYSROOT$interpreter" ]; then
            sudo cp -L "$SYSROOT$interpreter" "$destination"
        else
            library_path=$(
                find "$SYSROOT" -name "$(basename "$interpreter")" \
                    -print -quit
            )

            if [ -z "$library_path" ]; then
                echo "Error: cannot find interpreter $interpreter" >&2
                return 1
            fi

            sudo cp -L "$library_path" "$destination"
        fi
    fi

    while IFS= read -r library; do
        [ -n "$library" ] || continue

        library_path=$(
            find "$SYSROOT" -name "$library" -print -quit
        )

        if [ -z "$library_path" ]; then
            echo "Error: cannot find ARM64 library $library" >&2
            return 1
        fi

        #destination="$ROOTFS/lib64/$library"
        destination="$ROOTFS/lib/$library"
        
        sudo mkdir -p "$(dirname "$destination")"
        sudo cp -L "$library_path" "$destination"

    done < <(
        "${CROSS_COMPILE}readelf" -d "$binary" |
        sed -n 's/.*Shared library: \[\(.*\)\].*/\1/p'
    )
}

copy_runtime_dependencies "$BUSYBOX_DIR/busybox"

# --------------------------------------------------
# 7. Cross-compile the writer application
# --------------------------------------------------

echo "Compiling writer.c for ARM64..."

"${CROSS_COMPILE}gcc" \
    -Wall \
    -Werror \
    -O2 \
    -o "$OUTDIR/writer" \
    "$FINDER_APP_DIR/writer.c"

copy_runtime_dependencies "$OUTDIR/writer"

sudo cp "$OUTDIR/writer" "$ROOTFS/home/writer"

# --------------------------------------------------
# 8. Copy finder application scripts and configuration
# --------------------------------------------------

echo "Copying finder application files..."

sudo cp "$FINDER_APP_DIR/finder.sh" "$ROOTFS/home/finder.sh"
sudo cp "$FINDER_APP_DIR/finder-test.sh" "$ROOTFS/home/finder-test.sh"
sudo cp "$FINDER_APP_DIR/autorun-qemu.sh" "$ROOTFS/home/autorun-qemu.sh"

sudo cp "$PROJECT_DIR/conf/username.txt" "$ROOTFS/home/conf/username.txt"
sudo cp "$PROJECT_DIR/conf/assignment.txt" "$ROOTFS/home/conf/assignment.txt"

sudo chmod +x \
    "$ROOTFS/home/finder.sh" \
    "$ROOTFS/home/finder-test.sh" \
    "$ROOTFS/home/autorun-qemu.sh"

# --------------------------------------------------
# 9. Create required device nodes
# --------------------------------------------------

echo "Creating device nodes..."

sudo rm -f "$ROOTFS/dev/console" "$ROOTFS/dev/null"

sudo mknod -m 600 "$ROOTFS/dev/console" c 5 1
sudo mknod -m 666 "$ROOTFS/dev/null" c 1 3

# --------------------------------------------------
# 10. Set root filesystem ownership
# --------------------------------------------------

echo "Setting root filesystem ownership..."

sudo chown -R root:root "$ROOTFS"

# --------------------------------------------------
# 10b. Compatibility symlinks for dynamic loader
# --------------------------------------------------
sudo rm -rf "$ROOTFS/lib64" "$ROOTFS/usr/lib64"
sudo ln -sfn lib "$ROOTFS/lib64"
sudo ln -sfn ../lib "$ROOTFS/usr/lib64"

# --------------------------------------------------
# 11. Create the compressed initramfs archive
# --------------------------------------------------

echo "Creating initramfs.cpio.gz..."

(
    cd "$ROOTFS"
    sudo find . -print0 |
        sudo cpio --null -ov --format=newc
) | gzip -9 > "$OUTDIR/initramfs.cpio.gz"

# --------------------------------------------------
# 12. Verify generated files
# --------------------------------------------------

echo
echo "============================================"
echo "Build completed."
echo "============================================"

for file in \
    "$OUTDIR/Image" \
    "$OUTDIR/initramfs.cpio.gz" \
    "$OUTDIR/writer"
do
    if [ ! -s "$file" ]; then
        echo "Error: missing or empty file: $file" >&2
        exit 1
    fi

    ls -lh "$file"
done

echo
echo "Root filesystem: $ROOTFS"
echo "Kernel image: $OUTDIR/Image"
echo "Initramfs: $OUTDIR/initramfs.cpio.gz"
echo
echo "Next step: boot the system using the QEMU scripts."
