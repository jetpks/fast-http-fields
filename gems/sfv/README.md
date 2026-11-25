# fast-sfv

fast-sfv implements RFC 9651 Structured Field Values for Ruby — Items,
Lists, and Dictionaries with parameters — the syntax substrate every
other fast-http-fields gem builds on.

> **Parse and serialize landed.** `Fast::SFV.parse_item`, `parse_list`
> and `parse_dict` implement the strict RFC 9651 §4.2 parse — Items,
> Lists and Dictionaries with parameters and inner lists, all eight
> bare item types — and `Fast::SFV.serialize_item`, `serialize_list`
> and `serialize_dict` emit the canonical §4.1 wire form from the same
> value shapes, against the vendored httpwg conformance corpus (1607
> parse records and 1287 serialize records under `test/corpus/`). The
> docs tree and the 0.1.0 release arrive with the next iterations.

```ruby
Fast::SFV.serialize_list(Fast::SFV.parse_list("1, 42"))          # => "1, 42"
Fast::SFV.serialize_dict("a" => Fast::SFV::Item.new(1, {}))      # => "a=1"
```

The require is `fast/sfv`, not `fast-sfv`. Requires Ruby `>= 3.4`. No
runtime dependencies.
