kind: manual
description: Package the rastertosag-gdi Ricoh raster filter and PPDs.

sources:
  - kind: git_repo
    url: salsa:printing-team/rastertosag-gdi.git
    track: debian/*
    ref: debian/0.1-8-0-g6f4028f36f015692a602077b7060438d0bf9f634

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst

config:
  build-commands:
    - pyppd -v -o rastertosag-gdi-ppds ppd
  install-commands:
    - install -D -m 0755 rastertosag-gdi "%{install-root}/usr/lib/cups/filter/rastertosag-gdi"
    - install -D -m 0755 rastertosag-gdi-ppds "%{install-root}/usr/share/ppd/rastertosag-gdi-ppds"
