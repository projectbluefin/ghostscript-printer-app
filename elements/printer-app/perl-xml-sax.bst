kind: makemaker
description: Build XML::SAX for Foomatic XML parsing.

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
  - printer-app/perl-xml-namespace-support.bst
  - printer-app/perl-xml-sax-base.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst

sources:
  - kind: cpan
    index: "cpan:"
    name: XML::SAX
    suffix: authors/id/G/GR/GRANTM/XML-SAX-1.02.tar.gz
    sha256sum: 4506c387043aa6a77b455f00f57409f3720aa7e553495ab2535263b4ed1ea12a
