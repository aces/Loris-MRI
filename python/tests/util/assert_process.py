import subprocess


def assert_process(
    command: list[str],
    return_code: int,
    stdout: str | None,
    stderr: str | None,
):
    """
    Run the provided command and check that its return code, standard output message, and standard
    error message contain their expected values. A `None` value means that the message must be
    empty.
    """

    # Run the script to test
    process = subprocess.run(command, capture_output=True, text=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout}')
    print(f'STDERR:\n{process.stderr}')

    # Check that the actual return code is equal to the expected return code
    assert process.returncode == return_code

    # Check that the actual output message matches or contains the expected error message
    if stdout is not None:
        assert stdout in process.stdout
    else:
        assert process.stdout == ""

    # Check that the actual error message matches or contains the expected error message
    if stderr is not None:
        assert stderr in process.stderr
    else:
        assert process.stderr == ""
