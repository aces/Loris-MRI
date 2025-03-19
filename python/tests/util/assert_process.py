import subprocess


def assert_process(
    command: list[str],
    return_code: int,
    stdout_msg: str | None,
    stderr_msg: str | None
):
    # Run the script to test
    process = subprocess.run(command, capture_output=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout.decode()}')
    print(f'STDERR:\n{process.stderr.decode()}')

    # Isolate STDOUT message and check that it contains the expected error message
    if stdout_msg:
        error_msg_is_valid = True if stdout_msg in process.stdout.decode() else False
        assert error_msg_is_valid is True

    # Isolate STDERR message and check that it contains the expected error message
    if stderr_msg:
        error_msg_is_valid = True if stderr_msg in process.stdout.decode() else False
        assert error_msg_is_valid is True

    # Check that return code, standard error and standard output are correct
    assert process.returncode == return_code
    if not stdout_msg:
        assert process.stdout == b''
    if not stderr_msg:
        assert process.stderr == b''
