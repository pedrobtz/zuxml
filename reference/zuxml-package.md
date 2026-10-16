# zuxml: Small and Secure XML Parser and Document Tree

Reads, navigates, and writes XML documents using a bundled copy of the
'Expat' parser (<https://libexpat.github.io/>), so that no system XML
library is required. Documents are parsed into a faithful immutable tree
exposed through a small vectorized navigation interface. Parsing is
strict and secure by default: document type declarations are rejected,
external entity resolution is not compiled in, and configurable limits
bound nesting depth and memory use. A registered C interface allows
other packages to parse XML without linking against the parser
themselves, and to feed it incrementally so that a large document need
not be held in memory all at once.

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

- Thai Open Source Software Center Ltd (Expat, bundled in
  src/vendor/expat) \[copyright holder\]

- Expat maintainers (Expat, bundled in src/vendor/expat) \[copyright
  holder\]

- Sony Corporation (Expat, bundled in src/vendor/expat) \[copyright
  holder\]

- Rolf Eike Beer (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Nick Begg (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Francesco Bertolaccini (Expat, bundled in src/vendor/expat)
  \[contributor, copyright holder\]

- Thomas Beutlich (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Alexander Bluhm (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Atrem Borovik (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Hanno B\<U+00F6\>ck (Expat, bundled in src/vendor/expat)
  \[contributor, copyright holder\]

- Darren Carreras (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- James Clark (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Clark Cooper (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Pascal Cuoq (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Owain Davies (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Snild Dolkow (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Fred L. Drake, Jr. (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Martin Ettl (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Matthew Fernandez (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Gaurav (Expat, bundled in src/vendor/expat) \[contributor, copyright
  holder\]

- Alfonso Gregory (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Yury Gribov (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Gustavo Grieco (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Jos\<U+00E9\> Guti\<U+00E9\>rrez de la Concha (Expat, bundled in
  src/vendor/expat) \[contributor, copyright holder\]

- Taichi Haradaguchi (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Jann Horn (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Haris Hussain (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Rhodri James (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Kartik Kenchi (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Boris Kolpackov (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Evgeny Kotkov (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Don Lewis (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Zeyou Liu (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- David Loffredo (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Marco Maggi (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Anton Maklakov (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Alberto Maschietto (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Sean McBride (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Donghee Na (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Benbuck Nason (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Samanta Navarro (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Christian Ng (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Chanho Park (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Rosen Penev (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Benjamin Peterson (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Sebastian Pipping (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Eric Rahm (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Cristian Rodr\<U+00ED\>guez (Expat, bundled in src/vendor/expat)
  \[contributor, copyright holder\]

- Ed Schouten (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Thijs Schreijer (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Orgad Shaneh (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- V\<U+00E1\>clav Slav\<U+00ED\>k (Expat, bundled in src/vendor/expat)
  \[contributor, copyright holder\]

- Steven Solie (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Greg Stein (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Viktor Szakats (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Karl Waclawek (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Ben Wagner (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Jeffrey Walton (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Hans Wennborg (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Matthew Wozniczka (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Mariusz Zaborski (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Vadim Zeitlin (Expat, bundled in src/vendor/expat) \[contributor,
  copyright holder\]

- Berkay Eren \<U+00DC\>r\<U+00FC\>n (Expat, bundled in
  src/vendor/expat) \[contributor, copyright holder\]

- William Ahern (derived the bundled SipHash implementation (siphash.h))
  \[contributor\]

- Jean-Philippe Aumasson (co-author of the SipHash reference
  implementation (siphash.h)) \[contributor\]

- Daniel J. Bernstein (co-author of the SipHash reference implementation
  (siphash.h)) \[contributor\]

- Victor Stinner (contributor to siphash.h) \[contributor\]
