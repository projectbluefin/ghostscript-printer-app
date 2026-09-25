kind: manual
description: Build the Foomatic XML database compiler.

sources:
  - kind: git_repo
    url: github:OpenPrinting/foomatic-db-engine.git
    track: master
    ref: e4e7b9cd28ba160428f82bc5234559d1f50e5c42
  - kind: patch_queue
    path: patches/foomatic-db-engine

build-depends:
  - printer-app/perl-clone.bst
  - printer-app/perl-xml-libxml.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/curl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/file.bst
  - fsdk-containers.bst:printing/foomatic-db.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/gzip.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl-xml-parser.bst

config:
  build-commands:
    - ./make_configure
    - PERL_INSTALLDIRS=vendor ./configure --prefix=/usr --libdir="%{libdir}"
    - make -j1
  install-commands:
    - make DESTDIR="$PWD/full-install" install
    - install -D -m 0755 full-install/usr/sbin/foomatic-compiledb "%{install-root}/usr/bin/foomatic-compiledb"
    - mkdir -p "%{install-root}/usr/lib" && cp -a full-install/usr/lib/perl5 "%{install-root}/usr/lib/"
