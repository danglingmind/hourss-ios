# Hourss — working notes

## Simulator

Always use **iPhone 17 Pro**, and always by UDID:

```
-destination 'platform=iOS Simulator,id=53352C15-35FE-4B6F-BAA9-AEF24E34281D'
```

Two reasons, both learned the hard way:

- **The Apple account is signed in on that device only.** iPhone 17 (plain) and
  iPhone 17 Pro Max are not signed in, so onboarding's account gate cannot be
  passed on them and any run that reaches beat 7 stalls there.
- **Never use `name=`.** xcodebuild resolves a name against whatever is booted on
  a prefix match, so `name=iPhone 17` silently resolves to *iPhone 17 Pro*. Two
  concurrent runs then land on one device and SIGKILL each other's test host,
  producing dozens of "Test crashed with signal kill" failures that look real and
  are not.

Concurrent runs need genuinely different UDIDs — iPhone 17 Pro Max
(`CFDD0622-31CC-480A-BFFC-4BEA889177B2`) is the second device, with the caveat
about the account above.

## Test suites

Baseline is **378 unit tests** and **32 UI tests**, all passing. The unit suite
takes about 100 seconds; if it takes materially longer, something has been added
that runs the engine at high resample counts — that has happened once and took
the suite to forty minutes.

## Diagnostics

SourceKit diagnostics in this project are unreliable — "Cannot find 'Space' in
scope" and similar appear constantly for types that plainly exist. Trust
`xcodebuild`, never the editor diagnostics.
