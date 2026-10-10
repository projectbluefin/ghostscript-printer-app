kind: manual
description: Build the standalone IJS library from the junction's Ghostscript source.

# FSDK's ghostscript element (as patched by fsdk-containers) supplies the
# ghostpdl source and ref, so IJS always matches the shipped Ghostscript and an
# fsdk-containers bump moves both. Everything else is overridden below.
(@): fsdk-containers.bst:freedesktop-sdk.bst:elements/components/ghostscript.bst

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends: []

public:
  bst:
    split-rules:
      devel:
        (>):
          - "%{includedir}"
          - "%{includedir}/**"
          - "%{libdir}/libijs.so"

environment:
  MAXJOBS: "%{max-jobs}"
environment-nocache:
  - MAXJOBS

config:
  configure-commands: []
  build-commands:
    - cd ijs && autoreconf --force --install && ./configure --prefix=/usr --libdir="%{libdir}" --enable-shared --disable-static
    - make -C ijs -j"${MAXJOBS}"
  install-commands:
    - make -C ijs DESTDIR="$PWD/full-install" install
    - mkdir -p "%{install-root}%{libdir}" && cp -a "full-install%{libdir}"/libijs*.so* "%{install-root}%{libdir}/"
    - mkdir -p "%{install-root}/usr/include" && cp -a full-install/usr/include/ijs "%{install-root}/usr/include/"
