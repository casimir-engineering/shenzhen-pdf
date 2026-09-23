# Shenzhen Reader mobile proposal

Start with **index.html** for the complete illustrated document and interactive mockups, or **spec.md** for the canonical implementation specification. This folder is a design deliverable; no Android/iPhone app or native performance result is implied. It changes no desktop reader code.

**Final independent review:** specification 9.57/10 and visual prototype 9.57/10 after eight total rounds; no unresolved major or medium findings in the reviewed design flows. Native implementation gates remain separate.

## Open the document

From this folder run `python3 -m http.server 61206 --bind 127.0.0.1`, then open `http://127.0.0.1:61206/`. Any free local port works. The finished HTML and prototype use local assets/system fonts; no install or build is needed to view them.

To regenerate index.html after editing the specification/reviews, run `node build-doc.cjs` with `marked` available through Node's module search path. This run used marked 17.0.5 from the Codex bundled workspace runtime. Generated HTML is included so this dependency is not required for reading.

## Authority and evidence

- `spec.md`: final product, architecture, storage and acceptance contracts.
- `director-notes.md`: independent creative direction, kept as historical input; its opening notice explains superseded choices.
- `prototype*.html/css/js`: code-native design mockups, with simulated documents and in-memory state. This HTML prototype is not the proposed React Native implementation or proof that a native engine works.
- `prototype-readme.md`: interactions and validation limits.
- `reviews/`: independent scored text reviews first, then visual reviews; ranked findings remain available even after correction.
- `journal.md`: decisions, revisions and evidence boundaries.
- `prototype-evidence/`: initial rendered evidence and fixture test results. Later screenshots may be superseded by source corrections; see the journal and reviews.

The proposed 1 GiB mobile archive limit, SQLite live authority and YAML interchange are deliberate mobile recommendations, not desktop setting changes. PDF/EPUB engine integration, licensing, native accessibility, real-device opening times and actual storage savings remain Gate 0/implementation tests.
