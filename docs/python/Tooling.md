# LORIS-MRI Python tooling

## Virtual environment

LORIS-MRI uses a Python virtual environment to manage its execution context and dependencies. To activate the virtual environment, use the command `source environment` in the LORIS-MRI root directory. The dependencies of the virtual environment are listed in the `install/requirements/requirements.txt` file.

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
- A copy of the main LORIS repository.
- A file system mount of the S3 LORIS-MRI test dataset.
- A LORIS database Docker image with the LORIS-MRI test dataset.
- A LORIS-MRI code Docker image with all the required dependencies installed.

To run the LORIS-MRI integration tests, use the command `pytest python/tests/integration` in the root LORIS-MRI directory **inside the LORIS-MRI code Docker image**.

As of December 2024, there is no easy way to set up and run this environment locally. You can however use the LORIS-MRI GitHub Actions workflow (that is, create a pull request) to set up this environment and run the integration tests in GitHub.
