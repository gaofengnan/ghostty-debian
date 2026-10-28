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
    pandoc minisign \
    libonig-dev libbz2-dev libgtk4-layer-shell-dev \
    libgtk-4-dev libadwaita-1-dev libxml2-utils libfontconfig-dev \
    jq xz-utils

# Fetch the upstream release tarball and verify its minisign signature. The public key is
# published in ghostty's PACKAGING.md. The tarball ships pre-generated gresource files, so no
# blueprint-compiler is needed (trixie has 0.16, a git checkout of 1.4.0 needs >= 0.20).
WORKDIR /build
RUN wget -q "https://release.files.ghostty.org/${GHOSTTY_VERSION}/ghostty-${GHOSTTY_VERSION}.tar.gz" \
    && wget -q "https://release.files.ghostty.org/${GHOSTTY_VERSION}/ghostty-${GHOSTTY_VERSION}.tar.gz.minisig" \
    && minisign -Vm "ghostty-${GHOSTTY_VERSION}.tar.gz" \
        -P RWQlAjJC23149WL2sEpT/l0QKy7hMIFhYdQOFy0Z7z7PbneUgvlsnYcV \
    && tar -xzmf "ghostty-${GHOSTTY_VERSION}.tar.gz" \
    && rm "ghostty-${GHOSTTY_VERSION}.tar.gz" "ghostty-${GHOSTTY_VERSION}.tar.gz.minisig"
WORKDIR /build/ghostty-$GHOSTTY_VERSION

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

