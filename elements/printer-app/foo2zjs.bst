kind: manual
description: Build foo2zjs drivers with persistent color-profile paths.

sources:
  - kind: git_repo
    url: salsa:printing-team/foo2zjs.git
    track: debian/*
    ref: debian/20200505dfsg0-5-0-g816bcd01d5fa0b3171fe6d09c093a9290ccf7c25

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
  - printer-app/jbigkit.bst
  - printer-app/psutils.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/bc.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/file.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/grep.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/lcms.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

config:
  build-commands:
    - |
      for wrapper in *-wrapper.in; do
        sed -i \
          -e 's|$PREFIX/share/foo2|/var/lib/ghostscript-printer-app/foo2zjs/foo2|g' \
          -e 's|ICC2PS=$PREFIX/bin/foo2zjs-icc2ps|ICC2PS=/usr/bin/psicc|' \
          -e 's|/tmp|${TMPDIR:-/tmp}|g' \
          -e 's|dNOPAUSE|dNOPAUSE -dNOINTERPOLATE|g' \
          "$wrapper"
      done
    - >-
      make -j2
      foo2zjs zjsdecode arm2hpdl
      foo2hp foo2xqx xqxdecode
      foo2lava lavadecode foo2qpdl qpdldecode opldecode
      foo2oak oakdecode foo2slx slxdecode
      foo2hiperc hipercdecode foo2hbpl2 hbpldecode
      gipddecode foo2ddst ddstdecode usb_printerid
      foo2zjs-wrapper foo2oak-wrapper foo2hp2600-wrapper
      foo2xqx-wrapper foo2lava-wrapper foo2qpdl-wrapper
      foo2slx-wrapper foo2hiperc-wrapper foo2hbpl2-wrapper
      foo2ddst-wrapper foo2zjs-pstops
      CUPS_SERVERBIN=/usr/lib/cups CUPS_DEVEL=1 CUPS_GOODAPI=1
    - make command2foo2lava-pjl CUPS_SERVERBIN=/usr/lib/cups CUPS_DEVEL=1 CUPS_GOODAPI=1
    - |
      cp -a PPD ppd
      for model in 1000 1005 1018 1020 P1005 P1006 P1007 P1008 P1505; do
        rm -f "ppd/HP-LaserJet_${model}.ppd"
      done
      pyppd -v -o foo2zjs-ppds ppd
  install-commands:
    - |
      install -d "%{install-root}/usr/bin"
      for file in \
        foo2zjs zjsdecode arm2hpdl \
        foo2hp foo2xqx xqxdecode \
        foo2lava lavadecode foo2qpdl qpdldecode opldecode \
        foo2oak oakdecode foo2slx slxdecode \
        foo2hiperc hipercdecode foo2hbpl2 hbpldecode \
        gipddecode foo2ddst ddstdecode usb_printerid \
        foo2zjs-wrapper foo2oak-wrapper foo2hp2600-wrapper \
        foo2xqx-wrapper foo2lava-wrapper foo2qpdl-wrapper \
        foo2slx-wrapper foo2hiperc-wrapper foo2hbpl2-wrapper \
        foo2ddst-wrapper foo2zjs-pstops; do
        install -m 0755 "$file" "%{install-root}/usr/bin/$file"
      done
    - install -D -m 0755 command2foo2lava-pjl "%{install-root}/usr/lib/cups/filter/command2foo2lava-pjl"
    - install -D -m 0755 foo2zjs-ppds "%{install-root}/usr/share/ppd/foo2zjs-ppds"
    - |
      defaults="%{install-root}/usr/share/ghostscript-printer-app/defaults/foo2zjs"
      for directory in foo2zjs foo2oak foo2hp foo2xqx foo2lava foo2qpdl foo2slx foo2hiperc foo2hbpl foo2ddst; do
        install -d "$defaults/$directory/icm"
      done
      install -m 0644 gamma.ps gamma-lookup.ps "$defaults/foo2zjs/"
      install -d "$defaults/foo2zjs/crd" "$defaults/foo2qpdl/crd"
      cp -a crd/zjs/. "$defaults/foo2zjs/crd/"
      cp -a crd/qpdl/. "$defaults/foo2qpdl/crd/"
