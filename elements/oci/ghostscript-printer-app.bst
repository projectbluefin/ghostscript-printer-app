kind: script

build-depends:
  - fsdk-containers.bst:freedesktop-sdk.bst:bootstrap/bash.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:bootstrap/coreutils.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/oci-builder.bst
  - fsdk-containers.bst:freedesktop-sdk.bst:components/sed.bst
  - filename: printer-app/version.bst
    config:
      location: /metadata
  - filename: printer-app/core-runtime.bst
    config:
      location: /layer
  - filename: printer-app/runtime-parent.bst
    config:
      location: /parent

variables:
  (@):
    - fsdk-containers.bst:include/slim-printing.yml
  app-forbidden-paths: |
    usr/share/cups/ipptool
    usr/bin/cupsd
    usr/bin/ippeveprinter
    etc/avahi/services/ssh.service
    etc/avahi/services/sftp-ssh.service
  # Shared-recipe removals this image still needs; restored after the gate,
  # and exempted by `just verify-slim`. Each line must match a staged file.
  # psicc: foo2zjs wrappers run it for ICC profiles (printer-app/foo2zjs.bst).
  # libharfbuzz-subset: NEEDED by libpoppler and pdftops (cups-filters).
  app-kept-paths: |
    usr/bin/psicc
    usr/lib/*/libharfbuzz-subset.so*

config:
  commands:
    - |
      set -eu
      shopt -s nullglob
      mkdir -p /tmp/app-kept
      cd /layer
      while IFS= read -r pattern; do
        [ -n "$pattern" ] || continue
        matches=()
        for match in $pattern; do
          if [ -e "$match" ] || [ -L "$match" ]; then matches+=("$match"); fi
        done
        [ "${#matches[@]}" -gt 0 ] || { echo "app-kept-paths: nothing staged for $pattern" >&2; exit 1; }
        cp -a --parents "${matches[@]}" /tmp/app-kept
      done <<'KEEP'
      %{app-kept-paths}
      KEEP
    - "%{slim-printing-commands}"
    - "%{slim-printing-gate-commands}"
    - cp -a /tmp/app-kept/. /layer/
    - |
      version="$(cat /metadata/VERSION)"
      install -d /layer/etc
      printf '%s\n' \
        'root:x:0:0:root:/root:/usr/bin/bash' \
        'nonroot:x:65532:65532:Printer Application:/var/lib/ghostscript-printer-app:/usr/sbin/nologin' \
        >> /layer/etc/passwd
      printf '%s\n' \
        'root:x:0:' \
        'nonroot:x:65532:' \
        >> /layer/etc/group
      rm -rf /layer/run/dbus /layer/run/avahi-daemon /layer/run/ghostscript-printer-app
      rm -rf /layer/usr/lib/debug /layer/usr/share/cups/ipptool
      rm -f /layer/usr/bin/cupsd /layer/usr/bin/ippeveprinter
      # Avahi's sample remote-login records do not describe this appliance.
      # Keep the shared base's avahi-printing element and PAPPL's dynamic IPP publication.
      rm -f /layer/etc/avahi/services/ssh.service \
        /layer/etc/avahi/services/sftp-ssh.service
      chmod 0777 /layer/run
      install -d -m 1777 /layer/tmp
      install -d -m 0777 \
        /layer/var/lib/ghostscript-printer-app \
        /layer/var/lib/ghostscript-printer-app/ppd \
        /layer/var/spool/ghostscript-printer-app
      if [ -f /layer/usr/share/dbus-1/system.conf ]; then
        sed -i '/<user>messagebus<\/user>/d; s/<policy user="root">/<policy user="nonroot">/g' /layer/usr/share/dbus-1/system.conf
      fi
      if [ -f /layer/etc/dbus-1/system.d/avahi-dbus.conf ]; then
        sed -i 's/<policy group="netdev">/<policy group="nonroot">/g; s/<policy user="root">/<policy user="nonroot">/g; s/<policy user="avahi">/<policy user="nonroot">/g' /layer/etc/dbus-1/system.d/avahi-dbus.conf
      fi
      cd "%{install-root}"
      build-oci <<EOF
      mode: oci
      gzip: gzip
      images:
        - os: linux
          architecture: "%{go-arch}"
          # Layer 0 is the shared printing runtime layer, copied byte-for-byte
          # (gzip mode only); /layer stays the full final rootfs.
          parent:
            image: /parent
          layer: /layer
          config:
            User: '65532:65532'
            Entrypoint: ['/usr/bin/catatonit', '--', '/usr/bin/bash', '/usr/libexec/ghostscript-printer-app/container-entrypoint']
            Env:
              - 'HOME=/var/lib/ghostscript-printer-app'
              - 'PATH=/usr/bin:/usr/sbin'
            Labels:
              'org.opencontainers.image.title': 'ghostscript-printer-app'
              'org.opencontainers.image.description': 'Ghostscript Printer Application built from freedesktop-sdk'
              'org.opencontainers.image.source': 'https://github.com/projectbluefin/ghostscript-printer-app'
              'org.opencontainers.image.licenses': 'Apache-2.0'
              'org.opencontainers.image.version': '${version}'
      EOF
