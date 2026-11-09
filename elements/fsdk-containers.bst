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
    ref: f51492ab5a19f353617bc147eb2ffe705579ab58

config:
  options:
    arch: '%{arch}'
