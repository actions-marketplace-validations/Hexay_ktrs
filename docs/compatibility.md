# Compatibility

## ktlint 1.8

Most teams still run ktlint 1.x, and 2.0 changed rule results, autocorrect order, exit codes and baseline matching
([research/22](../research/22-ktlint-1x-gap.md)). To get 1.8.0 behaviour, add this to `.editorconfig` (the ktlint jars
ignore it), or pass `--ktlint-version=1.8`:

```ini
[*.{kt,kts}]
ktrs_ktlint_version = 1.8
```

This mode ports 1.8's rule differences, its rule-by-rule autocorrect order and its CLI. On 21,000 files it matches the
1.8.0 jar except for a few KDoc whitespace rows, where 1.8's older Kotlin lexer splits trailing spaces differently
([research/26](../research/26-ktlint-18-mode.md)).

## Custom rule sets

`-R` jars are supported, in `ktlint` and `ktrs lint`. [compose-rules](https://github.com/mrmans0n/compose-rules) 0.6.8, by
far the most used rule set, runs natively with output identical to the jar (the `-all.jar` and the Maven artifacts). Any
other rule set or reporter jar hands the whole run to the real ktlint jar (downloaded once and checked by SHA-256; needs
Java), so it works at JVM speed ([research/27](../research/27-custom-rulesets-impl.md)).

## ktfmt version

ktrs formats exactly like ktfmt 0.65, everywhere: the binaries, the Gradle and Maven integrations and the editor support.
Tools that bundle an older ktfmt (ktfmt-gradle 0.27.0 and Spotless's default are on 0.64) therefore format slightly
differently from ktrs: switching to ktrs shows the same one-time diff as upgrading ktfmt to 0.65 (for example, a trailing
comma after a single argument that sits on its own line).

## Limits

- The `ktfmt` binary parses with Kotlin 2.4.21's grammar; ktfmt 0.65 is built on Kotlin 2.4.10, so syntax newer than that
  is accepted here and rejected there.
- ktfmt's undocumented `--experimental-engine` flag is rejected.
