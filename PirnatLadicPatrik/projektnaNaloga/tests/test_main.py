from fastapi.testclient import TestClient

from app.main import app, items_db

client = TestClient(app)


def setup_function() -> None:
    items_db.clear()


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_and_get_item() -> None:
    create_response = client.post(
        "/items", json={"name": "Test item", "description": "Created in tests"}
    )
    assert create_response.status_code == 201
    created = create_response.json()
    assert created["name"] == "Test item"

    get_response = client.get(f"/items/{created['id']}")
    assert get_response.status_code == 200
    assert get_response.json()["description"] == "Created in tests"


def test_get_missing_item() -> None:
    response = client.get("/items/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Item not found"
