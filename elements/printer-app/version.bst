kind: manual
description: >-
  Stage the application version: the junction's Ghostscript release plus the
  packaging revision kept in VERSION.

sources:
  - kind: local
    path: VERSION

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:bootstrap/bash.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:bootstrap/coreutils.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/ghostscript.bst

config:
  install-commands:
    - |
      ghostscript="$(gs --version)"
      revision="$(cat VERSION)"
      case "$ghostscript" in
        *[!0-9.]*|.*|*.|*..*|"") echo "unexpected Ghostscript version: $ghostscript" >&2; exit 1 ;;
      esac
      case "$revision" in
        0*|*[!0-9]*|"") echo "VERSION must be a positive packaging revision: $revision" >&2; exit 1 ;;
      esac
      install -d "%{install-root}"
      printf '%s-%s\n' "$ghostscript" "$revision" > "%{install-root}/VERSION"
