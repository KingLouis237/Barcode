# Reproducible Playbook for Bacterial Genome Assembly from ONT Barcode07 Reads

_Last updated: 7 March 2026_

## Background
- **Problem**: Convert Nanopore raw signal demultiplexed as `barcode07` into an interpretable bacterial genome plus QC evidence. Raw FASTQ reads (~10 kb average length) are not yet an assembled genome; they require error correction, layout, polishing, and validation before biological interpretation.
- **What does a barcode mean?** ONT ligation kits tag each library with unique adapter sequences; Guppy then demultiplexes reads. `barcode07` refers to the seventh barcode in the ONT EXP-NBD104/114 set and represents a single bacterial isolate within a multiplexed run. Selecting this barcode isolates one sample without cross-talk from other isolates.
- **Why bacterial genome assembly?** Bacterial genomes are typically 3–6 Mb and often circular. Long-read assembly can resolve repeats and plasmids, but tooling/parameters strongly influence contiguity and accuracy, so documenting the process is essential for trust.
- **Why multiple assemblers + evaluation tools?** Different assemblers make different trade-offs (speed vs accuracy, repeat handling, read filtering). Running Flye, Raven, and Shasta side-by-side, then validating with QUAST, KAT, BUSCO, Bandage, and 16S analyses exposes strengths, weaknesses, and gives readers intuition about comparing pipelines.

> **Canonical vs archival sources**
> - This Markdown playbook is the **only maintained source of truth** for the BARCODE workflow. All new edits happen here.
- `BARCODE_project/WORKFLOW.html` is retained solely as a historical/raw log. It preserves the original commands verbatim and outputs of the pipeline but now carries a banner deferring to this document.
- `BARCODE_project/barcode_carousel.pdf` houses the supporting figures (screenshots, graphs) for every stage. Visual callouts below reference specific slide pages of `barcode_carousel.pdf` so readers can cross-check the same artifact.

## How to Use This Playbook
1. **Core Flow First** – Each step begins with a concise summary (goal, inputs, canonical command, expected files).
2. **Layered Deep Dives** – Callouts titled *Command Breakdown*, *Why These Flags Matter*, *Troubleshooting*, *Alternatives / Variants*, and *First-Principles Intuition* expand on flags, reasoning, and diagnostics.
3. **Reproducibility Labels** – Every step carries a badge so you know what can be rerun as-is.
   - 🟢 **Fully Reproducible (FR)**: All inputs, commands, and outputs are in `BARCODE_project` or generated deterministically.
   - 🟡 **Conditionally Reproducible (CR)**: Requires large downloads, internet access, or cloud quotas but still scripted.
   - 🟠 **Manual / External (ME)**: Relies on GUI/web tools; we provide artifacts plus instructions to redo manually.
4. **Scientific Sanity Checks** – Instead of quizzes, checkpoints show what success/failure looks like so you can reason about deviations.

> **First-Principles Orientation**
> - Think of the workflow as a data transformation pipeline: compressed raw FASTQ → decompressed FASTQ with QC → assemblies → evaluation (QUAST/KAT/BUSCO/graphs) → biological interpretation (16S phylogeny, BlastKOALA, visual storytelling).
> - Each command either validates an assumption about the data, transforms sequences into a new representation, or contextualizes biological meaning. When a command fails, map the failure to that layer (data availability, algorithmic parameter, or interpretation) to reason about fixes.

## Repository Layout & Data Availability
- Unless otherwise noted, commands assume your working directory is `BARCODE_project`.
- **Raw reads live in `raw/`.** The repository ships `raw/barcode07.fq.gz`. Run `gzip -dk raw/barcode07.fq.gz` once so `raw/barcode07.fq` exists for all commands. Bring your own FASTQ only if you want to assemble another barcode.
- **Heavy intermediates remain local.** Directories such as `assemblies/*`, `logs/*`, and `eval/16s/*` are omitted to keep the repo lightweight; regenerate them by rerunning the documented commands when you need the original logs.
- **Flattened assemblies are included.** Each assembler’s final FASTA is copied into `Assembly/` (e.g., `Assembly/flye.fasta`) for quick comparisons; these mirror what rerunning the tools would produce under `assemblies/`.
- 16S deliverables live in `16S anno_phylo/`. When the playbook references `eval/16s/*`, read it as “regenerate under `eval/16s`, or cross-check the committed files in `16S anno_phylo/`.”
- Bandage PNGs (`Bandage Graphs/*.png`), BUSCO/QUAST/KAT outputs, BlastKOALA screenshots, and the supporting figure deck `barcode_carousel.pdf` are committed exactly as referenced.
- Paths highlighted as missing during validation are documented in the **Local Validation – 7 Mar 2026** section at the end of this file.
- `BARCODE_project/WORKFLOW.html` remains available if you need to see the original unedited command transcript; treat it as archival/raw data only.

> **Raw input prep (run once per new clone)**
> ```bash
> gzip -dk raw/barcode07.fq.gz   # keep .gz and create raw/barcode07.fq
> ls -lh raw/barcode07.fq        # confirm the ~390 Mb FASTQ exists
> ```
> After this, all downstream steps can reference `raw/barcode07.fq` directly.

## Workflow Overview
| Stage | Reproducibility | Key Outputs |
| --- | --- | --- |
| Environment Preparation | 🟢 | `envs/*.yml` | 
| Raw Read QC | 🟢 | `raw/seqkit_stats.txt` (documented in workflow) |
| Assemblies (Flye, Raven, Shasta) | 🟢 | `Assembly/*.fasta`, `assemblies/*` | 
| QUAST Evaluation | 🟢 | `quast_results/*` |
| KAT k-mer Comparisons | 🟢 | `KAT analysis/*` |
| BUSCO Completeness | 🟢 | `Busco Analysis/*` |
| Bandage Graphs | 🟡 | `Bandage Graphs/*.png` |
| 16S Extraction + Phylogeny | 🟢 | `16S anno_phylo/*` |
| BlastKOALA Functional Annotation | 🟠 | `BlastKoala/Screenshot*.png` |
| Barcode Carousel Summary Deck | 🟠 | `barcode_carousel.pdf` |

---

## Step 0. Environment Preparation 🟢
**Goal**: Install the exact toolchains needed for assembly, evaluation, and phylogenetics using modular Conda environments (containers deferred until a future phase).

**Inputs**: `envs/assembly.yml`, `envs/quast.yml`, `envs/kat.yml`, `envs/busco.yml`, and `envs/phylo.yml`.

**Core Commands**
```bash
# Example: create the Flye/Raven/Shasta environment
conda env create -f envs/assembly.yml
conda activate barcode-assembly
flye --version

# Repeat for remaining envs (conda does not accept globs)
for yaml in envs/quast.yml envs/kat.yml envs/busco.yml envs/phylo.yml; do
  conda env create -f "${yaml}"
done
```

> **Command Breakdown**
> - `conda env create -f envs/assembly.yml`: reads the YAML to install Flye, Raven, Shasta, SeqKit, and Minimap2 into a clean prefix named after the `name:` entry.
> - `conda activate barcode-assembly`: switches PATH/LD_LIBRARY_PATH so the just-created tools are resolved; creation and activation are separate operations.
> - `flye --version`: quick smoke test that activation worked.
> - `for yaml in ...; do conda env create -f "$yaml"; done`: iterates explicitly because `conda env create -f envs/*.yml` tries to parse the literal glob list as extra arguments.
>
> **Why These Flags Matter**
> - `-f envs/<tool>.yml` pins dependency sets; removing it risks solver drift and irreproducible assemblies.
> - Activation must follow creation so shell sessions pick up the correct `PATH`. Running commands without `conda activate` often executes system binaries instead.
>
> **Troubleshooting**
> - `LibMambaUnsatisfiableError`: try `conda env create --solver classic ...` or fall back to `micromamba create -f ...`.
> - Missing packages from Bioconda: ensure `channels:` inside each YAML lists `conda-forge` and `bioconda` in that order.
> - Large BUSCO downloads timing out: create `envs/busco.yml` separately, then `conda rename tmp barcode-busco`.
> - Need GUI Bandage? Install system-wide separately; this repo relies on pre-rendered PNGs.
>
> **Alternatives / Variants**
> - Micromamba (`micromamba create -f envs/assembly.yml`) is faster and avoids base Conda activation.
> - One-off installs: if you already have a shared env, use `conda install -n bio flye=2.9.6 ...` but capture the package list in a lock file.
>
> **First-Principles Intuition**
> - Reproducibility hinges on freezing toolchains. Environments are miniature sandboxes replicating the 2026 experiment state; if they fail to create, you cannot trust downstream QC differences.
> - The loop enforces deterministic ordering, so each evaluation stack mirrors the proven workflow.

---

## Step 1. Raw Read Quality Control (SeqKit) 🟢
**Goal**: Verify barcode07 read yield, length distribution, and per-base quality before assembly.

**Inputs**: `raw/barcode07.fq` (ONT basecalled FASTQ) generated locally from the committed `raw/barcode07.fq.gz`.

> **Prep**
> ```bash
> gzip -dk raw/barcode07.fq.gz   # creates raw/barcode07.fq if it does not already exist
> ```
> **Command Breakdown**
> - `gzip -dk`: `-d` decompresses, `-k` keeps the `.gz` so you can re-run without redownloading.
> - Output path automatically mirrors the input (`raw/barcode07.fq.gz` → `raw/barcode07.fq`).
>
> **Why These Flags Matter**
> - Keeping the `.gz` prevents accidental data loss if you need to verify checksums later.
> - Explicit paths avoid decompressing into `$PWD`, which would scatter data across the repo.
>
> **Troubleshooting**
> - `No such file or directory`: confirm you are inside `BARCODE_project/`.
> - File still ends with `.gz`: you may be on macOS/BSD `gzip` without `-k`; use `gunzip -c raw/barcode07.fq.gz > raw/barcode07.fq`.
>
> **Alternatives / Variants**
> - `pigz -dk` leverages multi-core decompression for very large runs.
> - If storage is tight, skip `-k` but note you cannot regenerate the compressed version from lossy FASTQ.
>
> **First-Principles Intuition**
> - Assemblers expect plain FASTQ streams; decompression transforms archival storage into analysis-ready signals while preserving provenance via the original `.gz`.

**Core Command**
```bash
conda activate barcode-assembly
seqkit stats -a raw/barcode07.fq > raw/seqkit_stats.txt
```

**Expected Output Snapshot**
```
num_seqs = 37,054
sum_len  = 392,624,046 bp (~392.6 Mb)
avg_len  = 10,596 bp
N50      = 24,577 bp
Q20(%)   = 83.98
Q30(%)   = 57.02
GC(%)    = 41.29
```

> **Command Breakdown**
> - `conda activate barcode-assembly`: ensures SeqKit resolves to the pinned version.
> - `seqkit stats`: streams the FASTQ once and reports counts, lengths, GC, and quality.
> - `-a`: augments the report with quartiles and Q20/Q30 percentages.
> - `> raw/seqkit_stats.txt`: captures the table for reproducibility.
>
> **Why These Flags Matter**
> - `-a` surfaces depth of coverage and length distribution so you can sanity-check assembler assumptions without plotting.
> - Redirecting to `raw/seqkit_stats.txt` keeps the raw QC result alongside the input.
>
> **Troubleshooting**
> - Empty output: confirm `raw/barcode07.fq` exists and is not zero bytes (`ls -lh`).
> - `seqkit: command not found`: re-run `conda activate barcode-assembly`.
> - Unicode/locale warnings: prepend `LC_ALL=C` to avoid localized parsing.
>
> **Alternatives / Variants**
> - `nanoplot --fastq raw/barcode07.fq` generates richer plots but requires more dependencies.
> - `seqkit stats raw/barcode07.fq.gz` also works if you prefer streaming compressed input, but decompressing simplifies downstream steps.
>
> **First-Principles Intuition**
> - QC quantifies whether the read set can theoretically span the genome (coverage = total bases / genome size) and whether quality supports high-fidelity assembly.
> - Deviations (low coverage, odd GC) hint at biological contamination or technical demultiplexing issues that assemblies cannot fix later.
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 2 (“Raw QC & Coverage”) summarizes the SeqKit table and read-length violin plots that correspond to this step.

---

## Step 2. Assemblies 🟢
We run three assemblers to illustrate different design philosophies. All raw outputs live in `Assembly/` (flattened copies) or original subfolders referenced in `WORKFLOW.html`.

> **Result digest (from `Assembly/*.fasta` and `WORKFLOW.html`)**
> - **Flye:** 2 contigs, total length 3,780,699 bp, N50 3,773,355 bp, dominant circular chromosome plus one small contig.
> - **Raven:** 28 contigs spanning 6,402,553 bp, same N50 as Flye but inflated span/GC (46.73%) because duplicated regions stay split.
> - **Shasta:** 13 contigs, 3,155,007 bp total, N50 437,312 bp due to aggressive read filtering and lower coverage.

### 2A. Flye 🟢
**Goal**: Produce a highly contiguous assembly optimized for long reads.

**Inputs**: `raw/barcode07.fq`, environment `barcode-assembly`.

**Core Command**
```bash
flye --nano-hq raw/barcode07.fq --out-dir assemblies/flye --threads $(nproc)
```

**Expected Outputs**: `assemblies/flye/assembly.fasta` plus logs. The repo includes the flattened copy `Assembly/flye.fasta` for inspection if you cannot rerun Flye immediately.

> **Command Breakdown**
> - `--nano-hq raw/barcode07.fq`: treats reads as super-accuracy ONT, enabling Flye’s fast polishing model.
> - `--out-dir assemblies/flye`: captures Flye’s multi-stage intermediates for auditing.
> - `--threads $(nproc)`: matches logical CPUs for fastest consensus.
>
> **Why These Flags Matter**
> - Choosing `--nano-hq` instead of `--nano-raw` assumes Guppy/Dorado “super” models; using the wrong preset over/under-corrects errors.
> - Explicit `--out-dir` keeps assemblies from overwriting previous runs and simplifies gitignore rules.
>
> **Troubleshooting**
> - RAM error or crash: lower `--threads` or run with `--asm-coverage 60` to subsample.
> - Extra contigs: inspect `assembly_info.txt` for low-coverage scaffolds; possible contamination or unresolved repeats.
> - Log mentions “not enough coverage”: confirm Step 1 coverage >30×; otherwise consider `filtlong` to enrich high-quality reads.
>
> **Alternatives / Variants**
> - `--nano-raw` if using legacy fast models; `--meta` for metagenomes; or wrap Flye inside Trycycler for consensus assemblies.
> - Add `--polish-target contigs` to focus on a subset when iterating quickly.
>
> **First-Principles Intuition**
> - Flye builds a repeat graph and resolves long paths; with two contigs you expect one chromosome plus minor plasmid/residual fragment. Deviations mean the read set violates graph assumptions (e.g., mixed strains).

### 2B. Raven 🟢
**Core Command**
```bash
raven --threads $(nproc) \
  --graph assemblies/raven/raven.gfa \
  raw/barcode07.fq > assemblies/raven/raven.fasta 2> logs/raven.log
```
**Expected**: 28 contigs totaling 6.40 Mb, largest 3.77 Mb. The committed `Assembly/raven.fasta` mirrors the canonical `assemblies/raven/raven.fasta`.

> **Command Breakdown**
> - `--threads $(nproc)`: multithreaded layout/alignment.
> - `--graph assemblies/raven/raven.gfa`: emits the assembly graph alongside contigs.
> - `raw/barcode07.fq > assemblies/raven/raven.fasta`: streams FASTQ in, writes contigs to FASTA, and logs stderr.
> - `2> logs/raven.log`: keeps warnings (e.g., chimeric read notices) for debugging.
>
> **Why These Flags Matter**
> - Saving the `.gfa` enables Bandage inspection; without it you lose graph-level insight.
> - Redirecting stdout/stderr separates contig output from diagnostic text, preventing corrupt FASTA headers.
>
> **Troubleshooting**
> - Output length >>4 Mb: check `raven.log` for “low coverage trimming disabled” and consider pre-filtering reads.
> - Missing `.gfa`: ensure destination directory exists; Raven does not create parent folders.
> - Segfaults on WSL: set `export RAVEN_DISABLE_SIMD=1` as a fallback.
>
> **Alternatives / Variants**
> - `--resume` can restart from partially completed runs.
> - Consider Raven+Medaka polishing or Trycycler ensembles if you need fewer duplications.
>
> **First-Principles Intuition**
> - Raven favors speed and keeps alternative paths rather than forcing consensus, so you expect more contigs and inflated genome length; duplicated BUSCOs downstream confirm the redundancy.

### 2C. Shasta 🟢
**Core Command**
```bash
shasta --input raw/barcode07.fq \
  --assemblyDirectory assemblies/shasta \
  --threads $(nproc) --config Nanopore-May2022
```
**Expected**: 13 contigs, total 3.16 Mb, N50 437 kb. The committed `Assembly/shasta.fasta` holds the published output.

> **Command Breakdown**
> - `--input raw/barcode07.fq`: Shasta ingests raw FASTQ directly.
> - `--assemblyDirectory assemblies/shasta`: target folder storing `Assembly.fasta`, coverage tables, and HTML reports.
> - `--threads $(nproc)`: parallelizes overlapping and polishing phases.
> - `--config Nanopore-May2022`: preset tuned for Q20+ ONT data; controls read-length filters and error models.
>
> **Why These Flags Matter**
> - Preset config defines minimum read length (10 kb here) and coverage targets; misaligned presets either discard too many reads or admit noisy fragments.
> - Setting `--assemblyDirectory` prevents Shasta from writing into `/tmp` and aligns with repo structure.
>
> **Troubleshooting**
> - Too few reads: inspect `ReadSummary.csv` to confirm only 9,968 reads survived; rerun with `--Reads.minReadLength 5000` if coverage allows.
> - Crashes about filesystem permissions: ensure `assemblies/` exists and is writable.
> - Excessive fragmentation: add more polishing (e.g., Medaka) or supply higher-coverage reads.
>
> **Alternatives / Variants**
> - `--config Nanopore-UL` for ultra-long reads, or custom JSON configs for aggressive filtering.
> - `--Align.maxSkip` tweaks alignment sensitivity when assemblies collapse repeats.
>
> **First-Principles Intuition**
> - Shasta prioritizes speed by filtering short reads; the resulting contigs reveal what a conservative assembler produces under limited coverage. Missing BUSCOs later highlight the biological cost of discarding data.

> **Visual reference**
> - `barcode_carousel.pdf`, p. 3 (“Assembly comparison”) juxtaposes Flye/Raven/Shasta contig layouts and karyotype-style bars that match the statistics above.

---

## Step 3. QUAST Assembly Benchmarking 🟢
**Goal**: Compare contiguity metrics (contig counts, N50, GC) across assemblers using a consistent evaluator.

**Inputs**: `assemblies/flye/assembly.fasta`, `assemblies/raven/raven.fasta`, `assemblies/shasta/Assembly.fasta`.

**Core Command**
```bash
conda activate barcode-quast
quast.py \
  -o quast_results \
  -t $(nproc) \
  --labels Flye,Raven,Shasta \
  assemblies/flye/assembly.fasta \
  assemblies/raven/raven.fasta \
  assemblies/shasta/Assembly.fasta
```

**Expected Outputs**: `quast_results/report.txt`, `report.tsv`, `icarus.html`.

> **Command Breakdown**
> - `quast.py assemblies/...`: compares multiple assemblies side by side.
> - `-o quast_results`: writes summaries, TSVs, HTML, and plots into a reproducible folder.
> - `-t $(nproc)`: accelerates alignment-heavy stages.
> - `--labels Flye,Raven,Shasta`: ensures all reports share consistent series names.
>
> **Why These Flags Matter**
> - Without `--labels`, QUAST invents names from filenames; ordering can shift between runs.
> - `-o` allows committing stable reports; reruns do not overwrite older analyses unintentionally.
>
> **Troubleshooting**
> - `ModuleNotFoundError: matplotlib`: re-activate `barcode-quast` or install `matplotlib-base`.
> - `Reference genome not found`: the default mode is reference-free, so ignore unless you add `-r`.
> - Huge runtime: skip large assemblies or use `--fast` for preliminary checks.
>
> **Alternatives / Variants**
> - `merqury.sh` for k-mer-based QV, or `bandage` for graph-level QC.
> - Add `--circos` to plot synteny if you introduce a reference.
>
> **First-Principles Intuition**
> - QUAST quantifies contiguity and GC; Flye’s 2 contigs vs Raven’s 28 highlight structural redundancy, while Shasta’s short N50 shows coverage loss. You interpret GC shifts as potential contamination (Raven’s 46.7%).
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 4 (“QUAST metrics”) reproduces the bar charts for contig counts, N50, and GC% taken from `quast_results/report.txt`.

---

## Step 4. K-mer Agreement with KAT 🟢
**Goal**: Measure how well each assembly captures the raw read k-mer spectrum.

**Inputs**: raw FASTQ plus assembly FASTA.

**Core Command (Flye example)**
```bash
conda activate barcode-kat
kat comp -o "KAT analysis/kat_flye" \
  raw/barcode07.fq assemblies/flye/assembly.fasta
```

> **Command Breakdown**
> - `kat comp`: generates k-mer histograms comparing read and assembly spectra.
> - `-o "KAT analysis/kat_flye"`: target folder for `.stats`, `.mx`, and `.spectra-cn.png`.
> - Inputs are ordered: `raw/barcode07.fq` (truth) first, assembly FASTA second.
>
> **Why These Flags Matter**
> - Using a unique `-o` per assembler prevents overwriting results and mirrors committed artifacts.
> - KAT shells out to Jellyfish; keeping everything within the `barcode-kat` env ensures the dependency is available.
>
> **Troubleshooting**
> - Memory errors (>32 GB): add `--threads 4 --mem 32G` or run on downsampled reads (`seqtk sample`).
> - `kat: command not found`: activate the correct env or reinstall from Bioconda.
> - Empty `.stats`: indicates one of the inputs was empty; recheck FASTA paths.
>
> **Alternatives / Variants**
> - `merqury.sh` can provide similar spectra plus consensus QV if you have Illumina reads.
> - `kat comp -H 20000000` raises the hash size for very large genomes.
>
> **First-Principles Intuition**
> - K-mer agreement quantifies how well assemblies explain every read; Flye’s 148 assembly-only k-mers imply low false positives, while Raven’s thousands highlight duplicated sequence.
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 5 (“KAT spectra”) shows the exact `*.spectra-cn.png` plots for Flye/Raven/Shasta so readers can match the text with color-coded histograms.

---

## Step 5. BUSCO Genome Completeness 🟢
**Goal**: Quantify single-copy ortholog recovery using `bacteria_odb10` lineage.

**Inputs**: same three assemblies.

**Core Command (Flye example)**
```bash
conda activate barcode-busco
busco \
  -i assemblies/flye/assembly.fasta \
  -l bacteria_odb10 \
  -o busco_flye \
  -m genome -f
```

**Expected Outputs**: `Busco Analysis/busco_flye/short_summary...txt/json` (already stored for each assembler).

> **Command Breakdown**
> - `-i assemblies/flye/assembly.fasta`: assembly under evaluation.
> - `-l bacteria_odb10`: lineage dataset specifying the 124 conserved genes expected in bacteria.
> - `-o busco_flye`: output folder name; generates `short_summary*.txt`, JSON, and `full_table.tsv`.
> - `-m genome`: run mode optimized for assembled genomes (vs transcriptome/proteins).
> - `-f`: force overwrite if the folder already exists.
>
> **Why These Flags Matter**
> - Correct lineage selection is crucial; using `gammaproteobacteria` would change expectations and obscure missing genes.
> - `-m genome` instructs BUSCO to detect gene models internally; transcriptome mode would skip necessary steps.
>
> **Troubleshooting**
> - First run downloads data to `~/.config/busco`; ensure you have write permissions or set `BUSCO_CONFIG_FILE`.
> - `ERROR: Program augustus not found`: confirm `barcode-busco` env is active or install missing dependencies.
> - Empty summaries: indicates the input FASTA path was wrong or lacked sequence; check `logs/run_bacteria_odb10.log`.
> - Fewer than 124 entries in `full_table.tsv`: rerun `busco --update-data` to refresh the lineage.
>
> **Alternatives / Variants**
> - `checkm lineage_wf` for genome bins, or `BUSCO --augustus` flags to tweak gene prediction.
> - For Archaea/Metagenomes, switch lineage to `archaea_odb10` or `bacteria_metagenome_odb10`.
>
> **First-Principles Intuition**
> - BUSCO measures gene completeness vs duplication; Flye’s 98.4% complete indicates near-finished genome, Raven’s 44% duplicates confirm redundant contigs, and Shasta’s 16% missing genes reflects under-assembly.
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 6 (“BUSCO completeness”) mirrors the table in `Busco Analysis/busco_*/short_summary*.txt`, with bars for Complete/Fragmented/Missing metrics.

---

## Step 6. Bandage Graph Visualization 🟡
**Goal**: Visually inspect assembly graphs for circularization, repeat tangles, or plasmids.

**Inputs**: `.gfa` files from each assembler.

**Status**: PNG exports already exist in `Bandage Graphs/` via `Bandage image ... docs/flye_graph.png` (see `WORKFLOW.html` lines 324–348).

**Manual Command**
```bash
Bandage image assemblies/flye/assembly_graph.gfa "Bandage Graphs/flye_graph.png"
```

> **Command Breakdown**
> - `Bandage image`: headless export of a `.gfa` graph to PNG.
> - `assemblies/flye/assembly_graph.gfa`: graph built during assembly; change path for Raven/Shasta.
> - `"Bandage Graphs/flye_graph.png"`: destination image committed in the repo.
>
> **Why These Flags Matter**
> - Supplying explicit output filenames keeps Flye/Raven/Shasta renders side-by-side and reproducible.
> - Bandage reads `paths` and `segments` out of the `.gfa`; using the wrong file (e.g., `.gfa.gz`) yields blank images.
>
> **Troubleshooting**
> - `Bandage: command not found`: install the GUI build locally or run via X-forwarding.
> - Blank PNGs: ensure the `.gfa` is complete; Flye writes it to `assembly_graph.gfa`, not the flattened `Assembly/` folder.
> - Colors or fonts unreadable: use `--height`/`--width` flags to resize for publication.
>
> **Alternatives / Variants**
> - `Bandage GUI assemblies/flye/assembly_graph.gfa` for interactive exploration.
> - `odgi viz` provides similar plots via command-line only, useful on headless servers.
>
> **First-Principles Intuition**
> - Graph visualization reveals structural ambiguities hidden by contig FASTA stats. Simple circles confirm Flye’s finished chromosome, whereas Raven’s branching graph foreshadows duplicated BUSCOs.
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 7 (“Bandage graphs”) embeds the PNGs from `Bandage Graphs/*.png`, letting readers compare Flye/Raven/Shasta graph structures visually.

---

## Step 7. 16S Extraction + Phylogeny 🟢
**Goal**: Confirm taxonomic identity and contextualize assemblies phylogenetically.

**Inputs**: Assemblies, tools from `barcode-phylo` env. The repository stores generated FASTA/trees under `16S anno_phylo/` if you prefer to inspect existing results rather than rerun the commands below.

**Core Commands**
1. **Predict rRNA loci (barrnap)**
   ```bash
   barrnap assemblies/flye/assembly.fasta > eval/16s/flye.gff
   ```
   > **Command Breakdown**
   > - `barrnap assemblies/flye/assembly.fasta`: scans the assembly FASTA for rRNA genes using HMM profiles.
   > - `> eval/16s/flye.gff`: writes genomic coordinates and annotations into a GFF file for downstream extraction.
   >
   > **Why These Flags Matter**
   > - No extra flags keeps barrnap’s default bacterial models; adding `--kingdom bac` is optional but redundant.
   > - Directing output to `eval/16s/` aligns with later steps that expect the same path.
   >
   > **Troubleshooting**
   > - Zero hits: confirm the assembly contains complete rRNA operons (coverage issues) or run `barrnap --reject 0` to see low-scoring candidates.
   > - `barrnap: command not found`: activate the `barcode-phylo` env.
   >
   > **Alternatives / Variants**
   > - `aragorn` or `Infernal` can detect tRNAs/rRNAs, but barrnap is fastest for bacterial 16S.
   > - For partial genomes, use `--quiet --evalue 1e-5` to loosen filters.
   >
   > **First-Principles Intuition**
   > - Accurate 16S placement begins with identifying the rRNA operon boundaries; missing hits imply either biological loss or incomplete assemblies.
2. **Filter 16S hits**
   ```bash
   awk '$3=="rRNA" && /product=16S/' eval/16s/flye.gff > eval/16s/flye_16S.gff
   ```
   > **Command Breakdown**
   > - `awk '$3=="rRNA" && /product=16S/'`: keeps only GFF rows where the third column denotes rRNA and the attributes contain `product=16S`.
   > - `> eval/16s/flye_16S.gff`: saves a slim GFF with just 16S loci.
   >
   > **Why These Flags Matter**
   > - Filtering ensures downstream extraction ignores 5S/23S hits that barrnap also reports.
   > - Keeping coordinates in GFF format lets `bedtools getfasta` read strand information.
   >
   > **Troubleshooting**
   > - Empty file: confirm barrnap actually annotated `product=16S` or adjust the regex (e.g., `/16S_rRNA/`).
   > - `awk: command not found` on macOS/Windows: use `gawk` from the `barcode-phylo` env.
   >
   > **Alternatives / Variants**
   > - `grep "product=16S" eval/16s/flye.gff` works for quick inspections but drops structured columns.
   > - Use `seqkit grep -rp "16S"` on FASTA output if you prefer sequence-first filtering.
   >
   > **First-Principles Intuition**
   > - By isolating 16S coordinates you maintain a deterministic bridge from assemblies to phylogenetic markers; mislabelled coordinates break downstream taxonomic inference.
3. **Extract sequences (bedtools)**
   ```bash
   bedtools getfasta -fi assemblies/flye/assembly.fasta \
     -bed eval/16s/flye_16S.gff -s > eval/16s/flye_16S.fasta
   ```
   > **Command Breakdown**
   > - `bedtools getfasta`: slices sequences from the assembly FASTA using genomic intervals.
   > - `-fi assemblies/flye/assembly.fasta`: input FASTA file.
   > - `-bed eval/16s/flye_16S.gff`: interval list including strand info.
   > - `-s`: honors strand orientation so reverse complements are generated automatically.
   > - `> eval/16s/flye_16S.fasta`: outputs the extracted 16S sequences.
   >
   > **Why These Flags Matter**
   > - Using the same FASTA as barrnap ensures coordinates align; mixing assemblies causes empty results.
   > - `-s` is required because 16S loci can sit on either strand; omitting it yields non-biological sequences.
   >
   > **Troubleshooting**
   > - `bedtools: command not found`: confirm `barcode-phylo` env includes bedtools.
   > - Output length zero: check that the chromosome IDs in the GFF match FASTA headers exactly.
   >
   > **Alternatives / Variants**
   > - `seqkit subseq --gtf eval/16s/flye_16S.gff assemblies/flye/assembly.fasta` provides similar functionality and may already be installed.
   > - For multiple loci, combine GFFs (`cat eval/16s/*_16S.gff > eval/16s/all_16S.gff`) before extraction.
   >
   > **First-Principles Intuition**
   > - Extracting the literal nucleotide sequence preserves biological context for downstream BLAST and phylogeny; incorrect extraction cascades into misidentified species.
4. **Multiple alignment + trimming**
   ```bash
   mafft --auto --thread $(nproc) eval/16s/all_16S.fasta > eval/16s/all_16S.aln.fasta
   trimal -automated1 -in eval/16s/all_16S.aln.fasta -out eval/16s/all_16S.trim.fasta
   ```
   > **Command Breakdown**
   > - `mafft --auto --thread $(nproc)`: selects an alignment strategy based on sequence length/number and uses available CPUs.
   > - `> eval/16s/all_16S.aln.fasta`: writes the untrimmed alignment.
   > - `trimal -automated1`: removes poorly aligned columns using heuristics tuned for phylogeny.
   > - `-in ... -out ...`: defines input alignment and trimmed output.
   >
   > **Why These Flags Matter**
   > - `--auto` avoids hard-coding algorithms; MAFFT chooses FFT-NS-2 here, balancing speed and accuracy.
   > - Trimming reduces noisy columns that would otherwise inflate branch support artificially.
   >
   > **Troubleshooting**
   > - MAFFT stuck or OOM: add `--maxiterate 0` or downsample sequences.
   > - TrimAl removing everything: inspect the raw alignment; extremely divergent sequences may require manual parameter tuning (`-gt 0.7`).
   >
   > **Alternatives / Variants**
   > - `muscle` or `clustalo` for alignment; `gblocks` for masking instead of TrimAl.
   > - For rapid drafts, skip trimming but expect lower-quality trees.
   >
   > **First-Principles Intuition**
   > - Phylogenetic accuracy depends on homologous columns. Aligning ensures homologous positions line up, trimming prunes noise so tree-building focuses on genuine substitutions.
5. **Phylogeny**
   ```bash
   iqtree -s eval/16s/all_16S.trim.fasta -m MFP -bb 1000 -alrt 1000 -nt AUTO
   ```

**Expected Outputs**: If you rerun the commands, expect files under `eval/16s/`. The repository already includes the final artifacts in `16S anno_phylo/` (`all_16S.aln.fasta`, `all_16S.trim.fasta`, `16S_tree.nwk`, assembly-specific 16S FASTA files, and ITOL exports).

> **Command Breakdown**
> - `-s eval/16s/all_16S.trim.fasta`: trimmed alignment as tree input.
> - `-m MFP`: ModelFinder selects the best substitution model (usually GTR+F+I+G4 here).
> - `-bb 1000 -alrt 1000`: ultrafast bootstrap and SH-aLRT support for branch confidence.
> - `-nt AUTO`: IQ-TREE selects an appropriate thread count.
>
> **Why These Flags Matter**
> - Accurate models reduce bias; `-m MFP` removes guesswork for beginners.
> - Dual support metrics (bootstrap + aLRT) provide complementary confidence estimates; if they disagree, scrutinize the alignment.
>
> **Troubleshooting**
> - `FATAL ERROR: Alignment has only gaps`: TrimAl may have removed everything; revisit trimming thresholds.
> - Long runtimes: lower bootstrap replicates (`-bb 200`) during drafts.
> - Branch support <70/<0.9: verify that BLAST identities (~99.8% to *A. baumannii*) still hold; low support may indicate contamination or truncated sequences.
>
> **Alternatives / Variants**
> - `fasttree -nt` for quicker exploratory trees.
> - `raxml-ng --all` if you need ML searches with different optimization strategy.
>
> **First-Principles Intuition**
> - The tree places barcode07 relative to reference strains; consistent clustering with known *Acinetobacter* plus high support confirms taxonomic identity. Deviations would demand re-checking assemblies for contamination.
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 8 (“16S phylogeny”) shows the IQ-TREE consensus plus BLAST hit thumbnails corresponding to `16S anno_phylo/16S_tree.nwk` and the BLAST tables captured in `WORKFLOW.html`.

---

## Step 8. BlastKOALA Functional Annotation 🟠
**Goal**: Annotate metabolic pathways via KEGG’s BlastKOALA service.

**Status**: Requires manual uploads to KEGG servers; outputs preserved as `BlastKoala/Screenshot (260-262).png`.

**Manual Procedure**
1. Compress predicted proteins or contigs (FASTA) and upload to https://www.kegg.jp/blastkoala/.
2. Select the Prokaryotic database, submit job, and download the summary.
3. Capture screenshots or export tables.

> **Command (Process) Breakdown**
> - Upload FASTA: BlastKOALA performs DIAMOND-like searches against KEGG Orthology.
> - Choose “Prokaryotes”: ensures bacterial pathways/orthologs are prioritized.
> - Download HTML/TSV or capture screenshots for audit.
>
> **Why These Steps Matter**
> - KO assignments drive downstream pathway charts; choosing the wrong database yields irrelevant modules.
> - Screenshots/exports are the only reproducible artifacts because KEGG jobs are ephemeral.
>
> **Troubleshooting**
> - Upload failures: ensure FASTA <30 MB or split files; KEGG throttles large jobs.
> - No email response: check spam, or rerun using the “for submission” form with a verified address.
> - Pathways missing expected genes: verify annotations (Prokka/Bakta) and consider re-uploading protein FASTA instead of contigs.
>
> **Alternatives / Variants**
> - `eggnog-mapper -i proteins.faa -m diamond` for local KEGG/COG annotation.
> - Local `diamond blastp` against KEGG ortholog FASTA if you have a licensed copy.
>
> **First-Principles Intuition**
> - Functional annotation bridges assemblies to phenotype by mapping predicted proteins to metabolic modules. Manual KEGG steps remain external because licensing/API restrictions prevent shipping the databases here.
>
> **Visual reference**
> - `barcode_carousel.pdf`, p. 9 (“BlastKOALA pathways”) contains cropped screenshots from `BlastKoala/Screenshot (260-262).png`, matching the modules discussed here.

---

## Step 9. Barcode Carousel Summary Deck 🟠
**Goal**: Maintain `barcode_carousel.pdf` as a concise, shareable visual narrative of the workflow for talks, posts, or peer briefings.

**Status**: Manual editing (PowerPoint/Keynote/Canva). The exported PDF is committed so collaborators can cite slide numbers without rebuilding the deck.

> **Process Breakdown**
> - Source data: reuse plots/tables generated in earlier steps (SeqKit, QUAST, KAT, BUSCO, etc.).
> - Authoring: update the slide deck in your preferred editor, then export to PDF as `barcode_carousel.pdf`.
> - Versioning: replace the PDF in git so page numbers remain stable for cross-references throughout this Markdown.
>
> **Why These Steps Matter**
> - Page references in this playbook (pp. 2–10) rely on the current slide order; rearranging slides without updating references breaks the layered-learning experience.
> - Exporting to PDF ensures exact reproduction on GitHub/LinkedIn without needing proprietary software.
>
> **Troubleshooting**
> - Page numbers shifted: adjust references in this Markdown immediately or restore the prior slide order.
> - Plot styles inconsistent: regenerate figures from the documented commands to avoid stale screenshots.
>
> **Alternatives / Variants**
> - Build lightweight HTML dashboards (e.g., Quarto) if you prefer interactive visuals, but keep the PDF as the canonical shared artifact.
>
> **First-Principles Intuition**
> - The deck translates command-level results into visual checkpoints for broader audiences while remaining tethered to reproducible outputs; maintaining alignment preserves trust between the textual playbook and supporting visuals.

> **Visual reference**
> - `barcode_carousel.pdf`, p. 10 (“Summary checkpoints”) distills the headline conclusions referenced throughout this playbook.

---

## Final Scope Statement
- **This workflow _is_** a transparent, audit-grade, beginner-friendly tutorial for assembling and evaluating a single bacterial isolate (`barcode07`) from Nanopore data, complete with exact commands, environments, interpretations, and sanity checks.
- **This workflow _is not_** a hosted web platform, multi-species pipeline, or fully automated service. Manual/external steps (BlastKOALA submissions, Bandage PNG exports, barcode carousel layout tweaks) must still be redone manually. Scaling to other organisms or barcodes requires re-running the documented steps and adjusting parameters accordingly.

## Next Steps & Adaptation Tips
1. Swap `raw/barcode07.fq.gz` (and the decompressed `raw/barcode07.fq`) for other demultiplexed FASTQ files; keep folder structure identical and rerun from Step 1.
2. Add polishing (e.g., Medaka, Racon) if short-read data or higher accuracy is required—extend the playbook in new sections.
3. Once validated, wrap commands into Snakemake/Nextflow or a web interface, but retain this Markdown as the canonical reproducibility record.

## Local Validation – 7 Mar 2026
**File Path Audit**
- ✅ `raw/barcode07.fq.gz`, `Assembly/*.fasta`, `Bandage Graphs/*.png`, `Busco Analysis/*`, `KAT analysis/*`, `quast_results/*`, `16S anno_phylo/*`, `BlastKoala/Screenshot*.png`, `barcode_carousel.pdf`.
- ⚠️ Decompressed `raw/barcode07.fq`, `assemblies/*`, `logs/*`, and `eval/16s/*` are **not** present in the committed repository. Run `gzip -dk raw/barcode07.fq.gz` and re-execute the workflow to regenerate them, or rely on the summarized artifacts noted above.

**Environment Creation Attempts**
- `conda --version` and `micromamba --version` are unavailable in the current validation environment, so the Conda envs listed in `envs/*.yml` could not be materialized here. Ensure Conda/Miniforge or Micromamba is installed locally before running `conda env create -f ...`.

**Assembler Version Smoke Tests (external run, 8 Mar 2026)**
- On a Linux workstation, `conda env create -f envs/assembly.yml` succeeded. Activating `barcode-assembly` and running `flye --version`, `raven --version`, `shasta --version`, `seqkit version`, and `minimap2 --version` returned `2.9.6-b1802`, `1.8.3`, `Release 0.14.0`, `v2.10.0`, and `2.28-r1209` respectively, confirming the environment works as documented.
