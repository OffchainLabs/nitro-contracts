# Test coverage

This guide explains how test coverage is measured in this repository, how to run it locally, how to read the results, and what CI does with them. Coverage is measured with Foundry over the tests in `test/foundry`. The Hardhat tests are not part of the coverage signal; see the [last section](#7-hardhat-coverage) for the standalone tool.

## 1. What coverage measures

Coverage tells you which parts of the contracts in `src` were executed while the test suite ran. Foundry reports four metrics per file and for the whole repository:

| Metric     | Counts                                                                           |
| ---------- | -------------------------------------------------------------------------------- |
| Lines      | Source lines that executed at least once                                         |
| Statements | Individual statements that executed (a line can hold several)                    |
| Branches   | Paths of a conditional that were taken (`if`/`else`, `require`, `revert` guards) |
| Functions  | Functions that were called at least once                                         |

Branch coverage is the most informative of the four. A guard like `if (msg.sender != admin) revert NotOwner()` counts as a covered line as soon as the happy path runs, but the revert side stays uncovered until a test calls it from the wrong address.

Keep these limits in mind when reading a percentage:

- **Executed is not asserted.** A line is covered when any test reaches it, including setup code and tests that never check the outcome. Coverage finds code nobody exercises; it cannot tell you whether the tests would catch a bug in that code.
- **Project versus patch.** The repository-wide number moves slowly and for many reasons. The number that matters on a pull request is patch coverage: the share of the lines the PR touched that a test reached.
- **Only `test/foundry` counts.** Behaviour that is only exercised by the Hardhat tests in `test/contract` or `test/prover`, or by the e2e tests, shows as uncovered.
- **Fuzz inputs are fixed.** Which branches a fuzz test reaches depends on the inputs it draws, so `forge coverage` uses a fixed fuzz seed by default and two runs report the same numbers, locally and in CI. Regular `forge test` runs keep random seeds. Setting a seed yourself, through `FOUNDRY_FUZZ_SEED` or `foundry.toml`, overrides the default and makes the numbers differ from CI's.

## 2. Running coverage locally

Prerequisites: Foundry and the `lcov` package, which provides `genhtml`:

```shell
brew install lcov        # macOS
sudo apt install lcov    # Debian/Ubuntu
```

Generate the report and the HTML view:

```shell
yarn coverage
```

This writes two things at the repository root, both gitignored:

- `lcov.info`, the raw report in LCOV format
- `coverage/`, an HTML report; open `coverage/index.html` in a browser

It also prints a per-file summary table in the terminal. To get only the table and `lcov.info`, without the HTML step, run what CI runs:

```shell
yarn coverage:ci
```

Both commands run `forge coverage` under the `test` Foundry profile.

A full run takes under a minute, but every contract is recompiled without the optimizer. To iterate on one area, pass the usual Forge filters through, for example:

```shell
FOUNDRY_PROFILE=test forge coverage --match-contract InboxTest
genhtml lcov.info --branch-coverage --output-dir coverage --ignore-errors inconsistent
```

The second command refreshes the HTML report, which `forge coverage` itself does not touch. A filtered run only reports what the selected tests reach, including the contracts their setup deploys and calls; everything else looks uncovered. It also overwrites `lcov.info`, so run the full command again before comparing totals with CI.

## 3. Configuration

Coverage settings live in `foundry.toml` under `[profile.test.coverage]`:

| Setting         | Value                                 | Effect                                                                  |
| --------------- | ------------------------------------- | ----------------------------------------------------------------------- |
| `report`        | `summary`, `lcov`                     | Print the table and write `lcov.info`                                   |
| `exclude_tests` | `true`                                | Keep test contracts out of the report                                   |
| `skip_files`    | `src/mocks/**`, `src/test-helpers/**` | Mocks and helpers exist only to support tests, so they are not measured |

The `test` profile itself turns the optimizer off. `forge coverage` always compiles without the optimizer so that source maps line up with the original Solidity, and this repository's contracts compile fine that way. Do not add `--ir-minimum`: it is meant for projects that hit stack-too-deep errors without the optimizer, and here it is the flag that causes them.

`yarn coverage` passes `--ignore-errors inconsistent` to `genhtml`. Forge records a single branch for an `if (...) revert` guard with no `else`, so when the revert side is never taken, the LCOV file contains a line that executed with zero branches taken. Recent `lcov` releases treat that as a corrupt file by default. The flag turns it into a warning and does not affect the numbers.

## 4. Reading the results

The terminal table lists each file with its four metrics and ends with a `Total` row. Low branch coverage next to high line coverage usually means the error paths are untested.

The HTML report is the quickest way to find what to test. Open the file you are working on and look for red lines (never executed) and for the branch markers next to conditionals; a `-` next to one side of a branch means that side was never taken. Lines highlighted in blue executed at least once.

For a text-only view of what is missing, Forge can print every uncovered item directly:

```shell
FOUNDRY_PROFILE=test forge coverage --report debug
```

Passing `--report` replaces the configured report list, so this run prints the list and writes no `lcov.info`.

### Example

Every cell in the terminal table is a percentage followed by the covered and total counts:

```text
| File                                            | % Lines        | % Statements   | % Branches   | % Funcs       |
| src/assertionStakingPool/AbsBoldStakingPool.sol | 89.47% (17/19) | 86.67% (13/15) | 33.33% (1/3) | 100.00% (4/4) |
```

In this row every function was called and all but two lines ran. The three branches are the three `if (...) revert` guards in the contract, and only one of them was ever triggered. The two uncovered lines are the other two `revert` statements. Low branch coverage next to high line coverage usually means exactly this: the happy paths are tested and the error paths are not.

## 5. Improving coverage

Coverage is a map of what tests do not reach, not a target to chase. When a file you changed shows uncovered lines:

1. Decide whether the line should be tested at all. If a path is intentionally left untested, say why in the PR instead of writing a test that only executes the line.
2. For the rest, add a test in `test/foundry` that asserts the behaviour, not merely one that reaches the code. For a guard, that means a test that expects the revert.
3. Re-run coverage with a filter on the test contract you touched and check the file again.

## 6. Coverage in CI

The `Coverage (Foundry)` job in `.github/workflows/contract-tests.yml` runs on every pull request and on pushes to `develop`. It runs `yarn coverage:ci` and uploads `lcov.info` to [Codecov](https://about.codecov.io/) with the `foundry` flag.

The job sets no fuzz seed. `forge coverage` already uses a fixed one, so the base and head commits of a PR draw the same fuzz inputs, patch coverage does not drift between pushes, and a local `yarn coverage` reproduces the CI numbers.

### What Codecov does with the upload

Codecov behaviour is configured in `codecov.yml` at the repository root:

- **A comment on the PR**, posted once and updated on each push, with the overall coverage and its change against the base branch, the patch coverage, and the list of changed files with uncovered lines.
- **A `codecov/patch` status check** that reports patch coverage. It is informational: it shows the number but always passes.
- **No `codecov/project` status.** The repository-wide number is not used to judge a PR, because deleting well-tested code or adding code that is intentionally left untested lowers it for good reasons.

## 7. Hardhat coverage

A standalone command remains for the Hardhat tests:

```shell
yarn coverage:hardhat
```

It runs the `solidity-coverage` plugin over `test/contract/*.spec.ts` and `test/prover/*.ts` and writes its report to `coverage/hardhat/`, as configured in `.solcover.js`. It is not run in CI, its numbers are not merged with the Foundry report, and the plugin measures coverage by rewriting the Solidity sources before compiling, so its results are not directly comparable to Forge's. The prover tests only produce coverage when the proof fixtures in `test/prover/proofs/` exist; those are generated by Nitro's CI, not by this repository, so locally that part of the run is empty.
