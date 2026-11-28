import Lean
open Lean

/-!
# Human-audited: checks on the challenge that `lake comparator` doesn't do

Run by `audit.sh` (`lake build Challenge`, then
`lake env lean --run ../CheckChallenge.lean` from `lean/`). Why these checks
exist: `notes/audit-integrity.md`, Issues 4 and 5.

It loads the compiled challenge as data: no source is parsed while the code's
macros are active, and no initializers run (`loadExts := false`). It doesn't
load the solution at all. Names are written with a single backtick, which makes
a literal name that is never resolved, so shadowing can't change what they mean.
-/

/-- Each theorem in `Challenge.lean` and the exact statement it must have, built
from literal names. Must list the same theorems as `lean/comparator.json`. -/
def expected : List (Name × Expr) :=
  [(`Toy.c1, mkApp (mkConst `Toy.Spec.C1) (mkConst `Toy.categorizeFFI))]

/-- The module holding the code (not read by hand, so checked mechanically). -/
def codeModule : Name := `Toy.Categorize

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
  let some idx := env.getModuleIdx? codeModule
    | IO.println s!"FAILED module {codeModule} not found"; return 1
  let code := env.header.moduleData[idx.toNat]!

  -- Statements: each theorem states exactly the expected term.
  let mut stmtsOk := true
  for (name, stmt) in expected do
    let ok ← match env.find? name with
      | some ci => report (ci.type == stmt) s!"statement of {name} is {ci.type}"
      | none => report false s!"{name} not found"
    stmtsOk := stmtsOk && ok

  -- Syntax: the code module declares no macros, notation, parsers or elaborators.
  let bad := code.constants.toList.filter fun c =>
    match c.type.getAppFn with
    | .const n _ => syntaxTypes.contains n
    | _ => false
  let syntaxOk ← report bad.isEmpty s!"code declares no syntax {bad.map (·.name)}"

  -- Export: `categorizeFFI` is exported to C as `toy_categorize`, the symbol the shim calls.
  let exportName := getExportNameFor? env `Toy.categorizeFFI
  let exportOk ← report (exportName == some `toy_categorize) s!"export name is {exportName}"

  -- Compiled code: nothing in the code module has its compiled code swapped out.
  let swapped := code.constNames.toList.filter fun n =>
    (Compiler.getImplementedBy? env n).isSome || isExtern env n
  let swapOk ← report swapped.isEmpty s!"no swapped compiled code {swapped}"

  return if stmtsOk && syntaxOk && exportOk && swapOk then 0 else 1
