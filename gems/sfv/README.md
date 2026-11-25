# fast-sfv

fast-sfv implements RFC 9651 Structured Field Values for Ruby — Items,
Lists, and Dictionaries with parameters — the syntax substrate every
other fast-http-fields gem builds on.

> **Scaffold.** This iteration stands up the monorepo and the gem's
> skeleton: the module, its version, the test harness, the gemspec, and
> the packaging machinery. The grammar (strict parse per RFC 9651 §4.2,
> canonical serialization per §4.1, the httpwg conformance corpus),
> the docs, and the 0.1.0 release arrive with the next iterations.

The require is `fast/sfv`, not `fast-sfv`. Requires Ruby `>= 3.4`. No
runtime dependencies.
