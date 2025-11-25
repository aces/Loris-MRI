import os

FileTree = dict[str, 'FileTree'] | None
"""
Type that represents a file hierarchy relative to a path.
- `None` means that the path refers to a file.
- `dict[str, FileTree]` means that the path refers to a directory, with the entries of the
  dictionary as sub-trees.
"""


def assert_files_exist(path: str, file_tree: FileTree):
    """
    Assert that all the directories and files specified in a path exist.
    """

    if file_tree is None:
        assert os.path.isfile(path)
        return

    assert os.path.isdir(path)

    for sub_dir_name, sub_file_tree in file_tree.items():
        sub_dir_path = os.path.join(path, sub_dir_name)
        assert_files_exist(sub_dir_path, sub_file_tree)
