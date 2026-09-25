kind: manual
description: Build the HPLIP HPIJS driver with persistent appliance configuration.

sources:
  - kind: git_repo
    url: salsa:printing-team/hplip.v2.git
    track: debian/*
    ref: debian/3.26.4+dfsg0-3-0-gf27f786d5f1060cce7c92e42488bd5e5d00ba135

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/jpeg.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

config:
  build-commands:
    - sed -i 's|"/var/lib/hp|"/var/lib/ghostscript-printer-app/hplip|g' common/utils.c common/utils.h
    - sh debian/autogen.sh
    - >-
      ./configure
      --build=%{gcc-triplet}
      --prefix=/usr
      --enable-hpijs-only-build
      --enable-hpijs-install
      --disable-foomatic-rip-hplip-install
      --without-docdir
      --without-htmldir
      --without-hpppddir
      --without-drvdir
      --without-icondir
      --disable-hpcups-install
      --disable-cups-drv-install
      --disable-cups-ppd-install
      --disable-foomatic-drv-install
      --disable-foomatic-ppd-install
      --disable-network-build
      --disable-pp-build
      --disable-scan-build
      --disable-gui-build
      --disable-fax-build
      --disable-dbus-build
      --disable-qt3
      --disable-qt4
      --disable-qt5
      --disable-policykit
    - make -j2 hpijs
    - |
      sed -i \
        -e 's|^home=.*|home=/usr/share/hplip|' \
        -e 's|^run=.*|run=/var/lib/ghostscript-printer-app/hplip/run|' \
        -e 's|^ppd=.*|ppd=/usr/share/ppd|' \
        -e 's|^ppdbase=.*|ppdbase=/usr/share/ppd|' \
        -e 's|^cupsbackend=.*|cupsbackend=/usr/lib/cups/backend|' \
        -e 's|^cupsfilter=.*|cupsfilter=/usr/lib/cups/filter|' \
        hplip.conf
  install-commands:
    - install -D -m 0755 hpijs "%{install-root}/usr/bin/hpijs"
    - install -d "%{install-root}/usr/share/hplip"
    - install -D -m 0644 hplip.conf "%{install-root}/usr/share/ghostscript-printer-app/defaults/hplip/hplip.conf"
    - mkdir -p "%{install-root}/etc/hp" && ln -s /var/lib/ghostscript-printer-app/hplip/hplip.conf "%{install-root}/etc/hp/hplip.conf"
