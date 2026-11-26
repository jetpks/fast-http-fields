# Field injection and the trusted path

RFC 9440 §4 and Appendix B.1 — the injection attack, the trusted path, and why the flat field structure matters.

## The attack

RFC 9440 §4's MUST: "In order to prevent field injection, backend servers MUST only accept the Client-Cert and Client-Cert-Chain header fields from a trusted TTRP (or other proxy in a trusted path from the TTRP). A TTRP MUST sanitize the incoming request before forwarding it on by removing or overwriting any existing instances of the fields. Otherwise, arbitrary clients can control the field values as seen and used by the backend server".

Appendix B.1's plain statement of the same: "Otherwise, a client could inject its own values that would appear to the backend to have come from the TTRP".

## Why it does not fail safe

RFC 9440 §4's warning: "It is important to note that neglecting to prevent field injection does not 'fail safe' in that the nominal functionality will still work as expected even when malicious actions are possible. As such, extra care is recommended in ensuring that proper field sanitation is in place". The broken deployment keeps working — that is the danger.

The fail-closed parse protects against unreadable fields, not untrusted ones — a perfectly-formed injected field parses perfectly; the trust boundary is the connection, and no field value can carry its own provenance.

See [Fail-closed: the unauthenticated connection](fail-closed-semantics.md).

## Sanitizing is the mechanism

Appendix B.1's reasoning: "Although numerous other methods of detecting and preventing field injection are possible, such as the use of a unique secret value as part of the field name or value or the application of a signature, HMAC, or AEAD, there is no common general mechanism. ... Since a generic common solution does not currently exist, stripping and sanitizing the fields is the de facto means of protecting against field injection in practice. Sanitizing the fields is sufficient when properly implemented and is a normative requirement of Section 4".

RFC 9440 §2.4's rules are the implementation of that requirement: rule 3 (remove or overwrite before forwarding, MAY reject with 400) and the non-negotiated-connection MUST.

See [Insert Client-Cert and Client-Cert-Chain into forwarded requests](../how-to-guides/insert-the-fields-into-forwarded-requests.md).

## Why not Forwarded

Appendix B.2's argument, in three quoted moves: the Forwarded field "allows proxy components to disclose information lost in the proxying process" and the certificate information "could have been communicated with an extension parameter to the Forwarded field"; but "The multi-hop syntax of the Forwarded field is expressive but also more complicated, which would make processing it more cumbersome and, more importantly, would make properly sanitizing its content, as required by Section 4 to prevent field injection, considerably more difficult and error-prone. Thus, this document opted for a flatter and more straightforward structure".

The flat structure is why the two fields are one Item and one List of Byte Sequences — shapes a sanitizer can match on a field-name and strip wholesale.

## The trusted path

RFC 9440 §4's requirements beyond sanitization: "The communication between a TTRP and backend server needs to be secured against eavesdropping and modification by unintended parties", and the forms it may take — "might be authenticated in some way with the insertion and consumption of the Client-Cert and Client-Cert-Chain header fields occurring only on that connection. Appendix B.3 of [HTTPSIG] gives one example of this with an application of HTTP Message Signatures. Alternatively, the network topology might dictate a private network such that the backend application is only able to accept requests from the TTRP and the proxy can only make requests to that server".

The opt-in default: "Producing and consuming the Client-Cert and Client-Cert-Chain header fields SHOULD be configurable options ... The default configuration for both should be to not use the header fields, thus requiring an 'opt-in' to the functionality".

Every requirement in this doc is a deployment property — the gem carries none of them; it carries the field grammar and the fail-closed semantics, and the deployment carries the trust.
