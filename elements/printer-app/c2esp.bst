kind: manual
description: Build the c2esp Kodak raster filters and driver descriptions.

sources:
  - kind: git_repo
    url: salsa:printing-team/c2esp.git
    track: debian/*
    ref: debian/27-11-0-g90a09ca4927fca5e1ae08307cd3ca9c0f0ca5b5b
  - kind: local
    path: patches/c2esp-libcupsfilters2-api.patch
    directory: patches

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/patch.bst

depends:
  - printer-app/jbigkit.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/libcupsfilters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/libppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/zlib.bst

config:
  build-commands:
    - patch -p1 < patches/c2esp-libcupsfilters2-api.patch
    - autoreconf --install
    - ./configure --prefix=/usr
    - make -j2
  install-commands:
    - install -D -m 0755 src/c2esp "%{install-root}/usr/lib/cups/filter/c2esp"
    - install -D -m 0755 src/c2espC "%{install-root}/usr/lib/cups/filter/c2espC"
    - install -D -m 0755 src/command2esp "%{install-root}/usr/lib/cups/filter/command2esp"
    - install -d "%{install-root}/usr/share/ppd"
    - install -m 0644 src/*.drv "%{install-root}/usr/share/ppd/"
    - sed -i 's:/usr/lib/cups/filter/::g' "%{install-root}"/usr/share/ppd/*.drv
