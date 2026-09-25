kind: manual
description: Build the legacy psnup helper required by stateful driver wrappers.

sources:
  - kind: git_repo
    url: salsa:debian/psutils.git
    track: debian/1.*
    ref: debian/1.17.dfsg-5-0-gafa3fccb4b77165a22b783f21feac35a082d8137

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

config:
  build-commands:
    - sed -i 's/^CFLAGS = /CFLAGS = -std=gnu89 /' Makefile.unix
    - make -f Makefile.unix -j2 psnup CC=cc PAPER=a4
  install-commands:
    - install -D -m 0755 psnup "%{install-root}/usr/bin/psnup"
