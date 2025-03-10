import os

FileTree = dict[str, 'FileTree'] | None
"""
Type that represents a file hierarchy relative to a path.
- `None` means that the path refers to a file.
- `dict[str, FileTree]` means that the path refers to a directory, with the entries of the
  dictionary as sub-trees.
"""


def check_file_tree(path: str, file_tree: FileTree):
    """
    Check that a path has at least all the directories and files of a file tree.
    """

    if file_tree is None:
        return os.path.isfile(path)

    if not os.path.isdir(path):
        return False

    for sub_dir_name, sub_file_tree in file_tree.items():
        sub_dir_path = os.path.join(path, sub_dir_name)
        if not check_file_tree(sub_dir_path, sub_file_tree):
            return False

    return True
