from collections.abc import Callable, Iterable, Iterator, Sized
from typing import TypeVar

T = TypeVar('T')


def count(iterable: Iterable[T]) -> int:
    """
    Count the number of elements in an iterable.

    If the iterable is sized, this function uses the `__len__` method.
    If the iterable is an iterator, this function consumes the iterator.
    """

    if isinstance(iterable, Sized):
        return len(iterable)

    count = 0
    for _ in iterable:
        count += 1

    return count


T = TypeVar('T')  # type: ignore


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


T = TypeVar('T')  # type: ignore


def flatten(iterables: Iterable[Iterable[T]]) -> Iterator[T]:
    """
    Flatten an iterable of iterables into a single iterator.
    """

    for iterable in iterables:
        yield from iterable
