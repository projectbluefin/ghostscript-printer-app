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
    ref: f8fd38a30c38b482d62861effaf041f1bff1defb

config:
  options:
    arch: '%{arch}'
