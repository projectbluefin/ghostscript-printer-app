kind: manual
description: Build the pnm2ppa HP PPA raster converter.

sources:
  - kind: git_repo
    url: salsa:printing-team/pnm2ppa.git
    track: debian/*
    ref: debian/1.13-14-0-gca990cac53fb605d827f707e5f2d0c490639705c

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

config:
  build-commands:
    - sed -i 's/^version[[:space:]]\+0[[:space:]]\+/version 710 /' pnm2ppa.conf
    - autoreconf --force --install
    - ./configure --prefix=/usr --sysconfdir=/var/lib/ghostscript-printer-app/pnm2ppa
    - make -j2
  install-commands:
    - install -D -m 0755 pnm2ppa "%{install-root}/usr/bin/pnm2ppa"
    - install -D -m 0755 calibrate_ppa "%{install-root}/usr/bin/calibrate_ppa"
    - install -D -m 0644 pnm2ppa.conf "%{install-root}/usr/share/ghostscript-printer-app/pnm2ppa.conf"
