kind: junction

# The shared printing base (printing/base.bst): CUPS, cups-filters,
# libcupsfilters, libppd, ghostscript, mutool, avahi-printing, PAPPL and
# pappl-retrofit, plus the FSDK junction everything else comes from.
# Consumer contract: docs/skills/printing-base.md in fsdk-containers.
# Add no patches, overrides or options besides arch.
sources:
  - kind: git_repo
    url: github:projectbluefin/fsdk-containers.git
    track: main
    ref: f49b0f6523fb661f19e17e45e34dd88144bfde4a
  # The producer generates this gitignored include from its FSDK junction
  # before invoking bst; junction consumers must stage the same value so the
  # shared runtime layer's key (oci/printing-runtime-layer.bst) resolves here.
  - kind: local
    path: junction-files/fsdk-containers/include
    directory: include

config:
  options:
    arch: '%{arch}'
