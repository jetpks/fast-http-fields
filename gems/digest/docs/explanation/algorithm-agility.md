# Algorithm agility and the registry's statuses

## Why agility is designed in

"The security properties of hashing algorithms are not fixed. Algorithm agility … is achieved by providing implementations with flexibility to choose hashing algorithms from the IANA Hash Algorithms for HTTP Digest Fields registry" (`rfc9530.txt:665-670`).

The two agility levers: negotiation via the Want fields, or sending multiple digests from which the receiver chooses (`rfc9530.txt:671-673`); the transition story of §2's multi-digest rationale (`rfc9530.txt:305-312`).

## What Active means

"Algorithms with a status value of 'Active' are suitable for many purposes and it is RECOMMENDED that applications use these algorithms. These can be used in adversarial situations where hash functions might need to provide resistance to collision, first-preimage, and second-preimage attacks" (`rfc9530.txt:490-495`).

## What Deprecated means (and does not)

A Deprecated algorithm "MAY be used to preserve integrity against corruption, but MUST NOT be used in a potentially adversarial setting, for example, when signing Integrity fields' values for authenticity" (`rfc9530.txt:500-505`), with a legacy-migration allowance for stored digest collections (`rfc9530.txt:505-512`). The gem's stance: the status is advisory, never a gate — md5 and sha parse, emit and compute exactly like the Active ones; the adversarial-setting judgment is the caller's (`lib/fast/digest/registry.rb:18-23`).

## The weakest algorithm rule

"A receiver that depends on a digest for security will be vulnerable to attacks on the weakest algorithm it is willing to accept" and "Integrity fields do not provide any mitigations for downgrade or substitution attacks … endpoints could restrict their set of supported algorithms to stronger ones and protect the fields' values by using TLS and/or digital signatures" (`rfc9530.txt:674-676,680-684`).

The multi-digest field carries every algorithm the sender is willing to speak; the receiver that verifies only the weakest one has downgraded itself. The selection policy is the caller's — see [Choose hashing algorithms](../how-to-guides/choose-algorithms.md) and [Ask for digests with Want-Content-Digest and Want-Repr-Digest](../how-to-guides/request-digest-preferences.md).

## The registry as pinned data

The gem pins Table 2 at publication and passes unknown keys through: future registrations never break old gem versions; the four checksum entries are carried but never computed locally — the registry is the only source of their digest values (`lib/fast/digest/registry.rb:12-52`; the registries-as-data family rule). §5's registration procedure (Specification Required, `rfc9530.txt:517-519`) and the designated-expert status guidance (`rfc9530.txt:520-556`) are the growth path. See [The hash algorithm registry](../reference/algorithms.md).
