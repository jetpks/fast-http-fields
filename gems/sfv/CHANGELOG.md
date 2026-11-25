# Changelog

## Unreleased

- Serializer: `Fast::SFV.serialize_item`/`serialize_list`/
  `serialize_dict` and `to_s` on the value objects — the strict RFC
  9651 §4.1 emit (all eight bare item types, parameters, inner lists,
  dictionaries, the Boolean-true short forms, the empty-container field
  omission), append-only byte emission with the Ruby type as the
  wire-type tag (no coercion, no content inference), the positioned
  `Fast::SFV::SerializeError`, and the vendored httpwg corpus's
  serialize side (553 serialisation-tests records plus 734 parse-side
  round trips) refereeing every emit edge, with the decimal digits
  rounded as written and ties to even. The emit allocation budgets (the
  output String only) join the parse budgets, and the benchmark bundle
  (`gems.rb` + `benchmark/sfv.rb`) compares against starry, the RFC
  8941 reference implementation, on the common surface — a reference
  comparison, never a runtime dependency. The docs tree and the release
  stay pending.
- Parser: `Fast::SFV.parse_item`/`parse_list`/`parse_dict` with the
  `valid_item?`/`valid_list?`/`valid_dict?` mirrors — the strict RFC 9651
  §4.2 grammar (all eight bare item types, parameters, inner lists,
  dictionaries, the `", "` field-line combining), the frozen value
  objects (`Item`, `InnerList`, `Date`, `DisplayString`), the positioned
  `Fast::SFV::ParseError`, and the vendored httpwg conformance corpus
  (1607 records) refereeing every grammar edge. Serialization, the docs
  tree and the release stay pending.
- Scaffold: `Fast::SFV` module and version, the monorepo test harness
  (`config/sus.rb` routing `gems/*/lib` + `gems/*/test`), the gemspec,
  and the packaging machinery (CI build loop, release dispatch map,
  `script/verify-packaged.rb`). The grammar itself lands with the next
  iterations; 0.1.0 is cut only after the docs iteration.
