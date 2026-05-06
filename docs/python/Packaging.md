# LORIS Python packaging

This document aims to explain how _packaging_ works in LORIS Python. Packaging is the process of declaring, bundling, and distributing the LORIS Python code, dependencies, and metadata such that they can easily and reliably be installed and used by the LORIS administrator or developer.

The LORIS Python installation process should take care of installing LORIS Python on the host machine without needing the user to know the intricacies of Python or LORIS Python packaging. As such, this documentation is aimed at developers or power users that want to have a more granular control or better understanding of the LORIS Python packaging process.

## Overview of Python packaging

LORIS Python uses standard Python packaging tools, the official Python packaging documentation is available [here](https://packaging.python.org/en/latest/).

### Package

A Python package is a collection of Python code (modules, scripts, and resources) along with its dependencies and metadata (name, version, author...). Packages allow Python code to be reliably shared, installed, and reused.

Packages can be hosted on a package repository such as [PyPI](https://pypi.org/) (the Python Package Index) or located in a local directory.

Python packages are installed using package managers such as [`pip`](https://pip.pypa.io/). For example:

```sh
pip install requests                 # From PyPI.
pip install /path/to/local/package   # From the local LORIS Python directory.
```

Once a package is installed, it may provide modules to be used in Python via `import` statements, and eventually commands to be run in the shell.

When installing a package from a local directory, `pip` offers two modes:
- Non-editable (default) that copies the package files to the current environment.
- Editable (option `-e` or `--editable`) that instead uses a link to the original source.

This distinction is important for LORIS Python development. If you install a local package in non-editable mode, changes you make to the code will not be reflected in the program behavior. Therefore, it is strongly advised to install local packages such as LORIS Python packages in editable mode during development:

```sh
pip install -e /path/to/local/package
```

### Virtual environment

A Python virtual environment is an isolation layer that allows to install a set of Python packages without impacting or being impacted by the rest of the system.

LORIS Python uses a virtual environment to install itself and its dependencies. The virtual environment is created during the LORIS Python installation process and depends on the `python3.XY-venv` system dependency (`3.XY` referring to the Python version of the virtual environment).

The LORIS Python virtual environment can be created manually using the following command:

```sh
python3.XY -m venv --prompt loris .venv
```

- `-m venv` refers to the `venv` Python module, which creates the virtual environment.
- `--prompt loris` is the name of the virtual environment, which is only used for description purposes.
- `.venv` is to the path of the directory in which the virtual environment files will be created, a virtual environment is usually located in a `.venv` directory in the root directory of its associated project.

To use a package installed in a Python virtual environment, that virtual environment needs to be activated, this can be done by sourcing the `activate` file of the virtual environment using the following command:

```sh
source .venv/bin/activate
```

Note that the LORIS Python virtual environment is sourced in the LORIS Python `environment` file, which should itself be sourced in the user's `.bashrc` file.

In Bash, the activated Python virtual environment is typically indicated by its name between parentheses in the command prompt:

```
(loris) lorisadmin@loris:/opt/loris/bin/mri$
```

Once a Python virtual environment is activated, commands such as `pip install` will install packages within that environment, and those installed packages can freely be used using Python imports or shell commands.

To exit a virtual environment, simply use the `deactivate` command:

```sh
deactivate
```

## Package architecture

LORIS Python is not a single Python package but is rather a modular project composed of multiple packages. The metadata of each package is specified in its `pyproject.toml` file, and notably explicitly specifies its dependencies on external packages or other LORIS packages.

The LORIS Python packages can conceptually be organized into layers, where a package of a lower layer should never depend on a package of a higher layer.

**Utility packages**

These are the lowest-level packages, they provide helper functions and tools and can be used without a LORIS instance installed.

Examples: `loris-utils`, `loris-bids-reader`

**Core package**

This is a single package that provides shared code used to interact with a LORIS instance, most notably for configuration, database access, and file system operations.

At the time of this writing, the core package is not a true Python package but rather a module named `lib`. However, it shall be later reorganized into a true `loris-core` Python package.

**Module packages**

These packages provide isolated features or pipelines that may or may not be installed in a given LORIS instance. Since these packages depend on a LORIS instance being present, they should at least depend on the LORIS core package.

Examples: `loris-dicom-importer`, `loris-bids-importer`

**Top-level package**

The top-level `loris` package depends on the lower-level LORIS Python packages and aggregates them into a single metapackage. As such, installing the `loris` package installs all the other LORIS utility, core, and module packages.

Note that the top-level `loris` package does not necessarily need to depend on **all** lower-level LORIS Python packages. Instead, the exact packages it depends on may configured using Python package features, which allows to selectively choose which LORIS Python module packages should be installed.

## Installation

The LORIS Python packages can be installed with `pip` in non-editable mode using the following command:

```sh
pip install /path/to/loris/python
```

Note that the path to LORIS Python usually looks like `/opt/loris/bin/mri`.

However, as said previously, it is strongly advised to install LORIS Python in editable mode. There are two methods to do so, either using `pip` (default) or `uv` (simplest).

### Option 1: Using PIP

[`pip`](https://pip.pypa.io/) is the default Python package manager that comes bundled with most Python distributions. While it sees widespread use, `pip` does not yet have good support for multi-package projects, and notably always installs a package dependencies in non-editable mode. As such, using `pip install -e loris` will install the top-level `loris` package in editable mode, but will install its dependencies like `loris-core` or `loris-bids-importer` in non-editable mode.

Thankfully, this limitation can be worked around easily using the following commands:

```sh
# Step 1: Go to the LORIS Python directory.
cd /path/to/loris/python
# Step 2: Install the top-level LORIS Python package in editable mode.
# This step will also install all LORIS subpackages and dependencies in non-editable mode.
pip install -e .
# Step 3: Re-install each LORIS subpackage in editable mode without re-installing its dependencies.
for package in ./python/loris_*; do pip install --no-deps -e $package; done
```

### Option 2: Using UV

[`uv`](https://docs.astral.sh/uv/) is a popular third-party package manager for Python. Compared to `pip`, it notably offers better performance and has good support for multi-package projects. The `uv` installation guide can be found in the official documentation available [here](https://docs.astral.sh/uv/getting-started/installation/).

Once `uv` is installed, LORIS Python and all its packages can be installed in editable mode using the following command:

```sh
uv pip install -e /path/to/loris/python
```

Note that the `uv pip ...` command just means that `uv` emulates a `pip`-like interface, `uv` does not use `pip` under the hood.

## Versioning and release

All LORIS Python packages have their own package metadata and therefore their own version. However, the LORIS Python packages should still follow the [semantic versioning](https://packaging.python.org/en/latest/discussions/versioning/) convention and comply with the following rules:
- All LORIS Python packages should share the same _major_ version. For instance, for LORIS 29, all LORIS Python packages should have a `29.x.y` version.
- Individual LORIS Python packages may increment their _minor_ version, however, dependent packages should then also be updated.
- Individual LORIS Python packages can increment their _patch_ version without updating dependent packages.

During LORIS Python releases, the versions of all LORIS Python packages should be updated appropriately.

## Package-less packaging (deprecated)

Before LORIS Python used proper Python packaging, it made its Python code available to the environment through the `PYTHONPATH` environment variable, which is notably still used by some projects to selectively override some files im the `lib` module.

While the `PYTHONPATH` environment variable is no longer used by the LORIS Python installation process, the old behavior can still be recovered using the following commands:

```sh
# Step 1: Proceed to the standard LORIS Python installation described earlier.
# Step 2: Go to the LORIS Python directory.
cd /path/to/loris/python
# Step 3: Uninstall the top-level LORIS package.
# Note that this does not uninstall the LORIS Python subpackages and dependencies.
pip uninstall .
# Step 4: Add the LORIS Python packages directtory (which notably contains the `lib` module) to the
#`PYTHONPATH` variable.
# Note that this line should also be added to the LORIS Python environment file using absolute paths.
export PYTHONPATH = $PYTHONPATH:$(pwd)/python
```

This behavior is deprecated and may no longer work in the future. To override core LORIS Python files, it is now advised to properly fork the LORIS Python core package and modify the relevant files.
