from collections.abc import Callable, Iterable
from typing import Any, TypeVar, overload

T = TypeVar('T')


def group_errors(message: str, functions: Iterable[Callable[[], T]]) -> list[T]:
    """
    Run all the given functions and raise an exception group that combines all the exceptions
    they raised if any of them did so.
    """

    results: list[T] = []
    errors: list[Exception] = []
    for function in functions:
        try:
            results.append(function())
        except Exception as error:
            errors.append(error)

    if errors != []:
        raise ExceptionGroup(message, errors)

    return results


T1 = TypeVar('T1')
T2 = TypeVar('T2')
T3 = TypeVar('T3')
T4 = TypeVar('T4')


@overload
def group_errors_tuple(
    message: str,
    f1: Callable[[], T1],
) -> tuple[T1]: ...

@overload
def group_errors_tuple(
    message: str,
    f1: Callable[[], T1],
    f2: Callable[[], T2],
) -> tuple[T1, T2]: ...

@overload
def group_errors_tuple(
    message: str,
    f1: Callable[[], T1],
    f2: Callable[[], T2],
    f3: Callable[[], T3],
) -> tuple[T1, T2, T3]: ...

@overload
def group_errors_tuple(
    message: str,
    f1: Callable[[], T1],
    f2: Callable[[], T2],
    f3: Callable[[], T3],
    f4: Callable[[], T4],
) -> tuple[T1, T2, T3, T4]: ...


def group_errors_tuple(message: str, *functions: Callable[[], Any]) -> tuple[Any, ...]:  # type: ignore
    """
    Run all the given functions and raise an exception group that combines all the exceptions
    they raised if any of them did so.
    """

    return tuple(group_errors(message, functions))
