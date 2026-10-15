# JVBench – fork for JDK 27 and Armv9-A

This is a fork of [JVBench](https://github.com/usi-dag/JVBench). It was created for the bachelor thesis *"Performance Analysis of the Java Vector API on Armv9-A Architectures – An Extension of x86-64-Based Studies"* by **Fynn Moritz**.

The goal of the fork is to run the original suite unchanged on current JDKs and on Arm hardware, and to automate running and evaluating the benchmarks.

The [original README](#original-jvbench-readme) follows below this section and still applies, including the list of benchmarks and their default inputs.

## What this fork changes

**The benchmark code is unchanged.** All changes concern the build and the tooling around it.

### Build (`pom.xml`)

- `maven-compiler-plugin` updated from 3.1 to 3.13.0.
- The JMH annotation processor (`jmh-generator-annprocess`) is now configured explicitly via `annotationProcessorPaths`.

**Why:** Newer `javac` versions no longer run annotation processors that are only found on the class path. With the original configuration the build succeeds on recent JDKs, but JMH's `META-INF/BenchmarkList` is not generated and every run fails with `Unable to find the resource: /META-INF/BenchmarkList`. The explicit configuration works on both JDK 19 and JDK 27. `annotationProcessorPaths` is not supported by the old compiler plugin, hence the version update.

The JMH version (1.35) is intentionally left unchanged to keep results comparable with the original study.

### Added tooling

| File | Purpose |
|---|---|
| `run_all.sh` | Runs all selected benchmarks for one or more JDKs, one JSON and one log file per benchmark method, plus a metadata file per run |
| `compare.sh` | Extracts the results of two JDKs from the logs, shows absolute times side by side and computes speedups relative to `serial` |
| `tools/SpeciesInfo.java` | Prints `SPECIES_MAX` and `SPECIES_PREFERRED` for float, double and int vectors |

## Requirements

- JDK 19 and/or JDK 27 (the original suite targets JDK 16 or above; this fork has only been tested with 19 and 27)
- Maven 3.8 or newer
- Bash: any Linux shell, or Git Bash on Windows

## Building

The JAR is compiled against the Vector API of the JDK used for the build. Since the incubator API changes between releases, **build one JAR per JDK** and run each JAR with the JDK it was built with.

```bash
# with JAVA_HOME and PATH pointing to JDK 27
mvn clean package
mkdir -p jars
cp target/JVBench-2.0.0.jar jars/JVBench-jdk27.jar

# with JAVA_HOME and PATH pointing to JDK 19
mvn clean package
cp target/JVBench-2.0.0.jar jars/JVBench-jdk19.jar
```

## Running the benchmarks

All scripts are started from the repository root. Parameters are passed as environment variables.

```bash
DRYRUN=1 bash run_all.sh                            # list the benchmarks that would run
bash run_all.sh                                     # short smoke test (1 fork, 1 warmup, 2 measurements)
MODE=full bash run_all.sh                           # configuration from the annotations (5 forks, 10 warmup, 10 measurements)
MODE=full FILTER=Axpy JDKS=jdk27 bash run_all.sh    # only Axpy, only JDK27
```

| Variable | Default | Meaning |
|---|---|---|
| `MODE` | `short` | `short` for smoke tests, `full` for the configuration from the annotations |
| `JDKS` | `jdk27 jdk19` | JDKs to run, in this order |
| `JDK19_HOME`, `JDK27_HOME` | Windows default paths | Installation directories of the JDKs |
| `FILTER` | empty | Regex restricting the benchmark names |
| `VARIANTS` | `serial`, `autoVec`, `explicitVec`, `fullVec`, `indexInRange` | Regex on the method suffix; `.*` selects all methods |
| `DRYRUN` | `0` | `1` only lists the selected benchmarks |
| `JAR_DIR` | `jars` | Directory containing `JVBench-<jdk>.jar` |
| `RESULT_ROOT` | `results` | Output directory |
| `MACHINE` | host name | Subdirectory name for this machine |

Existing result files are skipped, so an interrupted run can simply be restarted. Failed benchmarks are listed in `failed.txt`.

**Note:** Results from `MODE=short` are only meant to verify that everything runs. Use `MODE=full` for measurements. Depending on your choosen hardware and JDK, `MODE=full` can take several hours to complete.

### Output layout

```
results/<machine>/<mode>/<jdk>/
    _metadata_<timestamp>.txt    # date, java -version, JAR checksum, git commit, CPU, vector sizes
    <benchmark>.json             # JMH raw data
    <benchmark>.log              # JMH console output
```

## Comparing results

```bash
bash compare.sh                                # full run, jdk19 vs. jdk27
MACHINE=<machine> MODE=short bash compare.sh   # required if results of several machines exist
```

The output contains two tables:

1. absolute times of both JDKs and their ratio (`< 1` means the second JDK is faster),
2. speedups of every variant relative to `serial` of the same JDK. `indexInRange` methods of the `*PatternBenchmark` classes are related to `serial` of the corresponding standard benchmark, matching the presentation in the original paper.

The table is also written to `results/<machine>/<mode>/comparison_<jdkA>_<jdkB>.txt`.

## Benchmark variants

| Method | Code | JVM flag |
|---|---|---|
| `serial` | scalar | `-XX:-UseSuperWord` (auto-vectorization off) |
| `autoVec` | scalar | default (auto-vectorization on) |
| `explicitVec` | Vector API, `loopBound` | `-XX:-UseSuperWord` |
| `fullVec` | Vector API, `loopBound` | default |
| `indexInRange` (`*PatternBenchmark`) | Vector API, masked tail via `indexInRange` | default |

---

## Original JVBench README

*The following section is the unmodified README of the original project.*

## JVBench Benchmark Suite

JVBench is a collection of diverse benchmarks
that exercise the [Java Vector API](https://openjdk.org/jeps/426) on typical SIMD workloads.

This benchmark suite includes a version of the workloads of the 
[RIVEC](https://github.com/RALC88/riscv-vectorized-benchmark-suite) suite after
recasting them in Java and expressing vector operations with the Java Vector API.


### List of benchmarks

The following table is a complete list of benchmarks included in JVBench in alphabetical order:

| Application Name | Application Domain         | Algorithmic Model    | Taken From |
|------------------|----------------------------|----------------------|------------|
| Axpy             | High Performance Computing | BLAS                 | RIVEC      |
| Blackscholes     | Financial Analysis         | Dense Linear Algebra | PARSEC     |
| Canneal          | Engineering                | Unstructured Grids   | PARSEC     |
| Jacobi-2D        | Engineering                | Dense Linear Algebra | PolyBench  |
| LavaMD           | Molecular Dynamics         | N-Body               | Rodinia    |
| Particlefilter   | Medical Imaging            | Structured Grids     | Rodinia    |
| Pathfinder       | Grid Traversal             | Dynamic Programming  | Rodinia    |
| Somier           | Physics Simulation         | Dense Linear Algebra | RIVEC      |
| Streamcluster    | Data Mining                | Dense Linear Algebra | PARSEC     |
| Swaptions        | Financial Analysis         | MapReduce Regular    | PARSEC     |


### Prerequisites
- [OpenJDK HotSpot JDK 16](https://github.com/openjdk/jdk16/) or above


### Obtaining the suite
To run the suite, you can download the suite JAR [here](https://github.com/usi-dag/JVBench/releases).
Alternatively, you can build it yourself. To do so, you will need [Maven](https://maven.apache.org/) version 3.8 or above. 
To build an executable JAR, use the following command:

```shell
$ mvn clean package
```


### Running the suite
To run a JVBench benchmark, execute the following java command:

```shell
$ java --add-modules jdk.incubator.vector -jar JVBench-1.0.1.jar "<benchmarks>"
```

where <benchmarks> is the benchmark name that you wish to run. Please append the word "Benchmark" to the benchmark name. For example, to run benchmark Axpy, specify `AxpyBenchmark` as the benchmark.

By default, the suite executes each benchmark operation for a specific number of times.
For thorough experimental evaluation, the benchmarks should be repeated for a large number of times or executed for a long time. 
The number of repetitions and the execution time can be set for all benchmarks using the -f, -wi, and -i options.
For a complete description, please refer to [JHM tutorial](https://github.com/guozheng/jmh-tutorial/blob/master/README.md)

Moreover, it is possible to override the default benchmark input with the following command:

```shell
$ java --add-modules jdk.incubator.vector <inputs> -jar JVBench-1.0.1.jar "<benchmarks>"
```

For example, to specify an input size of 70k elements to Axpy, you can run the following command:

```shell
$ java --add-modules jdk.incubator.vector -Dsize=70000 -jar JVBench-1.0.1.jar "AxpyBenchmark"
```

The default input (expressed as different system properties) for each benchmark is listed in the table below:

| Application Name | Default Input                                                                                                                         |
|------------------|---------------------------------------------------------------------------------------------------------------------------------------|
| Axpy             | -Dsize=70000                                                                                                                          |
| Blackscholes     | -Dinput=/blackscholes/input/in_512K.input                                                                         |
| Canneal          | -Dnswaps=10000 -DTEMP=2000 -Dnetlist=canneal/input/2500000.nets -Dnsteps=300                                     |
| Jacobi-2D        | -Dsize=10000 -Dtsteps=14                                                                                                              |
| LavaMD           | -Dinput=/lavaMD/input/lavaMD_127776.input                                                                           |
| Particlefilter   | -Dx=128 -Dy=128 -Dz=24 -Dnp=32768                                                                                                     |
| Pathfinder       | -Dinput=/pathfinder/input/pathfinder_5000_5000.input                                                                |
| Somier           | -Dsteps=10 -Dn=128                                                                                                                    |
| Streamcluster    | -Dk1=3 -Dk2=10 -Ddim=128 -Dchunksize=128 -Dclustersize=10 -Dinput=/streamcluster/input/streamcluster_128_128.input |
| Swaptions        | -Dms=64 -Dns=16384                                                                                                                    |


### 🤝 Contributing
You are welcome to contribute to this open-source benchmark suite. If you want to add or modify
the code, feel free to fork the repo, create issues and finally a pull request to review your code!
