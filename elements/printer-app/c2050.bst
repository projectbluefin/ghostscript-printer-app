kind: manual
description: Build the c2050 Lexmark raster converter.

sources:
  - kind: git_repo
    url: salsa:printing-team/c2050.git
    track: debian/*
    ref: debian/0.3-7-0-ge2ee50d2da58e552b1ac70ae0b4d8913436921e1
  - kind: patch_queue
    path: patches/c2050

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

config:
  build-commands:
    - make -j2
  install-commands:
    - install -D -m 0755 c2050 "%{install-root}/usr/bin/c2050"
