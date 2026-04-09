# Contributing

This document describes how you can contribute to the UGREEN DXP FAN NAS Driver. Please read it carefully.

**Table of Contents**

* [What contributions are accepted](#what-contributions-are-accepted)
* [Build instructions](#build-instructions)
* [Pull upstream changes into your fork regularly](#pull-upstream-changes-into-your-fork-regularly)
* [How to get your pull request accepted](#how-to-get-your-pull-request-accepted)
  * [Keep your pull requests limited to a single issue](#keep-your-pull-requests-limited-to-a-single-issue)
    * [Squash your commits to a single commit](#squash-your-commits-to-a-single-commit)
  * [Don't mix code changes with whitespace cleanup](#dont-mix-code-changes-with-whitespace-cleanup)
  * [Keep your code simple!](#keep-your-code-simple)
  * [Test your changes!](#test-your-changes)
  * [Write a good commit message](#write-a-good-commit-message)

## What contributions are accepted

Contributions are highly appreciated, especially in the following areas:

- **Bug fixes** in the `it87` driver or the installer/uninstaller scripts
- **New NAS model support** — if your UGREEN DXP model isn't listed, open an issue first with your chipset details before submitting a PR
- **Documentation improvements** — README corrections, clearer install steps, additional distro coverage
- **Kernel compatibility fixes** — the driver targets the latest upstream kernel; patches that extend support to new kernel versions are welcome

Please push to your fork and [submit a pull request][pr].

We try to review pull requests as fast as possible. If we find issues, we may suggest changes before merging.

## Build instructions

See the [README.md][build_instructions] for package requirements and step-by-step build instructions for your distribution.

## Pull upstream changes into your fork regularly

The driver is actively maintained and kernel compatibility patches land frequently. Pull upstream changes into your fork regularly to avoid rejected PRs due to divergence.

To pull in upstream changes:

    git remote add upstream https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver.git
    git fetch upstream main

Check the log before merging:

    git log upstream/main

Then rebase your changes:

    git rebase upstream/main

Force push afterwards:

    git push --force

For more info, see [GitHub Help][help_fork_repo].

## How to get your pull request accepted

### Keep your pull requests limited to a single issue

PRs should be as small and focused as possible. Large, wide-sweeping changes will be **rejected** with comments to split them up. Some examples:

* If you are fixing a build warning in the C driver, don't restructure the Makefile at the same time.
* If you are adding support for a new NAS model, don't refactor unrelated pwmconfig logic in the same PR.

#### Squash your commits to a single commit

Keep the project history clean — one logical change, one commit. To squash the last N commits:

    git reset --soft HEAD~{N} && git commit
    git push --force

### Don't mix code changes with whitespace cleanup

Whitespace-only cleanups must be in their own separate PR. A diff that mixes functional changes with formatting noise is unreadable and will be **rejected**.

### Keep your code simple!

Keep C and shell code clean and readable:

* Meaningful variable names over single-letter abbreviations
* Comments where kernel API behaviour is non-obvious
* No dead code or commented-out blocks left in

### Test your changes!

Before submitting:

- Build the module cleanly: `make clean && make -j$(nproc)`
- Verify DKMS install: `sudo make dkms && dkms status it87`
- Confirm `sensors` shows expected output on your hardware
- Confirm `fancontrol` starts and controls fan speed correctly
- Test across a reboot to catch module load ordering issues

PRs that introduce regressions or are untested on real hardware will be **rejected**.

### Write a good commit message

* Explain **why** the change is necessary, not just what it does.
* Reference the relevant issue number where applicable.

  For example: `Fix PWM channel mapping for DXP6800Pro, closes #6`

[//]: # (LINKS)
[pr]: https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/compare
[build_instructions]: https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/blob/main/README.md
[help_fork_repo]: https://help.github.com/articles/fork-a-repo/
