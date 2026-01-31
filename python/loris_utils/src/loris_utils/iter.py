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


def find(iterable: Iterable[T], predicate: Callable[[T], bool]) -> T | None:
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


def filter_map(iterable: Iterable[T], function: Callable[[T], U | None]) -> Iterator[U]:
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


def replace_or_append(elements: list[T], value: T, predicate: Callable[[T], bool]) -> None:
    """
    Replace the first element of a list that satisfies a predicate with a value, or append that
    value to the list.
    """

    for i, element in enumerate(elements):
        if predicate(element):
            elements[i] = value
            return

    elements.append(value)
