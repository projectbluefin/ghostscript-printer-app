kind: makemaker
description: Build XML::LibXML against FSDK libxml2 for Foomatic.

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/pkg-config.bst

depends:
  - printer-app/perl-xml-namespace-support.bst
  - printer-app/perl-xml-sax.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/libxml2.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst

sources:
  - kind: cpan
    index: "cpan:"
    name: XML::LibXML
    suffix: authors/id/T/TO/TODDR/XML-LibXML-2.0213.tar.gz
    sha256sum: 2af21c5d61ac34ea26a5fabf15ba5a5841e648f7189db3e33b6f28b5489802ab
  - kind: patch_queue
    path: patches/perl-xml-libxml
