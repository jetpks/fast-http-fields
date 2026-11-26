# Targeted cache control and the age penalty

## One freshness model, several caches

"HTTP caching has a single, end-to-end freshness model defined in Section 4.2 of [HTTP-CACHING]. When additional freshness mechanisms are only available to some caches along a request path (for example, using targeted fields), their interactions need to be carefully considered. In particular, a targeted cache might have longer freshness lifetimes available to it than other caches, causing it to serve responses that appear to be prematurely (or even immediately) stale to those other caches, negatively impacting cache efficiency".

## The example

§2.3's own example:

```text
Age: 1800
Cache-Control: max-age=600
CDN-Cache-Control: max-age=3600
```

And its explanation: "From the CDN's perspective, this response is still fresh after being cached for 30 minutes, while from the standpoint of other caches, this response is already stale. See [AGE-PENALTY] for more discussion".

Why this happens — the CDN's 3600 seconds of freshness include time the response has already aged downstream of the origin; the Age header carries that age forward, so a downstream cache's 600-second budget is consumed by the CDN's dwell time.

## The mitigations the RFC names

"When the targeted cache has a strong coherence mechanism (e.g., the origin server has the ability to proactively invalidate cached responses), it is often desirable to mitigate these effects. Some techniques seen in deployments include: Removing the Age header field; Updating the Date header field value to the current time; Updating the Expires header field value to the current time, plus any Cache-Control: max-age value". And the boundary: "This specification does not place any specific requirements on implementations to mitigate these effects, but definitions of targeted fields can do so".

## What this class does about it

Nothing, deliberately — and that is the point: the class is a field-value object; freshness arithmetic, Age rewriting and Date updates belong to the cache that uses the field:

```ruby
field = Fast::TargetedCacheControl.parse("max-age=3600")
field["max-age"]  # => 3600
```

What a longer CDN freshness buys you (the §2 rationale — invalidation relationships allow more generous policies) and what it costs downstream (the age penalty); the operator decides both.

See [Emit CDN-Cache-Control](../how-to-guides/emit-cdn-cache-control.md) and [The Targeted Cache Control boundary](the-targeted-cache-control-boundary.md).
