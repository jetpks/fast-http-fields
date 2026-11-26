# Validate a field value without exceptions

## The three predicates

`Fast::SFV.valid_item?(input)` → `true`/`false`; `valid_list?`; `valid_dict?` — arity 1 each, the strict parse behind a boolean, never raise.

They mirror `parse_item`/`parse_list`/`parse_dict` exactly on content.

```ruby
require "fast/sfv"

Fast::SFV.valid_item?("@42")  # => true
Fast::SFV.valid_list?("1, 42")  # => true
Fast::SFV.valid_dict?("a=1")  # => true
```

See [API reference](../reference/api.md) for the full signatures. For the throwing variants see [Parse a field value](parse-field-values.md).

## Validate, then parse

```ruby
require "fast/sfv"

value = "1, 42"
list = Fast::SFV.parse_list(value) if Fast::SFV.valid_list?(value)
list.map(&:value)  # => [1, 42]
```

```ruby
require "fast/sfv"

Fast::SFV.valid_item?("@42")  # => true
Fast::SFV.valid_item?("@ 42")  # => false
Fast::SFV.valid_list?("1, 42")  # => true
Fast::SFV.valid_list?("1,")  # => false
Fast::SFV.valid_dict?("a=1,")  # => false
```

## What "invalid" covers

Malformed field content → `false`.

A wrong input type — `42`, `nil`, `3.14`, `:sym`, `{}`, or an Array holding a non-String line — is also `false`, not an exception: a caller bug is not field content either.

```ruby
require "fast/sfv"

Fast::SFV.valid_item?(42)  # => false
Fast::SFV.valid_item?(nil)  # => false
Fast::SFV.valid_list?(["1", 42])  # => false
```

## When to parse instead

The predicates answer only yes/no: they discard the value and the byte offset. When you need either, parse and rescue `Fast::SFV::ParseError` — see [Diagnose a rejected field value](diagnose-failures.md).

Do not use them as a cheap parse (they run the full parse); they are for guarding unknown input.
