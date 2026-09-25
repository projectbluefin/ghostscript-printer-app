kind: manual
description: Build the brlaser Brother laser raster filter.

sources:
  - kind: git_repo
    url: github:pdewacht/brlaser.git
    track: v*
    ref: v6-0-g23117fe9e0266396e4791cdae84d979928aed135

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-cmake.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst

config:
  build-commands:
    - cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    - cmake --build build --target rastertobrlaser -j2
  install-commands:
    - install -D -m 0755 build/rastertobrlaser "%{install-root}/usr/lib/cups/filter/rastertobrlaser"
    - install -D -m 0644 build/brlaser.drv "%{install-root}/usr/share/ppd/brlaser.drv"
