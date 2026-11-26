# The Targeted Cache Control boundary

## Legacy Cache-Control is not a Structured Field

"Note that while targeted fields often have the same syntax as Cache-Control fields, differences in error handling mean that using a Cache-Control parser rather than a Structured Fields parser can introduce interoperability issues". The class parses the RFC 9651 Dictionary ONLY — the legacy `Cache-Control` field (RFC 9111 §5.2, a list-syntax field, not SFV) is out of scope: there is no `Cache-Control` entry point, and the mapping between the two vocabularies is §2.1's, stated in the docs, never computed by the code.

## The target list is cache policy

"A cache that implements this specification maintains a target list. A target list is an ordered list of the targeted field names that it uses for caching policy, with the order reflecting priority from most applicable to least"; "the cache MUST select the first (in target-list order) field with a valid, non-empty value and use its value to determine the caching policy for the response, and it MUST ignore the Cache-Control and Expires header fields in that response, unless no valid, non-empty value is available from the listed header fields"; "Targeted fields that are not on a cache's target list MUST NOT change that cache's behavior and MUST be passed through".

None of this is a field-value fact. A single value object cannot know which names a cache targets, which field was selected, or that Cache-Control and Expires were ignored — the class parses one field's value and the cache owns the policy.

## The suffix is only a convention

"By convention, targeted fields have the suffix '-Cache-Control' … However, this suffix MUST NOT be used on its own to identify targeted fields; it is only a convention". The class is name-agnostic and carries no suffix matcher — only `FIELD_NAME`, the one registered instance:

```ruby
Fast::TargetedCacheControl.respond_to?(:targeted_name?)  # => false
```

## Directive semantics are the cache's

"The semantics and precedence of cache directives in a targeted field are the same as those in Cache-Control. In particular, no-store and no-cache make max-age inoperative, and unrecognized extension directives are ignored". The class never computes precedence, inoperativeness or freshness — it holds the directives and their values.

Parameters on directives are ignored, per §2.1 — preserved in the raw member data, never flagged, re-emitted by a round-trip:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=600;foo=1")
field.members["max-age"].params  # => {"foo" => 1}
field.violating                  # => []
field.to_s                       # => "max-age=600;foo=1"
```

The boundary is what makes the class a field library rather than a cache — everything on the other side of it is a cache's job (see [Targeted cache control and the age penalty](age-penalty.md) for the freshness side and [Emit CDN-Cache-Control](../how-to-guides/emit-cdn-cache-control.md) for the sender's side).
