kind: manual
description: Build the P-Touch CUPS raster filter and Foomatic PPD archive.

sources:
  - kind: git_repo
    url: salsa:printing-team/ptouch-driver.git
    track: debian/*
    ref: debian/1.7-1-0-gccfa92351be3ce601f212048b174147a5496d8be

build-depends:
  - printer-app/foomatic-db-engine.bst
  - printer-app/pyppd.bst
  - printer-app/perl-clone.bst
  - printer-app/perl-xml-libxml.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:printing/foomatic-db.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/gzip.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl-xml-parser.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst

config:
  build-commands:
    - autoreconf --install
    - ./configure --prefix=/usr
    - make -j"%{max-jobs}" rastertoptch generated/stamp-h1
    - |
      cp -a /usr/share/foomatic "$PWD/foomatic-db"
      cp -a generated/. foomatic-db/db/source/
      printf '#\n' > foomatic-db/db/oldprinterids
      FOOMATICDB="$PWD/foomatic-db" \
        foomatic-compiledb -j "%{max-jobs}" -t ppd -d ppd ptouch-pt ptouch-ql
      pyppd -v -o ptouch-ppds ppd
  install-commands:
    - install -D -m 0755 rastertoptch "%{install-root}/usr/lib/cups/filter/rastertoptch"
    - install -D -m 0755 ptouch-ppds "%{install-root}/usr/share/ppd/ptouch-ppds"
