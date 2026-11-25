# Changelog

## Unreleased

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
