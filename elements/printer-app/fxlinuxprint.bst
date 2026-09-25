kind: manual
description: Build the Fuji Xerox PDF printer CUPS filters and PPD archive.

sources:
  - kind: git_repo
    url: salsa:printing-team/fxlinuxprint.git
    track: debian/*
    ref: debian/1.1.0+ds-4-0-g3e640d5cf2881b01b6dab16e7d899290e61b0417

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst

config:
  build-commands:
    - autoreconf --install
    - ./configure --prefix=/usr
    - make -j2
    - pyppd -v -o fxlinuxprint-ppds .
  install-commands:
    - install -D -m 0755 pstopdffx "%{install-root}/usr/lib/cups/filter/pstopdffx"
    - install -D -m 0755 pdftopjlfx "%{install-root}/usr/lib/cups/filter/pdftopjlfx"
    - install -D -m 0755 pdftopdffx "%{install-root}/usr/lib/cups/filter/pdftopdffx"
    - install -D -m 0755 fxlinuxprint-ppds "%{install-root}/usr/share/ppd/fxlinuxprint-ppds"
    - install -D -m 0644 mimefx.types "%{install-root}/usr/share/cups/mime/mimefx.types"
    - install -D -m 0644 mimefx.convs "%{install-root}/usr/share/cups/mime/mimefx.convs"
