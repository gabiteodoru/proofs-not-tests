/-!
# `categorize`, moved from Python to Lean

Mirrors `categorize` in `../../expenses.py`. Normalization is ASCII-only on
both sides (see `notes/python-lean-contract-gaps.md`).
-/

namespace Toy

/-- Keyword → category; first match wins. Same table as `MERCHANT_RULES` in Python. -/
def merchantRules : List (String × String) :=
  [("cafe", "food"), ("restaurant", "food"), ("airline", "travel"),
   ("taxi", "travel"), ("hotel", "travel"), ("staples", "office")]

/-- Strips space, tab, CR, LF (`Char.isWhitespace`). Python: `s.strip(" \t\r\n")`. -/
def asciiTrim (s : String) : String := s.trimAscii.toString

/-- Category guessed from the merchant name. -/
def guess (merchant : String) : String :=
  let m := merchant.toLower
  match merchantRules.find? (fun r => m.contains r.1) with
  | some r => r.2
  | none => "other"

/-- The declared category (normalized) if there is a non-blank one, else the guess. -/
def chooseCategory (merchant : String) (declared : Option String) : String :=
  match declared with
  | some d => if asciiTrim d = "" then guess merchant else (asciiTrim d).toLower
  | none => guess merchant

/-- The category for one expense row, or an error if it isn't allowed. -/
def categorize (merchant : String) (declared : Option String) (allowed : List String) :
    Except String String :=
  let category := chooseCategory merchant declared
  if category ∈ allowed then .ok category
  else .error s!"category '{category}' is not allowed"

/-- The property we care about: an accepted category is always on the allow-list. -/
theorem categorize_allowed {merchant : String} {declared : Option String}
    {allowed : List String} {c : String}
    (h : categorize merchant declared allowed = .ok c) : c ∈ allowed := by
  unfold categorize at h
  by_cases hm : chooseCategory merchant declared ∈ allowed <;> simp_all

/-- C-callable entry point. Exactly `categorize`; only the list type differs
(an `Array` is easier to build from C).

Ownership: `@[export]` parameters are always owned (Lean FFI reference), so
this function consumes all three arguments. The C caller must NOT `lean_dec`
them after the call; to keep using one, `lean_inc` it before the call.
The returned `Except` is owned by the caller and must be `lean_dec`'d. -/
@[export toy_categorize]
def categorizeFFI (merchant : String) (declared : Option String) (allowed : Array String) :
    Except String String :=
  categorize merchant declared allowed.toList

end Toy
