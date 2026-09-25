kind: manual
description: Build the pxljr HP Color LaserJet IJS driver and PPD archive.

sources:
  - kind: git_repo
    url: salsa:printing-team/pxljr.git
    track: debian/*
    ref: debian/1.4+repack0-6-0-g6b0dafe66965e5fa398733c04160bd6436d13254

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - printer-app/ijs.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/jpeg.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst

config:
  build-commands:
    - autoreconf --force --install
    - ./configure --prefix=/usr
    - make -j2
    - |
      mkdir ppd
      cp HP-Color_LaserJet_3550-pxljr.ppd ppd/
      cd ppd
      for model in 3500 3600; do
        perl -p -e "s:3550(?!\&quot):${model}:g" HP-Color_LaserJet_3550-pxljr.ppd > "HP-Color_LaserJet_${model}-pxljr.ppd"
      done
      perl -p -i -e 's,^\*cupsFilter:\s*"application/vnd.cups-postscript\s+0\s+foomatic-rip",*cupsFilter: "application/vnd.cups-postscript 100 foomatic-rip"\n*cupsFilter: "application/vnd.cups-pdf 0 foomatic-rip",' *.ppd
      perl -p -i -e 's,(\-sDEVICE=ijs),-dNOINTERPOLATE \1,' *.ppd
      cd ..
      pyppd -v -o pxljr-ppds ppd
  install-commands:
    - install -D -m 0755 ijs_pxljr "%{install-root}/usr/bin/ijs_pxljr"
    - install -D -m 0755 pxljr-ppds "%{install-root}/usr/share/ppd/pxljr-ppds"
