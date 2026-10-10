# Publish immutable application versions

Superseded by [0004](0004-publish-every-verified-testing-commit.md).

OCI publication will occur only from `v<application-version>` Git tags and will use the Ghostscript-derived application version plus packaging revision. The registry will not publish a `latest` alias: consumers must select an immutable application release, while OCI labels and attestations record the exact freedesktop-sdk version and source revision used to build it. Published images are keyless-signed; signed Git tags are not required.
