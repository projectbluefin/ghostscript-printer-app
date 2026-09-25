kind: manual
description: Build the JBIG and JBIG85 shared libraries required by legacy drivers.

sources:
  - kind: tar
    url: debian:pool/main/j/jbigkit/jbigkit_2.1.orig.tar.gz
    ref: de7106b6bfaf495d6865c7dd7ac6ca1381bd12e0d81405ea81e7f2167263d932

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

public:
  bst:
    split-rules:
      devel:
        (>):
          - "%{includedir}/jbig85.h"
          - "%{includedir}/jbig.h"
          - "%{includedir}/jbig_ar.h"
          - "%{libdir}/libjbig85.so"
          - "%{libdir}/libjbig.so"

config:
  build-commands:
    - cc $CFLAGS -fPIC -Ilibjbig -c libjbig/jbig85.c -o jbig85.o
    - cc $CFLAGS -fPIC -Ilibjbig -c libjbig/jbig.c -o jbig.o
    - cc $CFLAGS -fPIC -Ilibjbig -c libjbig/jbig_ar.c -o jbig_ar.o
    - cc $LDFLAGS -shared -Wl,-soname,libjbig85.so.0 -o libjbig85.so.0 jbig85.o jbig_ar.o
    - cc $LDFLAGS -shared -Wl,-soname,libjbig.so.0 -o libjbig.so.0 jbig.o jbig_ar.o
  install-commands:
    - install -D -m 0644 libjbig85.so.0 "%{install-root}%{libdir}/libjbig85.so.0"
    - ln -s libjbig85.so.0 "%{install-root}%{libdir}/libjbig85.so"
    - install -D -m 0644 libjbig.so.0 "%{install-root}%{libdir}/libjbig.so.0"
    - ln -s libjbig.so.0 "%{install-root}%{libdir}/libjbig.so"
    - install -D -m 0644 libjbig/jbig85.h "%{install-root}/usr/include/jbig85.h"
    - install -D -m 0644 libjbig/jbig.h "%{install-root}/usr/include/jbig.h"
    - install -D -m 0644 libjbig/jbig_ar.h "%{install-root}/usr/include/jbig_ar.h"
