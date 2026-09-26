kind: manual
description: Build the SpliX QPDL printer filters and PPD archive.

sources:
  - kind: git_repo
    url: salsa:printing-team/splix.git
    track: debian/*
    ref: debian/2.0.1-1-0-g505f24d43fdb86eaa41a44486e7ef88226bb2c0c

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - printer-app/jbigkit.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst

config:
  # SpliX's threaded page cache shares unlocked state between the cache
  # controller, compression and render threads: under CPU contention
  # rastertoqpdl intermittently segfaults with no output. Build the serial
  # renderer, which emits the same QPDL.
  build-commands:
    - >-
      make -j2 V=1
      DISABLE_THREADS=1
      CUPSFILTER="/usr/lib/cups/filter"
      rastertoqpdl_LIBS="-lcupsimage -lcups -ljbig85"
      pstoqpdl_LIBS="-lcupsimage -lcups"
    - cp *.ppd ppd/
    - pyppd -v -o splix-ppds ppd
  install-commands:
    - install -D -m 0755 optimized/pstoqpdl "%{install-root}/usr/lib/cups/filter/pstoqpdl"
    - install -D -m 0755 optimized/rastertoqpdl "%{install-root}/usr/lib/cups/filter/rastertoqpdl"
    - install -D -m 0755 splix-ppds "%{install-root}/usr/share/ppd/splix-ppds"
