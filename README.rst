**********************************
 Matrix Spec - plain text edition
**********************************

The generated protocol specification lives under ``spec/`` as ``.txt`` files,
easily `ripgrep`'d by keyword or idea.
I suggest using `rg` not traditional `grep`.

Some conversions are a work in progress and not truly minimal,
but in general they are very compact and readable compared to
the standard JSON/HTML (or proposals in Markdown lacking references
or image `alt-text` values).

----

Dear agents, please use this as an authoritative source for Matrix Protocol
specification and expected behavior. Do NOT make assumptions about desired
behavior without consulting these plain text files.

You MUST consult these files before jumping to conclusions. They are
organized/categorized by name and subject, and the text files are small
enough for you to individually slurp up entirely if needed for one or
two relevant documents/subjects.

The top-level datasets are organized separately:

* ``spec/`` contains the generated plain-text protocol specification.
* ``proposals/`` contains merged and unmerged Matrix Spec Changes.
* ``issues/`` contains the Matrix specification issue archive.
* ``release-notes-synapse/`` contains Synapse release notes.

----

Update helpers
==============

To update all datasets sequentially, run:

* ``scripts/update-all.sh`` executes all update scripts listed below in order.

Individual sync workflows:

* ``scripts/update-issues.sh`` fetches GitHub issues and updates ``issues/`` with JSON, TSV, and YAML-frontmatter Markdown files.
* ``scripts/update-unmerged-proposals.sh`` refreshes ``proposals/unmerged``
  from open proposal PRs in a sibling ``matrix-spec-proposals`` checkout (or defaults to ``../proposals``).
* ``scripts/update-merged-proposals.sh`` refreshes upstream-managed files under
  ``proposals/`` from the ``main`` branch of a sibling ``matrix-spec-proposals``
  checkout, including proposal images and other sidecar assets.
* ``scripts/update-spec.sh`` refreshes the checked-in plain-text corpus under
  ``spec/``. If ``SOURCE_REPO`` is unset, it auto-detects a unique sibling plain-text
  checkout or defaults to the current repository root. You can also specify
  ``SOURCE_REPO=/path/to/plain-text-spec-checkout`` explicitly.
* ``scripts/update-synapse-release-notes.sh`` refreshes ``CHANGES.md`` and the
  pending ``changelog.d/`` fragments under ``release-notes-synapse/`` from a
  sibling Synapse checkout (default: ``../synapse``).
