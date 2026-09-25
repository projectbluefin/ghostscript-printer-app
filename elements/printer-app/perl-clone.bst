kind: makemaker
description: Build the Perl Clone module used by Foomatic.

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst

sources:
  - kind: cpan
    index: "cpan:"
    name: Clone
    suffix: authors/id/A/AT/ATOOMIC/Clone-0.50.tar.gz
    sha256sum: f9732a4a857974db30905233589113003301b585b0cecda29a21cfba5bb014f9
