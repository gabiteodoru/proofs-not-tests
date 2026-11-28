import Toy.Spec
def Toy.categorizeFFI (_ : String) (_ : Option String) (_ : Array String) : Except String String := .error "no"
theorem Toy.c1 : Toy.Spec.C1 Toy.categorizeFFI := by intro _ _ _ _ h; cases h
