# fast-sfv

fast-sfv implements RFC 9651 Structured Field Values for Ruby — Items,
Lists, and Dictionaries with parameters — the syntax substrate every
other fast-http-fields gem builds on.

> **Parse landed.** `Fast::SFV.parse_item`, `parse_list` and `parse_dict`
> implement the strict RFC 9651 §4.2 parse — Items, Lists and Dictionaries
> with parameters and inner lists, all eight bare item types — against the
> vendored httpwg conformance corpus (1607 records under `test/corpus/`).
> Canonical serialization (§4.1), the docs tree and the 0.1.0 release
> arrive with the next iterations.

The require is `fast/sfv`, not `fast-sfv`. Requires Ruby `>= 3.4`. No
runtime dependencies.
