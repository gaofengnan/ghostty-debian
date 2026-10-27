# syntax=docker/dockerfile:1
ARG DEBIAN_DIST=trixie
FROM debian:$DEBIAN_DIST

ARG DEBIAN_DIST
ARG GHOSTTY_VERSION
ARG BUILD_VERSION

# Install build deps + packaging tools
# APT::Immediate-Configure=false works around a dependency-ordering bug in
# sid's tpm2-tss/systemd-tpm stack (libtss2-tcti-cmd0t64 fails to configure)
RUN apt-get update && apt-get install -y -o APT::Immediate-Configure=false \
    git curl wget gpg lsb-release \
    build-essential debhelper devscripts fakeroot \
    blueprint-compiler pandoc minisign \
    libonig-dev libbz2-dev libgtk4-layer-shell-dev \
    libgtk-4-dev libadwaita-1-dev libxml2-utils libfontconfig-dev \
    jq xz-utils

# Clone and checkout
WORKDIR /build
RUN git clone https://github.com/ghostty-org/ghostty
WORKDIR /build/ghostty
RUN git checkout v$GHOSTTY_VERSION

# Zig: install the version this ghostty release declares (minimum_zig_version), from ziglang.org.
# Verified two ways: the sha256 published in ziglang.org's index.json, and the minisign signature
# against Zig's official public key (https://ziglang.org/download/).
RUN set -eux; \
    arch=$(uname -m); \
    ver=$(sed -n 's/.*\.minimum_zig_version *= *"\([^"]*\)".*/\1/p' build.zig.zon); \
    test -n "$ver"; \
    curl -fsSL https://ziglang.org/download/index.json -o /tmp/zig-index.json; \
    url=$(jq -r --arg v "$ver" --arg a "${arch}-linux" '.[$v][$a].tarball' /tmp/zig-index.json); \
    sha=$(jq -r --arg v "$ver" --arg a "${arch}-linux" '.[$v][$a].shasum' /tmp/zig-index.json); \
    test "$url" != null; test "$sha" != null; \
    curl -fsSL -o /tmp/zig.tar.xz "$url"; \
    curl -fsSL -o /tmp/zig.tar.xz.minisig "$url.minisig"; \
    echo "$sha  /tmp/zig.tar.xz" | sha256sum -c -; \
    minisign -Vm /tmp/zig.tar.xz -P RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U; \
    mkdir -p /opt/zig; tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    ln -s /opt/zig/zig /usr/local/bin/zig; zig version; \
    rm -f /tmp/zig.tar.xz /tmp/zig.tar.xz.minisig /tmp/zig-index.json

# Copy debian packaging
COPY debian/ debian/
RUN chmod +x debian/rules

# Generate debian/changelog with proper version and timestamp
ENV DEBEMAIL="gao.fengnan@gmail.com"
ENV DEBFULLNAME="Fengnan Gao"
RUN rm -f debian/changelog && \
    dch --create --package ghostty \
    --newversion "${GHOSTTY_VERSION}-${BUILD_VERSION}~${DEBIAN_DIST}" \
    --distribution "${DEBIAN_DIST}" \
    "Unofficial Debian package." && \
    dch --append "https://ghostty.org/docs/install/release-notes/$(echo $GHOSTTY_VERSION | tr '.' '-')"

# Build
RUN dpkg-buildpackage --build=binary --no-sign --no-check-builddeps

