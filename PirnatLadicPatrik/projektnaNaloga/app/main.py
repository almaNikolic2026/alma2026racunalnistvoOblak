from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Python CI/CD Demo", version="1.0.0")


class ItemIn(BaseModel):
    name: str
    description: str | None = None


class Item(ItemIn):
    id: int


items_db: dict[int, Item] = {}
next_id = 1


def seed_items() -> None:
    global next_id
    if items_db:
        return

    defaults = [
        ItemIn(name="Item 1", description="Seed item 1"),
        ItemIn(name="Item 2", description="Seed item 2"),
        ItemIn(name="Item 3", description="Seed item 3"),
        ItemIn(name="Item 4", description="Seed item 4"),
    ]
    for payload in defaults:
        item = Item(id=next_id, **payload.model_dump())
        items_db[next_id] = item
        next_id += 1


@app.on_event("startup")
def startup_event() -> None:
    seed_items()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/items", response_model=list[Item])
def list_items() -> list[Item]:
    return list(items_db.values())


@app.post("/items", response_model=Item, status_code=201)
def create_item(payload: ItemIn) -> Item:
    global next_id
    item = Item(id=next_id, **payload.model_dump())
    items_db[next_id] = item
    next_id += 1
    return item


@app.get("/items/{item_id}", response_model=Item)
def get_item(item_id: int) -> Item:
    item = items_db.get(item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item
