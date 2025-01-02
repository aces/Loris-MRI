from typing import Callable, Iterable, Iterator, TypeVar

T = TypeVar('T')


def find(predicate: Callable[[T], bool], iterable: Iterable[T]) -> T | None:
    """
    Find the first element in an iterable that satisfies a predicate, or return `None` if no match
    is found.
    """

    for item in iterable:
        if predicate(item):
            return item

    return None


T = TypeVar('T')  # type: ignore
U = TypeVar('U')


def filter_map(function: Callable[[T], U | None], iterable: Iterable[T]) -> Iterator[U]:
    """
    Apply a function to each element of an iterator and yields the results that are not `None`.
    """

    for item in iterable:
        result = function(item)
        if result is not None:
            yield result


def try_parse_int(value: str) -> int | None:
    """
    Parse a string into an integer (base 10), or return `None` if the string does not correspond
    to an integer.
    """

    try:
        return int(value)
    except ValueError:
        return None
