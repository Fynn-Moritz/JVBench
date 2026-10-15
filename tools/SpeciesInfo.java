import jdk.incubator.vector.*;

/**
 * Prints the vector sizes of the Vector API on the current machine.
 * Run without compiling (single-file source launcher):
 *   java --add-modules jdk.incubator.vector tools/SpeciesInfo.java
 */
public class SpeciesInfo {

    public static void main(String[] args) {
        System.out.println("Preferred shape: " + VectorShape.preferredShape());
        print("Float",  FloatVector.SPECIES_MAX,  FloatVector.SPECIES_PREFERRED);
        print("Double", DoubleVector.SPECIES_MAX, DoubleVector.SPECIES_PREFERRED);
        print("Int",    IntVector.SPECIES_MAX,    IntVector.SPECIES_PREFERRED);
    }

    private static void print(String name, VectorSpecies<?> max, VectorSpecies<?> pref) {
        System.out.printf("%-6s MAX: %4d bit, %3d lanes | PREFERRED: %4d bit, %3d lanes%s%n",
                name,
                max.vectorBitSize(), max.length(),
                pref.vectorBitSize(), pref.length(),
                max.vectorBitSize() != pref.vectorBitSize() ? "   <-- different" : "");
    }
}
