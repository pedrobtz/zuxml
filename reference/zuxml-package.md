# zuxml: Small and Secure XML Parser and Document Tree

Reads, navigates, and writes XML documents using a bundled copy of the
'Expat' parser (<https://libexpat.github.io/>), so that no system XML
library is required. Documents are parsed into a faithful immutable tree
exposed through a small vectorized navigation interface, and large
inputs can be parsed incrementally from a stream. Parsing is strict and
secure by default: document type declarations are rejected, external
entity resolution is not compiled in, and configurable limits bound
nesting depth and memory use. A registered C interface allows other
packages to parse XML without linking against the parser themselves.

## See also

Useful links:

- <https://github.com/pedrobtz/zuxml>

- Report bugs at <https://github.com/pedrobtz/zuxml/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- Thai Open Source Software Center Ltd (Expat, bundled in
  src/vendor/expat) \[copyright holder\]

- Clark Cooper (Expat, bundled in src/vendor/expat) \[copyright holder\]

- Expat maintainers (Expat, bundled in src/vendor/expat) \[copyright
  holder\]
