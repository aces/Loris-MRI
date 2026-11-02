from collections.abc import Callable, Iterable
from textwrap import indent
from typing import Any, TypeVar, cast, overload

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


def format_exception(error: BaseException) -> str:
    """
    Format an exception to a string, displaying sub-exceptions and exception causes in an indented
    tree.
    """

    message = str(error)
    error_type = type(error)
    children: list[BaseException] = []

    # Add the sub-exceptions as children if the exception is a group exception.
    if isinstance(error, BaseExceptionGroup):
        group = cast(BaseExceptionGroup[BaseException], error)
        message = group.message
        children.extend(group.exceptions)

    # Add the cause as a child if the exception has one.
    cause = error.__cause__
    if cause is not None:
        children.append(cause)

    # Use the exception class name as its message if the exception has no message.
    if message == '':
        message = error_type.__name__

    messages = [message]

    # Add each child exception as a new message with one more indentation level.
    for child in children:
        messages.append(indent(format_exception(child), '  '))

    return '\n'.join(messages)
