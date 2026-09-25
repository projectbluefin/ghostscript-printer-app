kind: manual
description: Generate the core cups-filters and Foomatic PPD archives.

build-depends:
  - printer-app/foomatic-db-engine.bst
  - printer-app/pyppd.bst
  - printer-app/perl-clone.bst
  - printer-app/perl-xml-libxml.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:printing/foomatic-db.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/gzip.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl-xml-parser.bst

config:
  build-commands:
    - |
      mkdir -p payload/cupsfilters
      cp -a /usr/share/ppd/cupsfilters/. payload/cupsfilters/
      pyppd -v -o cups-filters-ppds payload/cupsfilters
    - |
      mkdir -p payload/foomatic
      cp -a /usr/share/foomatic/. payload/foomatic/
      rm -rf \
        payload/foomatic/db/source/PPD/Kyocera \
        payload/foomatic/db/source/PPD/Utax \
        payload/foomatic/db/source/PPD/Oce \
        payload/foomatic/db/source/PPD/*/PS
      rm -f \
        payload/foomatic/db/source/driver/bjc800j.xml \
        payload/foomatic/db/source/driver/c2070.xml \
        payload/foomatic/db/source/driver/drv_x125.xml \
        payload/foomatic/db/source/driver/lm1100.xml \
        payload/foomatic/db/source/driver/lpstyl.xml \
        payload/foomatic/db/source/driver/ml85p.xml \
        payload/foomatic/db/source/driver/pbm2l2030.xml \
        payload/foomatic/db/source/driver/pbm2l7k.xml \
        payload/foomatic/db/source/driver/pbm2lwxl.xml \
        payload/foomatic/db/source/driver/pentaxpj.xml \
        payload/foomatic/db/source/driver/ppmtomd.xml
      FOOMATICDB="$PWD/payload/foomatic" \
        foomatic-compiledb -j "%{max-jobs}" -t ppd -d payload/foomatic-ppds
      pyppd -v -o foomatic-ppds payload/foomatic-ppds
      pyppd -v -o manufacturer-ppds payload/foomatic/db/source/PPD
  install-commands:
    - install -D -m 0755 cups-filters-ppds "%{install-root}/usr/share/ppd/cups-filters-ppds"
    - install -D -m 0755 foomatic-ppds "%{install-root}/usr/share/ppd/foomatic-ppds"
    - install -D -m 0755 manufacturer-ppds "%{install-root}/usr/share/ppd/manufacturer-ppds"
