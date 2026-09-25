kind: manual
description: Build the min12xxw Minolta raster converter.

sources:
  - kind: git_repo
    url: salsa:printing-team/min12xxw.git
    track: debian/*
    ref: debian/0.0.9-11-0-g9a1fae0987e757c8d04e728eaec6e7adc1efca89

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

config:
  build-commands:
    - autoreconf --install
    - ./configure --prefix=/usr
    - make -j2
  install-commands:
    - install -D -m 0755 min12xxw "%{install-root}/usr/bin/min12xxw"
