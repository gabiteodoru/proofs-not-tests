import Lean
open Lean

/-!
# Checks on the challenge that `lake comparator` doesn't do

Prototype. Run with `lake env lean --run CheckChallenge.lean` after `lake build Challenge`.

It loads the compiled challenge as data: no source is parsed while the code's macros
are active, and no initializers run (`loadExts := false`). Names are written with a
single backtick, which makes a literal name that is never resolved, so shadowing
can't change what they mean.
-/

/-- Declarations whose type marks them as new syntax: parsers, macros, elaborators. -/
def syntaxTypes : List Name :=
  [`Lean.ParserDescr, `Lean.TrailingParserDescr, `Lean.Macro,
   `Lean.Elab.Term.TermElab, `Lean.Elab.Command.CommandElab, `Lean.Elab.Tactic.Tactic,
   `Lean.Parser.Parser, `Lean.Parser.TrailingParser]

def report (ok : Bool) (what : String) : IO Bool := do
  IO.println s!"{if ok then "ok    " else "FAILED"} {what}"
  return ok

def main : IO UInt32 := do
  initSearchPath (← findSysroot)
  let env ← importModules #[{ module := `Challenge }] {} (loadExts := false)
  let some idx := env.getModuleIdx? `Toy.Categorize
    | IO.println "FAILED module Toy.Categorize not found"; return 1
  let codeModule := env.header.moduleData[idx.toNat]!

  -- Statement: `Toy.c1` states exactly `Toy.Spec.C1 Toy.categorizeFFI`.
  let expected := mkApp (mkConst `Toy.Spec.C1) (mkConst `Toy.categorizeFFI)
  let stmtOk ← match env.find? `Toy.c1 with
    | some ci => report (ci.type == expected) s!"statement of Toy.c1 is {ci.type}"
    | none => report false "Toy.c1 not found"

  -- Syntax: the code module declares no macros, notation, parsers or elaborators.
  let bad := codeModule.constants.toList.filter fun c =>
    match c.type.getAppFn with
    | .const n _ => syntaxTypes.contains n
    | _ => false
  let syntaxOk ← report bad.isEmpty s!"code declares no syntax {bad.map (·.name)}"

  -- Check 3: `categorizeFFI` is exported to C as `toy_categorize`.
  let exportName := getExportNameFor? env `Toy.categorizeFFI
  let exportOk ← report (exportName == some `toy_categorize) s!"export name is {exportName}"

  -- Check 4: nothing in the code module has its compiled code swapped out.
  let swapped := codeModule.constNames.toList.filter fun n =>
    (Compiler.getImplementedBy? env n).isSome || isExtern env n
  let swapOk ← report swapped.isEmpty s!"no swapped compiled code {swapped}"

  return if stmtOk && syntaxOk && exportOk && swapOk then 0 else 1
