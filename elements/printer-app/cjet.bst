kind: manual
description: Build the cjet Canon CaPSL raster converter.

sources:
  - kind: git_repo
    url: salsa:printing-team/cjet.git
    track: debian/*
    ref: debian/0.8.9-11-0-g2de422f1b08cdf8d18a2e2ea8ae0b14751702fba

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/patch.bst

config:
  build-commands:
    - |
      while read -r patch_file; do
        patch -p1 < "debian/patches/$patch_file"
      done < debian/patches/series
    - make -j2
  install-commands:
    - install -D -m 0755 cjet "%{install-root}/usr/bin/cjet"
