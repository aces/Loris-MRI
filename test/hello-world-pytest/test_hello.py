# test_hello.py
from hello import say_hello

def test_say_hello():
    assert say_hello() == "Hello, World!"
