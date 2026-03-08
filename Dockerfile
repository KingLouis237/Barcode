FROM mambaorg/micromamba:1.5.8

ARG MAMBA_DOCKERFILE_ACTIVATE=1
WORKDIR /workspace

COPY envs /opt/envs

SHELL ["/bin/bash","-c"]

RUN for fname in assembly quast kat busco phylo; do \
      micromamba env create -y -f /opt/envs/${fname}.yml && \
      micromamba clean --all --yes; \
    done

ENV PATH=/opt/conda/bin:${PATH}

ENTRYPOINT ["/bin/bash"]
