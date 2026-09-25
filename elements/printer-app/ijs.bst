kind: manual
description: Build the standalone IJS library from the FSDK-pinned Ghostscript source.

sources:
  - kind: git_repo
    url: github:ArtifexSoftware/ghostpdl.git
    track: ghostpdl-10.07.1
    ref: ghostpdl-10.07.1-0-g9a39d68ca934f8e9343f46a2803e765122a3b4a9

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

public:
  bst:
    split-rules:
      devel:
        (>):
          - "%{includedir}"
          - "%{includedir}/**"
          - "%{libdir}/libijs.so"

config:
  build-commands:
    - cd ijs && autoreconf --force --install && ./configure --prefix=/usr --libdir="%{libdir}" --enable-shared --disable-static
    - make -C ijs -j2
  install-commands:
    - make -C ijs DESTDIR="$PWD/full-install" install
    - mkdir -p "%{install-root}%{libdir}" && cp -a "full-install%{libdir}"/libijs*.so* "%{install-root}%{libdir}/"
    - mkdir -p "%{install-root}/usr/include" && cp -a full-install/usr/include/ijs "%{install-root}/usr/include/"
