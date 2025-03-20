import subprocess


def run_integration_script(command: list[str]):
    """
    Run the provided command, print its STDOUT and STDERR for debugging purposes and return the process object.
    """

    # Run the script to test
    process = subprocess.run(command, capture_output=True, text=True)

    # Print the standard output and error for debugging
    print(f'STDOUT:\n{process.stdout}')
    print(f'STDERR:\n{process.stderr}')

    return process
