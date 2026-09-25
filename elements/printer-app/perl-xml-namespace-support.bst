kind: makemaker
description: Build XML::NamespaceSupport for Foomatic XML parsing.

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:public-stacks/buildsystem-make.bst

depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:components/perl.bst

sources:
  - kind: cpan
    index: "cpan:"
    name: XML::NamespaceSupport
    suffix: authors/id/P/PE/PERIGRIN/XML-NamespaceSupport-1.12.tar.gz
    sha256sum: 47e995859f8dd0413aa3f22d350c4a62da652e854267aa0586ae544ae2bae5ef
