kind: manual
description: Build the m2300w drivers with persistent color-profile paths.

sources:
  - kind: git_repo
    url: salsa:printing-team/m2300w.git
    track: debian/*
    ref: debian/0.51-15-0-gf4ebe31fe93e8f2f56ecce2f927e59bb41432d53

build-depends:
  - printer-app/pyppd.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst

depends:
  - printer-app/psutils.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/cups-filters.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/python3.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/runtime-gnu.bst

config:
  build-commands:
    - autoreconf --install
    - ./configure --prefix=/usr
    - make -j2
    - make INSTROOT="$PWD/stage" install
    - |
      for wrapper in stage/usr/bin/*-wrapper; do
        sed -i \
          -e 's|^PREFIX=.*|PREFIX=/usr|' \
          -e 's|^SHARE=.*|SHARE=/var/lib/ghostscript-printer-app/m2300w/0.51|' \
          -e 's|/tmp|${TMPDIR:-/tmp}|g' \
          -e 's|^$((resX\*=$RESMUL));|resX=$((resX * RESMUL))|' \
          "$wrapper"
      done
    - rm -rf stage/usr/share/m2300w/0.51/foomatic
    - |
      mkdir packaged-ppd
      for model in 2300 2400; do
        source="stage/usr/share/cups/model/Minolta/magicolor_${model}W-m${model}w.ppd"
        target="packaged-ppd/Minolta-magicolor_${model}W-m2300w.ppd"
        cp "$source" "$target"
        sed 's/Minolta/KONICA MINOLTA/g' "$target" > "packaged-ppd/KONICA_MINOLTA-magicolor_${model}W-m2300w.ppd"
        sed -i 's/KONICA MINOLTA/Minolta/g' "$target"
      done
      pyppd -v -o m2300w-ppds packaged-ppd
  install-commands:
    - install -D -m 0755 stage/usr/bin/m2300w "%{install-root}/usr/bin/m2300w"
    - install -D -m 0755 stage/usr/bin/m2400w "%{install-root}/usr/bin/m2400w"
    - install -D -m 0755 stage/usr/bin/m2300w-wrapper "%{install-root}/usr/bin/m2300w-wrapper"
    - install -D -m 0755 m2300w-ppds "%{install-root}/usr/share/ppd/m2300w-ppds"
    - mkdir -p "%{install-root}/usr/share/ghostscript-printer-app/defaults/m2300w" && cp -a stage/usr/share/m2300w/. "%{install-root}/usr/share/ghostscript-printer-app/defaults/m2300w/"
