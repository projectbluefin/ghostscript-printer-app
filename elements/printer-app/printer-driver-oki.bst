kind: manual
description: Package the OKI shell filters and PPD archive.

sources:
  - kind: git_repo
    url: github:rbalint/printer-driver-oki.git
    track: 1.*
    ref: 1.0.2-0-g9f48d5a6c5938126a5aa91a902668aa877c3c22b

build-depends:
  - printer-app/pyppd.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-daemon-only.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/grep.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

config:
  build-commands:
    - |
      sed -i \
        -e '/^[[:space:]]*PATH=/d' \
        -e '/^[[:space:]]*export PATH[[:space:]]*$/d' \
        -e '/^[[:space:]]*GSCRIPT_LIB=/d' \
        -e '/^[[:space:]]*export GSCRIPT_LIB[[:space:]]*$/d' \
        -e 's|${TMPDIR:-/tmp}|${TMPDIR}|g' \
        filters/*
    - sed -i 's/^\(\*LanguageVersion:[[:space:]]*\).*/\1Portuguese/' MFP/OK4X1PSBR.ppd
    - |
      mkdir ppd
      cp */*.ppd */*/*/*.ppd */*/*/*/*.ppd ppd/
      pyppd -v -o oki-ppds ppd
  install-commands:
    - install -d -m 0755 "%{install-root}/usr/lib/cups/filter"
    - install -m 0755 filters/* "%{install-root}/usr/lib/cups/filter/"
    - install -D -m 0755 oki-ppds "%{install-root}/usr/share/ppd/oki-ppds"
