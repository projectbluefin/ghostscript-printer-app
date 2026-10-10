# Ghostscript Printer Application

This repository packages a Printer Application that exposes classic Ghostscript and CUPS printer drivers through modern IPP interfaces.

## Language

**Printer Application**:
A PAPPL service that presents one or more traditional printer drivers as driverless IPP printers.
_Avoid_: print server, CUPS server

**Driver payload**:
The complete set of printer filters, backends, PPD data, profiles, and supporting runtimes shipped for the Printer Application.
_Avoid_: package set, extras

**OCI appliance**:
The runnable OCI artifact containing the Printer Application, its driver payload, and the service processes required for discovery and operation. It is minimized but not assumed to be shell-free.
_Avoid_: distroless image, Rock

**Driver parity**:
The OCI appliance supports every driver family and user-visible runtime behavior advertised by the current OCI distribution.
_Avoid_: build parity, package parity

**Application release**:
A signed OCI publication of one verified `testing` commit, tagged immutably by commit and carrying the application version: the packaged Ghostscript version plus a packaging revision.
_Avoid_: FSDK release, latest
