# zuxml: Small XML Parser and Document Tree

Reads, navigates, and writes XML documents using a bundled copy of the
'Expat' parser (<https://libexpat.github.io/>), so that no system XML
library is required. Documents are parsed into a faithful immutable tree
exposed through a small vectorized navigation interface. Parsing is
strict by default: document type declarations are rejected, external
entity resolution is not compiled in, and configurable limits bound
nesting depth and memory use. A registered C interface allows other
packages to parse XML without linking against the parser themselves, and
to feed it incrementally so that a large document need not be held in
memory all at once.

## See also

Useful links:

- <https://github.com/pedrobtz/zuxml>

- <https://pedrobtz.github.io/zuxml/>

- Report bugs at <https://github.com/pedrobtz/zuxml/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Clark Cooper (author of the bundled Expat library) \[contributor\]

- Fred L. Drake, Jr. (author of the bundled Expat library)
  \[contributor\]

- Greg Stein (author of the bundled Expat library) \[contributor\]

- James Clark (author of the bundled Expat library) \[contributor\]

- Karl Waclawek (author of the bundled Expat library) \[contributor\]

- Rhodri James (author of the bundled Expat library) \[contributor\]

- Sebastian Pipping (author of the bundled Expat library and contributor
  to siphash.h) \[contributor\]

- Steven Solie (author of the bundled Expat library) \[contributor\]

- William Ahern (derived the bundled SipHash implementation (siphash.h))
  \[contributor\]

- Jean-Philippe Aumasson (co-author of the SipHash reference
  implementation (siphash.h)) \[contributor\]

- Daniel J. Bernstein (co-author of the SipHash reference implementation
  (siphash.h)) \[contributor\]

- Victor Stinner (contributor to siphash.h) \[contributor\]
