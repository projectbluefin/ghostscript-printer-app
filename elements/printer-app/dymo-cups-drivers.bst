kind: manual
description: Build the DYMO CUPS raster filters and PPD archive.

sources:
  - kind: git_repo
    url: salsa:printing-team/dymo-cups-drivers.git
    track: debian/*
    ref: debian/1.4.0-12-0-ge69dceba792dc23d2894d57b0468009e52109625

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst

config:
  build-commands:
    - autoreconf --install
    - ./configure --prefix=/usr
    - make -j2
    - pyppd -v -o dymo-ppds ppd
  install-commands:
    - install -D -m 0755 src/lw/raster2dymolw "%{install-root}/usr/lib/cups/filter/raster2dymolw"
    - install -D -m 0755 src/lm/raster2dymolm "%{install-root}/usr/lib/cups/filter/raster2dymolm"
    - install -D -m 0755 dymo-ppds "%{install-root}/usr/share/ppd/dymo-ppds"
