# Gradle, Maven and Spotless

`ktrs migrate` makes these edits for you ([README](../README.md#migrating)). This page shows what it writes and what
each drop-in keeps.

## Gradle

### ktfmt-gradle

The `io.github.hexay.ktrs` plugin replaces [ktfmt-gradle](https://github.com/cortinico/ktfmt-gradle) 0.27.0. Change only
the plugin id. The `ktfmt { }` block, the `ktfmtCheck`/`ktfmtFormat*` tasks, `--include-only` and the
`com.ncorti.ktfmt.gradle.*` imports keep working. Formatting is ktfmt 0.65's; ktfmt-gradle 0.27.0 bundles ktfmt 0.64, so
the first `ktfmtFormat` after the switch is the ktfmt 0.64 to 0.65 diff.

```kotlin
plugins {
    id("io.github.hexay.ktrs") version "0.5.3"   // was: id("com.ncorti.ktfmt.gradle") version "0.27.0"
}
```

### ktlint-gradle

The `io.github.hexay.ktrs.ktlint` plugin replaces [ktlint-gradle](https://github.com/JLLeitschuh/ktlint-gradle) 14.2.0 the
same way: the `ktlint { }` block, `ktlintCheck`/`ktlintFormat` and the per-source-set, baseline and git hook tasks,
`ktlintRuleset(...)` and the `org.jlleitschuh.gradle.ktlint.*` types keep working. Console output, reports and formatted
files match the original with ktlint 1.8.0 ([research/29](../research/29-ktlint-gradle-dropin.md)).

```kotlin
plugins {
    id("io.github.hexay.ktrs.ktlint") version "0.5.3"   // was: id("org.jlleitschuh.gradle.ktlint") version "14.2.0"
}
```

`version` defaults to `"1.8.0"`; `"2.0.0-ALPHA-4"` selects 2.0, and other versions fail the build. compose-rules runs
natively; other rule sets run the task through the real ktlint jar.

### kotlinter

The `io.github.hexay.ktrs.kotlinter` plugin replaces [kotlinter](https://github.com/jeremymailen/kotlinter-gradle) 5.7.0:
the `kotlinter { }` block, `lintKotlin`/`formatKotlin` and the per-source-set tasks, `installKotlinterPrePushHook`,
`ktlint(...)` rule sets and the `org.jmailen.gradle.kotlinter.*` types keep working
([research/34](../research/34-kotlinter-dropin.md)).

```kotlin
plugins {
    id("io.github.hexay.ktrs.kotlinter") version "0.5.3"   // was: id("org.jmailen.kotlinter") version "5.7.0"
}
```

`ktlintVersion` defaults to `"1.8.0"`, as in kotlinter 5.7.0; versions and rule sets work as in the ktlint-gradle drop-in.

### Spotless

`KtrsStep` replaces `ktfmt()` and `KtrsKtlintStep` replaces `ktlint()` (Spotless 7+):

```kotlin
buildscript {
    repositories { mavenCentral() }
    dependencies { classpath("io.github.hexay:ktrs:0.5.3") }
}

spotless {
    kotlin {
        addStep(io.github.hexay.ktrs.spotless.KtrsStep.create(io.github.hexay.ktrs.KtrsOptions.kotlinlang()))
        // or, instead of ktlint("1.8.0").editorConfigOverride(...).customRuleSets(...):
        addStep(io.github.hexay.ktrs.spotless.KtrsKtlintStep.create(io.github.hexay.ktrs.KtlintOptions.defaults()
            .withEditorConfigPath(rootProject.file(".editorconfig"))
            .withEditorConfigOverride(mapOf("ktlint_code_style" to "ktlint_official"))))
    }
}
```

`KtrsKtlintStep` gives the same results as Spotless's `ktlint("1.8.0")` step
([research/28](../research/28-spotless-ktlint-step.md)). `withCustomRuleSets(files)` takes jar files; only compose-rules
is supported there, other rule sets need Spotless's `ktlint()`.

### JVM API and options

The `io.github.hexay:ktrs` jar has no dependencies. It bundles the native binaries for Linux, macOS and Windows (x86-64
and ARM) and keeps long-lived `ktrs serve` processes, so a build starts the binary once, not once per file.

- `KtrsOptions` mirrors ktfmt's options: start from `meta()`, `google()` or `kotlinlang()`, then chain `withMaxWidth`,
  `withBlockIndent`, `withContinuationIndent`, `withRemoveUnusedImports`, `withTrailingCommas` and
  `withEditorConfig(true)`.
- From other JVM code, `Ktrs.create()` returns a thread-safe formatter: `ktrs.format(code, KtrsOptions.google())`, or
  `ktrs.ktlint(code, KtlintOptions.defaults(), path)` for ktlint's formatted code and remaining violations.
- The plugin accepts `useClassloaderIsolation`, `processIsolationJvmArgs` and `ktfmtClasspath` but ignores them.
  `debuggingPrintOpsAfterFormatting` only logs a warning.
- To use a different binary from the bundled one, set the Gradle property `ktrs.executable`.
- Without the jar, Spotless's generic step runs the binary once per file:
  `nativeCmd("ktfmt", "/path/to/ktfmt", listOf("--kotlinlang-style", "-"))`.

## Maven

### ktlint-maven-plugin

`io.github.hexay:ktrs-ktlint-maven-plugin` replaces gantsign's
[ktlint-maven-plugin](https://github.com/gantsign/ktlint-maven-plugin) 3.7.1. Change only the coordinates: the goals (`mvn
ktlint:check`, `ktlint:format`, the `ktlint` site report), parameters, `ktlint.*` properties, `<reporters>` and rule sets
in the plugin's `<dependencies>` keep working, and console output, reports and formatted files match the original
([research/31](../research/31-ktlint-maven-dropin.md)).

```xml
<plugin>
  <groupId>io.github.hexay</groupId>                   <!-- was: com.github.gantsign.maven -->
  <artifactId>ktrs-ktlint-maven-plugin</artifactId>    <!-- was: ktlint-maven-plugin -->
  <version>0.5.3</version>
  <executions><execution><goals><goal>check</goal></goals></execution></executions>
</plugin>
```

`<ktlintVersion>` (property `ktrs.ktlintVersion`) defaults to `1.8.0`; `2.0.0-ALPHA-4` selects 2.0.

### Spotless

Add `implementation=` to the existing `<ktfmt>` or `<ktlint>` element and the jar as a plugin dependency; the other
options stay as they are (Maven 3.9+, Java 17+):

```xml
<plugin>
  <groupId>com.diffplug.spotless</groupId>
  <artifactId>spotless-maven-plugin</artifactId>
  <configuration>
    <kotlin>
      <ktfmt implementation="io.github.hexay.ktrs.spotless.maven.KtrsKtfmt"><style>KOTLINLANG</style></ktfmt>
      <!-- or <ktlint implementation="io.github.hexay.ktrs.spotless.maven.KtrsKtlint">…</ktlint> -->
    </kotlin>
  </configuration>
  <dependencies>
    <dependency><groupId>io.github.hexay</groupId><artifactId>ktrs</artifactId><version>0.5.3</version></dependency>
  </dependencies>
</plugin>
```

Output is that of ktfmt 0.65 and identical to stock `<ktlint>` 1.8.0 (`tools/spotless-maven/parity.sh`). `<version>` must
be left out or match (ktfmt `0.65`; ktlint `1.8.0` or `2.0.0-ALPHA-4`). Stock `<ktfmt>` without a `<version>` runs
Spotless's default, 0.64: the swap then also is the upgrade to 0.65.
