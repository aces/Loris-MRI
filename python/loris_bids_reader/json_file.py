
import json
from pathlib import Path
from typing import Generic, TypeVar

from pydantic import BaseModel

T = TypeVar('T', bound=BaseModel)


class BIDSJSONFile(Generic[T]):
    path: Path
    data: T

    def __init__(self, model_class: type[T], path: Path):
        self.path = path
        with open(self.path) as file:
            sidecar_data = json.load(file)
        self.data = model_class(**sidecar_data)
