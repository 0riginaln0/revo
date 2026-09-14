# lang

the revo frontend: text in, bytecode artifact out. the vm lives in
`../vm/`, the stdlib in `../std/`, this dir is everything between

## pipeline

one file per stage, data flows down, never back up:

```ruby
source -> Lexer -> Parser -> expander -> semantic -> compiler -> artifact
```

`pipeline.zig` drives it (`build` is the whole thing)

`pipeline/` holds its companions: `module_scope` (`@exports` wiring)
and `import_preload` (compile-time import extraction)

## files

- `ast.zig`: ast defs, tree walking, and printing
- `Lexer.zig`: tokenizer
- `Parser.zig`: `parseSource`, `parseSourceReport`, token to tree
- `expander.zig`: template macros; `proc.zig` is `proc!` macros
- `semantic.zig`: name and type checking, owns `Failure`
- `compiler/`: lowering to bytecode; `types.zig` is where all the types are at
  plus `evalTypeExpr` and the `CheckCtx` interface every scope implements
- `ir/`: `IrInst` plus the optimization passes
- `type_serde.zig`: text-only type serialization/deserialiization
- `module_iface.zig`: public type surface of a module
- `diagnostic.zig`: reports: parts, spans, severities, render
- `pipeline/`: build orchestration stuff
- `Workspace.zig` + `workspace/`: incremental IDE state (hover, completions, symbols, diagnostics);
  the repl, lsp, and cli all build through it
- `Project.zig`:
  `lib.json` / `exe.json` detection
  (only for now, later itll actually manage build & lsp features and such)
- `docs.zig`: doc extraction and rendering
- `testing.zig`: test helpers; `tests.zig`: the language suite
- `root.zig`: facade for outsiders, re-exports only

## import rules

siblings import each other directly by relative path

nothing inside `lang/` imports `root.zig`
, and nothing reaches back through the `revo` module.
    `root.zig` exists for `repl.zig`, `main.zig`, `vm/`, `std/`, and friends

zig does allow it and its fine, its just cleaner this way

type code takes `types.CheckCtx`, never `anytype`

the four scopes (`Compiler`, `SemanticChecker`, `ModuleCtx`, `BareCtx`)
each have a one-line `check()`;\
    add an interface method and all four fail to build until they implement it

## how to add things

new syntax: `Lexer.zig` (tokens) -> `Parser.zig` (tree) -> `ast.zig`
    (node kinds) -> `expander.zig` if it desugars, `compiler/` if it lowers

new builtin: `../std/iface/*.d.rv` decl plus zig impl (see `../std/`), iface @ `api.zig`
    docs and runtime stay in sync that way

new type behavior: `compiler/types.zig` inference, `type_serde.zig` only if the text spelling changes

new check: `semantic.zig`, errors accumulate as report parts and the single `Failure` carries them out.
error codes are kebab slugs on the report, add one when the message alone is not greppable

new ide feature: `workspace/`, one file per provider. `Workspace`
re-exports each provider as a member alias so call sites keep method
syntax while implementations stay in focused files

## tests

unit tests go inline next to the code
end-to-end coverage lives in `tests.zig` via the `testing.zig` helpers
