# LORIS-MRI Python tooling

## Virtual environment

LORIS-MRI uses a Python virtual environment to manage its execution context and dependencies. To activate the virtual environment, use the command `source environment` in the LORIS-MRI root directory. The dependencies of the virtual environment are listed in the `pyproject.toml` file.

## Configuration

The LORIS-MRI Python tools are configured in the `pyproject.toml` file in the LORIS-MRI root directory.

## Linting

LORIS-MRI Python uses the Ruff linter to ensure a consistent coding style that adheres to the Python community guidelines.

To run Ruff, use the following commands in the LORIS-MRI root directory:
* `ruff check` to run the linter and report style errors.
* `ruff check --fix` to automatically fix trivial linting errors such as unsorted imports.

## Type checking

LORIS-MRI Python uses type hints and the Pyright type checker [^3] to improve the robustness and maintainability of the code.

To run Pyright, use the following commands in the LORIS-MRI root directory:
* `pyright` to run the strict type checker, which type checks modern LORIS-MRI Python type-hinted modules with a strict configuration.
* `pyright --project test` to run the global type checker, which type checks all the LORIS-MRI Python modules including untyped legacy code with a (very) loose configuration.

When interacting with legacy code or untyped libraries in modern modules, you can use `# type: ignore` or `cast(type, value)` to ignore type checking errors.

[^3]: Although we use Pyright, Mypy is also an excellent alternative type checker.

## Testing

LORIS-MRI Python uses the Pytest library to handle unit and integration tests.

### Unit testing

The LORIS-MRI Python unit tests are located in the `python/tests/unit` directory.

To run the LORIS-MRI Python unit tests, use the command `pytest` in the root LORIS-MRI directory.

### Integration testing

The LORIS-MRI integration tests are located in the `python/tests/integration` directory.

The LORIS-MRI integration tests require a more complex testing environment with the following:
- A (partial) copy of the main LORIS repository.
- A copy of the S3 LORIS-MRI test dataset.
- A LORIS database Docker image with the LORIS-MRI test dataset.
- A LORIS-MRI code Docker image with all the required dependencies installed.

To run the LORIS-MRI integration tests, use the command `test/run_integration_tests.sh` in the root LORIS-MRI directory.

Note that the first run of the LORIS-MRI integration test run might take some time, as the test data must be downloaded and the Docker images must be created. However, much of this setup should be cached in the Docker cache as well as the LORIS-MRI test cache directory (by default `~/.cache/loris/test`), so further test runs should be much faster. To avoid downloading data and building images locally, it is also possible to run the LORIS-MRI integration tests remotely by simply creating a pull request, which will trigger the LORIS-MRI CI workflow.
