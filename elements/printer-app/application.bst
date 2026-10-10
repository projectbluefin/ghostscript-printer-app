kind: manual
description: Build the Ghostscript Printer Application executable.

sources:
  - kind: local
    path: Makefile
  - kind: local
    path: ghostscript-printer-app.c
  - kind: local
    path: ghostscript-printer-app.1
  - kind: local
    path: ghostscript-printer-app.service
  - kind: local
    path: testpage.ps

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - filename: printer-app/version.bst
    config:
      location: /metadata

depends:
  - fsdk-containers.bst:printing/pappl-retrofit.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst

environment:
  MAXJOBS: "%{max-jobs}"
environment-nocache:
  - MAXJOBS

config:
  build-commands:
    - make clean
    - make -j"${MAXJOBS}" VERSION="$(cat /metadata/VERSION)" LDFLAGS="$LDFLAGS -ljpeg"
  install-commands:
    - make DESTDIR="%{install-root}" VERSION="$(cat /metadata/VERSION)" LDFLAGS="$LDFLAGS -ljpeg" unitdir= install
