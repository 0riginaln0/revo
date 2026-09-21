```text
zig build lib        # builds liberevo.a + revo.h into zig-out/
zig build test-c     # c api tests + c++ compat smoke (needs the lib first)
```

for C developers, see `tests.c` (idiomatic `const char*, len` form;
`revo.h` also ships `*_cstr` helpers that strlen internally).
generated decls carry `REVO_API`; `REVO_VERSION` matches `build.zig`.
