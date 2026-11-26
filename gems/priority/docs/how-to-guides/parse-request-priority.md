# Parse request priority in Rack

Assumes you know what the Priority field is — see [Your first Priority field](../tutorials/priority-field.md).

## Read the header

Rack exposes a request's Priority header as `env["HTTP_PRIORITY"]` (Rack's CGI-derived convention: HTTP_ + uppercased, dashes to underscores) — a String when present, nil when absent. The gem takes no Rack dependency; the examples use a plain Hash standing in for env, exactly the shape Rack hands you.

```ruby
require "fast/priority"

env = { "HTTP_PRIORITY" => "u=2, i" }
priority = Fast::Priority.parse(env["HTTP_PRIORITY"])
priority.urgency      # => 2
priority.incremental  # => true
```

The absent header: `env["HTTP_PRIORITY"]` is nil — a caller bug for `parse` (TypeError), so pass the empty field and take the defaults:

```ruby
require "fast/priority"

env = {}
Fast::Priority.parse(env["HTTP_PRIORITY"] || "").urgency  # => 3
```

Lowercase names: field names may arrive lowercased on HTTP/2 and HTTP/3; the value is what this gem parses — the value's case rules are the Dictionary grammar's, not the header name's.

## Parse it

`Fast::Priority.parse(input)` — the §4 recipient view, never raises on content; TypeError only for a non-String/non-Array input (`lib/fast/priority/field.rb:197-205`).

What a parsed field holds: the §4-valid members, unknown members as parsed, out-of-range/wrong-typed `u`/`i` dropped (never re-emitted) (`lib/fast/priority/field.rb:164-186`).

```ruby
require "fast/priority"

priority = Fast::Priority.parse("u=0, i, foo=bar")
priority.urgency              # => 0
priority.unknown.keys         # => ["foo"]
Fast::Priority.parse("u=9").urgency  # => 3
```

See [Handle malformed or absent Priority](handle-malformed-priority.md) for the full malformed story.

## The defaults and malformed input

Absence and malformedness both answer urgency 3, incremental false, no member held — the §4 SHOULD-defaults and the MUST-ignore filter (`rfc9218.txt:332-334,340-344`).

```ruby
require "fast/priority"

defaults = Fast::Priority.parse("")
defaults.urgency      # => 3
defaults.incremental  # => false
defaults.to_s         # => ""
```

## Multi-line fields

Some stacks hand you a field split across lines; the Array input combines them with `", "` exactly as RFC 9651 §4.2 requires (`lib/fast/priority/field.rb:231-234`).

```ruby
require "fast/priority"

Fast::Priority.parse(["u=5", "i"]).incremental  # => true
```

## What to do with it

Servers may use urgency to order responses and incremental to share bandwidth — all SHOULD/RECOMMENDED level. The RFC's own caution applies: "Endpoints cannot depend on particular treatment based on priority signals. Expressing priority is only a suggestion" (§10, `rfc9218.txt:743-746`).

See [Why malformed input answers the defaults](../explanation/defaults-on-malformed.md) and RFC 9218 §9/§10 for scheduling guidance.
