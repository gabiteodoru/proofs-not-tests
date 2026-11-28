/-!
# Human-audited: the spec of `categorize`, in Lean

A line-by-line translation of `../../SPEC.md` ("Definitions", "Behaviour",
"Claims to prove in Lean"). Each definition names the part of SPEC.md it
translates. This file imports nothing from the implementation or the proofs, so it
depends only on Lean's core library.

DRAFT, Nov 27, 2026: written for the user's audit. Connected to the implementation by
`../Challenge.lean`, which states C1 about `categorizeFFI` (C2–C4 not yet).
-/

namespace Toy.Spec

/-! ## Definitions (SPEC.md, "Definitions") -/

-- A Lean `String` is a finite sequence of `Char`s; `s.toList` is that
-- sequence as a list. A `Char` is a Unicode code point other than a
-- surrogate; `c.toNat` is its code point. `=` on strings is exact.

/-- Substring: `t` occurs in `s` as a contiguous block. -/
def IsSubstring (t s : String) : Prop :=
  ∃ pre post : List Char, s.toList = pre ++ t.toList ++ post

/-- Printable ASCII character: code point from 0x20 to 0x7e inclusive. -/
def IsPrintableAsciiChar (c : Char) : Prop :=
  0x20 ≤ c.toNat ∧ c.toNat ≤ 0x7e

/-- Printable ASCII string: every character is printable ASCII. -/
def IsPrintableAscii (s : String) : Prop :=
  ∀ c ∈ s.toList, IsPrintableAsciiChar c

/-- One character of `Lower`: `A`–`Z` (0x41–0x5a) to `a`–`z` (code point + 0x20). -/
def lowerChar (c : Char) : Char :=
  if 0x41 ≤ c.toNat ∧ c.toNat ≤ 0x5a then Char.ofNat (c.toNat + 0x20) else c

/-- Lower(s): `lowerChar` applied to each character. -/
def lower (s : String) : String :=
  String.ofList (s.toList.map lowerChar)

/-- Drops the longest prefix consisting only of spaces (0x20). -/
def dropLeadingSpaces (l : List Char) : List Char :=
  l.dropWhile (· = ' ')

/-- Trim(s): drop the leading spaces, then the trailing ones (by reversing,
dropping leading spaces, and reversing back). -/
def trim (s : String) : String :=
  String.ofList (dropLeadingSpaces (dropLeadingSpaces s.toList).reverse).reverse

/-- Normalize(s) = Lower(Trim(s)). -/
def normalize (s : String) : String :=
  lower (trim s)

/-- Canonical: `Normalize(s) = s`. The empty string is canonical. -/
def IsCanonical (s : String) : Prop :=
  normalize s = s

/-- The merchant rules: (keyword, category) pairs, in order. -/
def merchantRules : List (String × String) :=
  [("cafe", "food"), ("restaurant", "food"), ("airline", "travel"),
   ("taxi", "travel"), ("hotel", "travel"), ("staples", "office")]

-- Lets `guess` test `IsSubstring` while running. Not part of the spec's
-- meaning: Lean checks that this test agrees with `IsSubstring` exactly.
instance (t s : String) : Decidable (IsSubstring t s) :=
  decidable_of_iff (t.toList <:+: s.toList)
    ⟨fun ⟨pre, post, h⟩ => ⟨pre, post, h.symm⟩, fun ⟨pre, post, h⟩ => ⟨pre, post, h.symm⟩⟩

/-- Guess(m): the category of the first rule whose keyword is a substring of
`Lower(m)`, or `"other"` if there is none. -/
def guess (m : String) : String :=
  match merchantRules.find? (fun rule => decide (IsSubstring rule.1 (lower m))) with
  | some rule => rule.2
  | none => "other"

/-! ## The function and its outcome (SPEC.md, "The function") -/

/-- The shape of `categorizeFFI`: merchant, declared (absent = `none`),
allow-list; the outcome is `.ok c` (accept `c`) or `.error message` (reject). -/
abbrev CategorizeShape := String → Option String → Array String → Except String String

/-- The outcome is reject, with some message. -/
def IsReject (r : Except String String) : Prop :=
  ∃ message, r = .error message

/-! ## Behaviour (SPEC.md, "Behaviour") -/

/-- Valid arguments: V1, V2, V3. (The type parts of V2 and V3, "a string",
"a list", "absent", hold by the types; Python checks them. SPEC.md, "Boundary".) -/
def Valid (merchant : String) (declared : Option String) (allowed : Array String) : Prop :=
  IsPrintableAscii merchant ∧                                    -- V1
  (∀ d, declared = some d → IsPrintableAscii d) ∧                -- V2
  (∀ e ∈ allowed, e ≠ "" ∧ IsPrintableAscii e ∧ IsCanonical e)   -- V3

/-! ## Claims (SPEC.md, "Claims to prove in Lean"), for any `f` of the right shape -/

/-- C1, safety: an accepted category is an element of `allowed`. -/
def C1 (f : CategorizeShape) : Prop :=
  ∀ merchant declared allowed c,
    f merchant declared allowed = .ok c → c ∈ allowed

/-- C2, invalid input is rejected. -/
def C2 (f : CategorizeShape) : Prop :=
  ∀ merchant declared allowed,
    ¬ Valid merchant declared allowed → IsReject (f merchant declared allowed)

/-- C3, a declared category decides: if `Normalize(d)` is non-empty, accept it
if it is in `allowed`, else reject. -/
def C3 (f : CategorizeShape) : Prop :=
  ∀ merchant d allowed,
    Valid merchant (some d) allowed → normalize d ≠ "" →
      (normalize d ∈ allowed → f merchant (some d) allowed = .ok (normalize d)) ∧
      (normalize d ∉ allowed → IsReject (f merchant (some d) allowed))

/-- C4, otherwise the guess decides: if `declared` is absent or normalizes to
the empty string, accept `Guess(merchant)` if it is in `allowed`, else reject. -/
def C4 (f : CategorizeShape) : Prop :=
  ∀ merchant declared allowed,
    Valid merchant declared allowed →
    (declared = none ∨ ∃ d, declared = some d ∧ normalize d = "") →
      (guess merchant ∈ allowed → f merchant declared allowed = .ok (guess merchant)) ∧
      (guess merchant ∉ allowed → IsReject (f merchant declared allowed))

/-! ## Sanity checks of the definitions

Each `#guard` evaluates its expression when the file is built, and fails the
build if it is false. They are examples, not proofs: they help a reader check
that the definitions mean what SPEC.md says. -/

#guard lower "Blue CAFE 9!" = "blue cafe 9!"
#guard lower "É" = "É"                       -- only A–Z change
#guard trim "  food  " = "food"
#guard trim " a b " = "a b"                  -- inner spaces stay
#guard trim "\tfood" = "\tfood"              -- only spaces are trimmed
#guard trim "   " = ""
#guard normalize "  FOOD " = "food"
#guard guess "Blue Cafe" = "food"
#guard guess "Airline Cafe" = "food"         -- rule order decides, not position in the name:
                                             -- cafe (rule 1) beats airline (rule 3)
#guard guess "Bookshop" = "other"
#guard guess "" = "other"
#guard decide (IsSubstring "" "abc")
#guard decide (IsSubstring "abc" "abc")
#guard !decide (IsSubstring "ac" "abc")      -- contiguous only

end Toy.Spec
