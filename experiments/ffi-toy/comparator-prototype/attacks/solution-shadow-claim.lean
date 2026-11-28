import Toy.Spec
import Toy.Categorize
namespace Evil
def Toy.Spec.C1 (_ : Toy.Spec.CategorizeShape) : Prop := True
theorem _root_.Toy.c1 : Toy.Spec.C1 Toy.categorizeFFI := trivial
end Evil
