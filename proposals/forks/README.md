# Proposal Fork Registry

This directory records proposal lineage discovered from proposal text in this
repo.

## Files

- `lineage.tsv`: extracted proposal-to-proposal relationships.
- `448x.tsv`: inventory of the 448x proposal files and their source refs.
- `extract_relations.sh`: regenerates `lineage.tsv` from the current proposal
  tree.

The current tree has 9 files in the 448x series. `448x.tsv` records upstream
source refs from `SOURCES.tsv`; these are source refs, not local Git branches.

## `lineage.tsv` schema

The file is tab-separated with this header:

```text
child_msc	parent_msc	relation	confidence	child_path	evidence
```

Field meanings:

- `child_msc`: the downstream or newer proposal.
- `parent_msc`: the upstream proposal it refers to.
- `relation`: normalized relationship label.
- `confidence`: `direct` when the text states a fork/supersession-like
  relationship, `derived` when the text states a weaker lineage relationship
  such as `builds on`.
- `child_path`: repo-relative path to the child proposal.
- `evidence`: the matching source line trimmed to a single line.

## Relationship labels

- `supersedes`
- `superseded_by`
- `replaces`
- `parallel_exploration`
- `incorporates_attempt`
- `builds_on`
- `extends`
- `depends_on`

## Regeneration

Run:

```sh
proposals/forks/extract_relations.sh
```

The script only uses local proposal text and does not try to infer lineage from
topic similarity.
