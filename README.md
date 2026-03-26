# Transparent ONT Bacterial Assembly Case Study

This repository documents a logic-first, reproducible walkthrough of assembling and interpreting an *Acinetobacter* barcode (ONT barcode07).  
It is not a one-click pipeline. Instead, it shows every command, environment, QC step, and manual checkpoint so learners can reason about long-read bacterial genomics from first principles.

## Repository Layout

```
BARCODE/
├── BARCODE_project/
│   ├── Assembly/            # Flattened FASTA outputs (Flye/Raven/Shasta)
│   ├── Bandage Graphs/      # PNGs exported from Bandage
│   ├── BlastKoala/          # Manual KEGG screenshots
│   ├── Busco Analysis/      # BUSCO summaries (TXT/JSON)
│   ├── KAT analysis/        # KAT spectra, stats, plots
│   ├── quast_results/       # QUAST reports
│   ├── 16S anno_phylo/      # 16S extraction + IQ-TREE outputs
│   ├── raw/                 # you supply `barcode07.fq.gz`; `.gitkeep` keeps the folder in Git
│   ├── WORKFLOW.html        # archival command log (defers to the Markdown playbook)
│   └── barcode_carousel.pdf # legacy carousel containing screenshots of every step of the workflow
├── docs/
│   ├── REPRO_PLAYBOOK.md    # canonical Markdown playbook (maintained)
│   └── Barcode07_...pdf     # current 7-slide scientific carousel
├── envs/                    # Conda environment YAMLs (assembly, quast, kat, busco, phylo)
└── README.md                # (this file)
```

## Prerequisites

- Linux shell (WSL Ubuntu works) with Conda or Micromamba.
- Ability to download or otherwise supply the barcodeXX FASTQ locally.  
  Place `barcode07.fq.gz` under `BARCODE_project/raw/`. The file is **not** tracked in Git history because of size constraints.
- Internet access for BUSCO lineage downloads, BlastKOALA uploads, etc.

## Quick Start

1. **Clone the repo**
   ```bash
   git clone https://github.com/KingLouis237/Barcode.git
   cd Barcode
   ```
2. **Create environments** (see `envs/`):
   ```bash
   conda env create -f envs/assembly.yml
   conda env create -f envs/quast.yml
   conda env create -f envs/kat.yml
   conda env create -f envs/busco.yml
   conda env create -f envs/phylo.yml
   ```
   *(Micromamba works too; the Markdown playbook contains troubleshooting tips.)*
3. **Place your FASTQ**
   ```bash
   cp /path/to/barcode07.fq.gz BARCODE_project/raw/
   gzip -dk BARCODE_project/raw/barcode07.fq.gz
   ```
4. **Follow `docs/REPRO_PLAYBOOK.md`**
   - Step 1: SeqKit stats (`barcode-assembly` env) → `raw/seqkit_stats.txt`.
   - Step 2: Run Flye, Raven, Shasta; find flattened FASTAs in `Assembly/`.
   - Step 3-4: `barcode-quast` / `barcode-kat` envs for QUAST + KAT reports.
   - Step 5: BUSCO (bacteria_odb10 lineage) → `Busco Analysis/`.
   - Step 6: Bandage image exports (`Bandage Graphs/*.png` already committed).
   - Step 7: 16S extraction + IQ-TREE (barrnap → MAFFT → TrimAl → IQ-TREE).
   - Step 8: BlastKOALA upload (manual 🟠) with screenshots preserved in `BlastKoala/`.
   - Step 9: Wrap-up; keep `docs/REPRO_PLAYBOOK.md` as the source of truth.

## Key Principles

- **Transparency:** Every command and flag is documented in the playbook.  
- **Reproducibility:** Modular Conda envs + local raw FASTQ path; committed outputs (Assembly, BUSCO, KAT, etc.) provide reference checkpoints.  
- **Interpretability:** QUAST/KAT/BUSCO/Bandage/16S/KEGG are all included so you can reason about assemblies, not just run them.  
- **Manual honesty:** External or GUI steps (Bandage, BlastKOALA) are labeled 🟡/🟠 in the playbook so readers know what remains hands-on. This was done to also enhance understanding of underlying steps.

## Artifacts for Sharing

- `docs/Barcode07_ A Transparent ONT Assembly Case Study.pdf` – 7-slide carousel for social posts.
- `docs/REPRO_PLAYBOOK.md` – full tutorial with layered callouts.
- `BARCODE_project/WORKFLOW.html` – raw legacy log retained for auditing.

## Contributing / Issues

This is an educational case study maintained by Ancestra Genomics.  
If you find errors or want to extend the workflow (new assemblers, other barcodes, polishing steps), open an issue or submit a PR with your reasoning clearly documented.

---

**Reminder:** The repo will never host raw FASTQs. Keep your data local, follow the documented steps, and adapt the logic to your own isolates responsibly.
