# Reproducible Playbook for Bacterial Genome Assembly from ONT Barcode07 Reads

_Last updated: 7 March 2026_

## Background
- **Problem**: Convert Nanopore raw signal demultiplexed as `barcode07` into an interpretable bacterial genome plus QC evidence. Raw FASTQ reads (~10 kb average length) are not yet an assembled genome; they require error correction, layout, polishing, and validation before biological interpretation.
- **What does a barcode mean?** ONT ligation kits tag each library with unique adapter sequences; Guppy then demultiplexes reads. `barcode07` refers to the seventh barcode in the ONT EXP-NBD104/114 set and represents a single bacterial isolate within a multiplexed run. Selecting this barcode isolates one sample without cross-talk from other isolates.
- **Why bacterial genome assembly?** Bacterial genomes are typically 3–6 Mb and often circular. Long-read assembly can resolve repeats and plasmids, but tooling/parameters strongly influence contiguity and accuracy, so documenting the process is essential for trust.
- **Why multiple assemblers + evaluation tools?** Different assemblers make different trade-offs (speed vs accuracy, repeat handling, read filtering). Running Flye, Raven, and Shasta side-by-side, then validating with QUAST, KAT, BUSCO, Bandage, and 16S analyses exposes strengths, weaknesses, and gives readers intuition about comparing pipelines.

> **Canonical vs archival sources**
> - This Markdown playbook is the **only maintained source of truth** for the BARCODE workflow. All new edits happen here.
> - `BARCODE_project/WORKFLOW.html` is retained solely as a historical/raw log. It preserves original commands verbatim but now carries a banner deferring to this document.
> - `BARCODE_project/barcode_carousel.pdf` houses supporting figures (screenshots, graphs). Each step below points to the relevant slide as “Visual reference” where it meaningfully reinforces the text.

## How to Use This Playbook
1. **Core Flow First** – Each step begins with a concise summary (goal, inputs, canonical command, expected files).
2. **Layered Deep Dives** – Callouts titled *Command Breakdown*, *Sanity Check*, *Troubleshooting*, or *Intuition Builder* expand on flags, reasoning, and diagnostics.
3. **Reproducibility Labels** – Every step carries a badge so you know what can be rerun as-is.
   - 🟢 **Fully Reproducible (FR)**: All inputs, commands, and outputs are in `BARCODE_project` or generated deterministically.
   - 🟡 **Conditionally Reproducible (CR)**: Requires large downloads, internet access, or cloud quotas but still scripted.
   - 🟠 **Manual / External (ME)**: Relies on GUI/web tools; we provide artifacts plus instructions to redo manually.
4. **Scientific Sanity Checks** – Instead of quizzes, checkpoints show what success/failure looks like so you can reason about deviations.

## Repository Layout & Data Availability
- Unless otherwise noted, commands assume your working directory is `BARCODE_project`.
- **Raw reads ship in compressed form.** The repo includes `raw/barcode07.fq.gz`. Run `gzip -dk raw/barcode07.fq.gz` once at the start of any session so that `raw/barcode07.fq` exists for all commands. You do _not_ need to supply your own FASTQ unless you want to test a different barcode.
- **Intermediate working folders are intentionally absent.** Directories such as `assemblies/*`, `logs/*`, and `eval/16s/*` are large, so regenerate them locally by rerunning the documented commands whenever you need the full context.
- **Reference FASTAs are flattened for convenience.** The repo keeps one copy of each assembler’s final FASTA under `Assembly/` (e.g., `Assembly/flye.fasta`). These mirror what you would find in `assemblies/flye/assembly.fasta` after rerunning Flye.
- 16S deliverables are stored in `16S anno_phylo/`. When the playbook references `eval/16s/*`, read it as “regenerate under `eval/16s`, or consult the saved files in `16S anno_phylo/`.”
- Bandage PNGs (`Bandage Graphs/*.png`), BUSCO/QUAST/KAT outputs, BlastKOALA screenshots, and the curated visual deck `barcode_carousel.pdf` are committed exactly as referenced for crosschecking.
- Paths highlighted as missing during validation are documented in the **Local Validation – 7 Mar 2026** section at the end of this file.
- `BARCODE_project/WORKFLOW.html` remains available if you need to see the original unedited command transcript; treat it as archival/raw data only.

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
| Presentation + Video Packaging | 🟠 | `Presentation_flot.pptx`, `Video_present_flot.mp4` |

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
> - `conda env create -f envs/assembly.yml`: installs python 3.9 with flye=2.9.6-b1802, raven-assembler=1.8.3, shasta=0.14.0, seqkit=2.10.0, and minimap2=2.28 inside `barcode-assembly`. (Samtools is omitted here to avoid the current zlib conflict; use another env if you need it.)

> **Sanity Check**
> - Run `conda env list` and verify all five envs exist.

> **Troubleshooting**
> - BUSCO pulls heavy dependencies (Augustus, HMMER). If installation fails, create that env separately: `conda env create -f envs/busco.yml --name tmp && conda rename tmp barcode-busco`.
> - Bandage GUI is not bundled; we rely on PNGs generated via `Bandage image` already stored under `Bandage Graphs/`.
> - Need `samtools` alongside the assemblers? Install it after the fact (`conda install -n barcode-assembly samtools=1.18`) or use one of the evaluation envs that already include it.
> - The `barcode-kat` env now pins `python=3.9` alongside KAT itself. KAT normally pulls Jellyfish in automatically; if Conda ever omits it, install manually with `conda install -n barcode-kat -c bioconda jellyfish`.

---

## Step 1. Raw Read Quality Control (SeqKit) 🟢
**Goal**: Verify barcode07 read yield, length distribution, and per-base quality before assembly.

**Inputs**: `raw/barcode07.fq` (ONT basecalled FASTQ) generated locally by decompressing the committed `raw/barcode07.fq.gz`.

> **Prep**
> ```bash
> gzip -dk raw/barcode07.fq.gz   # leaves the compressed file in place while creating raw/barcode07.fq
> ```

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
> - `seqkit stats`: summarizes FASTQ lengths and quality.
> - `-a`: adds quartiles (Q1/Q2/Q3) and quality percentages, enabling deeper QC without extra tooling.

> **Intuition Builder**
> - Average read length (~10.6 kb) and N50 (24.6 kb) tell you these data are long enough to span bacterial repeats.
> - GC 41% matches typical *Acinetobacter* spp., hinting at minimal contamination.

> **Sanity Check**
> - Coverage estimate = 392,624,046 / 3,780,699 ˜ 104×. Anything <30× would risk fragmented assemblies.

> **Common Pitfalls**
> - If Q20 drops below 75%, expect more polishing rounds or pre-assembly filtering.
> - Unexpected GC peaks may indicate barcode bleed-through; re-check demultiplexing settings.

> **Visual reference**
> - `barcode_carousel.pdf` – “Raw QC & Coverage” slide summarizes the SeqKit table and read-length violin plots that correspond to this step.

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
> - `--nano-hq`: treats reads as high-quality ONT (supplants the deprecated `--plasmids`).
> - `--out-dir assemblies/flye`: organizes logs/polishing steps for future auditing.

> **Sanity Check**
> - `grep -c '^>' assemblies/flye/assembly.fasta` should return `2`.
> - L50 = 1, meaning one contig covers =50% of the genome (see `WORKFLOW.html` lines 40–44).

> **Troubleshooting**
> - If Flye crashes due to RAM, reduce `--threads` to limit memory.
> - If you see more than two contigs, inspect coverage spikes for possible contamination.

### 2B. Raven 🟢
**Core Command**
```bash
raven --threads $(nproc) \
  --graph assemblies/raven/raven.gfa \
  raw/barcode07.fq > assemblies/raven/raven.fasta 2> logs/raven.log
```
**Expected**: 28 contigs totaling 6.40 Mb, largest 3.77 Mb. The committed `Assembly/raven.fasta` mirrors the canonical `assemblies/raven/raven.fasta`.

> **Intuition Builder**
> - Raven keeps more alternative paths; duplicated BUSCOs later flag this redundancy.

> **Sanity Check**
> - `seqkit stats assemblies/raven/raven.fasta | grep sum_len` ˜ 6.4 Mb. If far larger, trimming failed.

### 2C. Shasta 🟢
**Core Command**
```bash
shasta --input raw/barcode07.fq \
  --assemblyDirectory assemblies/shasta \
  --threads $(nproc) --config Nanopore-May2022
```
**Expected**: 13 contigs, total 3.16 Mb, N50 437 kb. The committed `Assembly/shasta.fasta` holds the published output.

> **Common Pitfall**
> - Shasta discards reads <10 kb; confirm with `ReadSummary.csv` that 9,968 reads remained. Low coverage explains missing BUSCOs later.

> **Visual reference**
> - `barcode_carousel.pdf` – “Assembly comparison” slide juxtaposes Flye/Raven/Shasta contig layouts and karyotype-style bars that match the statistics above.

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
> - `--labels` enforces consistent naming, so plots align with assembly order.
> - `icarus.html` visualizes contig placement; open in a browser for manual inspection.

> **Interpretation Snapshot** (`quast_results/report.txt` lines 3–25)
> - Flye: 2 contigs, N50 3,773,355 bp, GC 39.08%.
> - Raven: 28 contigs, same N50 but GC 46.73% and total length 6.40 Mb (suggests duplication).
> - Shasta: fragmented; N50 437,312 bp, GC 39.09%.

> **Sanity Check**
> - Recompute GC using `seqkit fx2tab -n -l -g`. Values should match ±0.01%.

> **Troubleshooting**
> - If QUAST fails due to missing matplotlib backend, ensure you ran it inside `barcode-quast` env.

> **Visual reference**
> - `barcode_carousel.pdf` – “QUAST metrics” slide reproduces the bar charts for contig counts, N50, and GC% taken from `quast_results/report.txt`.

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
> - `kat comp`: counts k-mers in each dataset and produces paired spectra files (`*.mx`, `.stats`, `.spectra-cn.png`).
> - `-o "KAT analysis/kat_flye"`: writes all artifacts into a dedicated subfolder next to the provided outputs.
> - Jellyfish is required because KAT shells out to it for raw k-mer counting; if the `barcode-kat` environment creation ever skips Jellyfish, install it manually (`conda install -n barcode-kat -c bioconda jellyfish`).

**Expected Outputs**: `KAT analysis/kat_flye.stats`, `.mx`, `.spectra-cn.png` (already generated for all three assemblers).

> **Interpretation Snapshot** (`kat_flye.stats` lines 1–38)
> - Shared distinct k-mers: 3,724,890 (˜99.85% completeness).
> - Assembly-only k-mers: 148 (very low false positives).
> - For Raven, assembly-only k-mers = 7,905 (mild redundancy). Shasta shows only 3,019 but also fewer shared k-mers (3,109,356), signaling missing sequence.

> **Sanity Check**
> - Plot `*.spectra-cn.png`; a clean single peak indicates consistent coverage. Extra peaks suggest copy-number artifacts.

> **Troubleshooting**
> - KAT can require >32 GB RAM. Use `--threads 4` and subsample reads if memory constrained.

> **Visual reference**
> - `barcode_carousel.pdf` – “KAT spectra” slide shows the exact `*.spectra-cn.png` plots for Flye/Raven/Shasta so readers can match the text with color-coded histograms.

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

> **Interpretation Snapshot**
> - Flye: C:98.4% [S:98.4, D:0.0], F:1.6, M:0.0 (`...busco_flye.txt` line 9).
> - Raven: C:99.2% but D:44.4% duplicates (line 9 of raven summary) ? redundant contigs.
> - Shasta: C:78.2%, M:16.1% missing (line 9 of shasta summary) ? under-assembly.

> **Sanity Check**
> - Ensure `run_bacteria_odb10/full_table.tsv` lists 124 BUSCO IDs. Missing entries mean the lineage download failed—rerun with `busco --update-data`.

> **Troubleshooting**
> - On first run, BUSCO downloads `bacteria_odb10`; keep `~/.config/busco` cached to avoid repeated downloads.

> **Visual reference**
> - `barcode_carousel.pdf` – “BUSCO completeness” slide mirrors the table in `Busco Analysis/busco_*/short_summary*.txt`, with bars for Complete/Fragmented/Missing metrics.

---

## Step 6. Bandage Graph Visualization 🟡
**Goal**: Visually inspect assembly graphs for circularization, repeat tangles, or plasmids.

**Inputs**: `.gfa` files from each assembler.

**Status**: PNG exports already exist in `Bandage Graphs/` via `Bandage image ... docs/flye_graph.png` (see `WORKFLOW.html` lines 324–348).

> **Manual Step**
> - To regenerate, install Bandage manually (GUI requires desktop). Command-line export:
>   ```bash
>   Bandage image assemblies/flye/assembly_graph.gfa "Bandage Graphs/flye_graph.png"
>   ```
> - This is ?? because the original run required a GUI-capable environment; PNGs are included for reference.

> **Sanity Check**
> - Flye graph shows a single circular contig plus a small bubble.
> - Raven graph contains multiple branches, mirroring duplicated BUSCO findings.

> **Visual reference**
> - `barcode_carousel.pdf` – “Bandage graphs” slide embeds the PNGs from `Bandage Graphs/*.png`, letting readers compare Flye/Raven/Shasta graph structures visually.

---

## Step 7. 16S Extraction + Phylogeny 🟢
**Goal**: Confirm taxonomic identity and contextualize assemblies phylogenetically.

**Inputs**: Assemblies, tools from `barcode-phylo` env. The repository stores generated FASTA/trees under `16S anno_phylo/` if you prefer to inspect existing results rather than rerun the commands below.

**Core Commands**
1. **Predict rRNA loci (barrnap)**
   ```bash
   barrnap assemblies/flye/assembly.fasta > eval/16s/flye.gff
   ```
2. **Filter 16S hits**
   ```bash
   awk '$3=="rRNA" && /product=16S/' eval/16s/flye.gff > eval/16s/flye_16S.gff
   ```
3. **Extract sequences (bedtools)**
   ```bash
   bedtools getfasta -fi assemblies/flye/assembly.fasta \
     -bed eval/16s/flye_16S.gff -s > eval/16s/flye_16S.fasta
   ```
4. **Multiple alignment + trimming**
   ```bash
   mafft --auto --thread $(nproc) eval/16s/all_16S.fasta > eval/16s/all_16S.aln.fasta
   trimal -automated1 -in eval/16s/all_16S.aln.fasta -out eval/16s/all_16S.trim.fasta
   ```
5. **Phylogeny**
   ```bash
   iqtree -s eval/16s/all_16S.trim.fasta -m MFP -bb 1000 -alrt 1000 -nt AUTO
   ```

**Expected Outputs**: If you rerun the commands, expect files under `eval/16s/`. The repository already includes the final artifacts in `16S anno_phylo/` (`all_16S.aln.fasta`, `all_16S.trim.fasta`, `16S_tree.nwk`, assembly-specific 16S FASTA files, and ITOL exports).

> **Command Breakdown**
> - `mafft --auto`: picks the best algorithm for sequence length automatically.
> - `iqtree -m MFP`: ModelFinder selects the best substitution model; `-bb/-alrt` add support values.

> **Sanity Check**
> - BLAST hits show =99.8% identity to *Acinetobacter baumannii* (lines 525–557), matching GC insights.
> - Tree placement groups barcode07 sequences with *Acinetobacter* reference sequences.

> **Troubleshooting**
> - If `barrnap` produces no 16S hits, verify assembly coverage; missing rRNA operons often mean under-assembly or mis-annotation.

> **Visual reference**
> - `barcode_carousel.pdf` – “16S phylogeny” slide shows the IQ-TREE consensus plus BLAST hit thumbnails corresponding to `16S anno_phylo/16S_tree.nwk` and the BLAST tables captured in `WORKFLOW.html`.

---

## Step 8. BlastKOALA Functional Annotation 🟠
**Goal**: Annotate metabolic pathways via KEGG’s BlastKOALA service.

**Status**: Requires manual uploads to KEGG servers; outputs preserved as `BlastKoala/Screenshot (260-262).png`.

**Manual Procedure**
1. Compress predicted proteins or contigs (FASTA) and upload to https://www.kegg.jp/blastkoala/.
2. Select the Prokaryotic database, submit job, and download the summary.
3. Capture screenshots or export tables.

> **Reproducibility Note**
> - Because KEGG imposes account limits and lacks a fully open API, we classify this as 🟠. Screenshots serve as audit artifacts; redo manually if needed.

> **Sanity Check**
> - Modules enriched for antibiotic resistance should match known *Acinetobacter* biology. Discrepancies may indicate contamination or annotation errors.

> **Visual reference**
> - `barcode_carousel.pdf` – “BlastKOALA pathways” slide contains cropped screenshots from `BlastKoala/Screenshot (260-262).png`, matching the modules discussed here.

---

## Step 9. Presentation & Video Packaging 🟠
**Goal**: Communicate findings via `Presentation_flot.pptx` and `Video_present_flot.mp4`.

**Status**: Manual editing/recording; files live at the project root.

> **Note**: These artifacts summarize the workflow but are not scriptable, so they remain 🟠.

> **Visual reference**
> - `barcode_carousel.pdf` – closing slide previews the talk/video thumbnails to illustrate how findings were communicated.

---

## Final Scope Statement
- **This workflow _is_** a transparent, audit-grade, beginner-friendly tutorial for assembling and evaluating a single bacterial isolate (`barcode07`) from Nanopore data, complete with exact commands, environments, interpretations, and sanity checks.
- **This workflow _is not_** a hosted web platform, multi-species pipeline, or fully automated service. Manual/external steps (BlastKOALA, presentation design, some Bandage usages) must still be redone manually. Scaling to other organisms or barcodes requires re-running the documented steps and adjusting parameters accordingly.

## Next Steps & Adaptation Tips
1. Swap `raw/barcode07.fq.gz` (plus its decompressed companion `raw/barcode07.fq`) for other demultiplexed FASTQ files; keep folder structure identical and rerun from Step 1.
2. Add polishing (e.g., Medaka, Racon) if short-read data or higher accuracy is required—extend the playbook in new sections.
3. Once validated, wrap commands into Snakemake/Nextflow or a web interface, but retain this Markdown as the canonical reproducibility record.

## Local Validation – 7 Mar 2026
**File Path Audit**
- ✅ `raw/barcode07.fq.gz`, `Assembly/*.fasta`, `Bandage Graphs/*.png`, `Busco Analysis/*`, `KAT analysis/*`, `quast_results/*`, `16S anno_phylo/*`, `BlastKoala/Screenshot*.png`, `Presentation_flot.pptx`, `Video_present_flot.mp4`.
- ⚠️ The decompressed `raw/barcode07.fq`, `assemblies/*`, `logs/*`, and `eval/16s/*` are **not** present in the committed repository. Produce them by running `gzip -dk raw/barcode07.fq.gz` and re-executing the workflow, or rely on the summarized artifacts noted above.

**Environment Creation Attempts**
- `conda --version` and `micromamba --version` are unavailable in the current validation environment, so the Conda envs listed in `envs/*.yml` could not be materialized here. Ensure Conda/Miniforge or Micromamba is installed locally before running `conda env create -f ...`.

**Assembler Version Smoke Tests (external run, 8 Mar 2026)**
- On a Linux workstation, `conda env create -f envs/assembly.yml` succeeded. Activating `barcode-assembly` and running `flye --version`, `raven --version`, `shasta --version`, `seqkit version`, and `minimap2 --version` returned `2.9.6-b1802`, `1.8.3`, `Release 0.14.0`, `v2.10.0`, and `2.28-r1209` respectively, confirming the environment works as documented.
