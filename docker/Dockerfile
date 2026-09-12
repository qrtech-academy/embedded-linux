# The machine this whole course builds inside.
#
# Everything here is a build dependency of one of four things: the arm64 kernel, QEMU, BusyBox,
# or the lint targets. Nothing in the course needs root on the host, nothing it builds is
# installed outside build/, and the image exists so that a reader on WSL, a reader on a Mac and
# a CI runner all get the same compiler.
#
# Build it with "make env". It is not published anywhere; it is built locally from this file.
FROM debian:bookworm-slim

# Kernel build. bc and the two parser generators are needed by kbuild itself; libssl and libelf
# are needed by the module signing and BTF steps that a defconfig turns on.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        build-essential \
        bc \
        bison \
        flex \
        libssl-dev \
        libelf-dev \
        cpio \
        kmod \
        rsync \
        file \
        wget \
        ca-certificates \
        xz-utils \
        bzip2 \
        git \
    && rm -rf /var/lib/apt/lists/*

# The cross toolchain. Everything the reader compiles for the target goes through this prefix.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        gcc-aarch64-linux-gnu \
        libc6-dev-arm64-cross \
    && rm -rf /var/lib/apt/lists/*

# QEMU's own build dependencies, plus the device tree compiler, which L09 uses to read back the
# DTB that QEMU generates.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        meson \
        ninja-build \
        pkg-config \
        python3 \
        python3-venv \
        libglib2.0-dev \
        libpixman-1-dev \
        zlib1g-dev \
        device-tree-compiler \
    && rm -rf /var/lib/apt/lists/*

# The lint targets. gawk rather than mawk is load-bearing: ci/markdown.sh counts characters, and
# mawk counts bytes, so the line-length and table rules are wrong without it.
#
# strace is here for L02, which uses it to show that reading /proc opens no file on any disk. It
# is a host-side tool on purpose: BusyBox has no strace applet, so the target does not have one,
# and that absence is itself part of what L02 teaches about a two-megabyte userland.
RUN apt-get update && apt-get install --yes --no-install-recommends \
        gawk \
        clang-format \
        black \
        strace \
    && rm -rf /var/lib/apt/lists/*

# The container runs as the invoking user, who has no entry in /etc/passwd and therefore no home
# directory. Anything that wants to write a dotfile gets /tmp instead.
ENV HOME=/tmp

# The marker ci/common.sh looks for to know it is already inside.
RUN echo "qacademy-linux" > /etc/qa-linux-env
